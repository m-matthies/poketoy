import AppKit
import IOKit.ps
import OSLog
import PokeToyCore
import ServiceManagement

/// What the configurable global shortcuts do.
enum ShortcutAction: CaseIterable {
    case feed, catchGame, showHide

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .catchGame: return "Start / End Catch Game"
        case .showHide: return "Show / Hide Pets"
        }
    }
}

/// A wild Pokémon's catalog entry with its loaded sprites.
private struct LoadedWild: Sendable {
    let entry: CatalogEntry
    let sprites: SpriteSet
}

/// Owns the settings, the sprite store and the playground, and drives the 60 Hz tick.
@MainActor
final class AppModel {
    private(set) var settings: Settings
    private(set) var playground: Playground
    private let store: SpriteStore
    private let evolutionStore: EvolutionStore
    /// What each pet can evolve into (empty: final form); missing until PokeAPI answered.
    private var evolutionOptions: [UUID: [CatalogEntry]] = [:]
    /// Pets whose evolution lookup is in flight, and when a lookup last failed (retried after a while).
    private var evolutionLookups: Set<UUID> = []
    private var evolutionFailedAt: [UUID: Date] = [:]
    /// Pets whose new sprites are downloading; they can't evolve again meanwhile.
    private var evolving: Set<UUID> = []
    private var tickCount = 0
    private let worldMonitor = WorldMonitor()
    private var petViews: [UUID: PetController] = [:]
    private var itemViews: [UUID: ItemController] = [:]
    private var wildSprites: [String: SpriteSet] = [:]
    /// This round's wild Pokémon by path, and which path each spawned wild has.
    private var rosterSpecs: [String: WildSpec] = [:]
    private var wildPaths: [UUID: String] = [:]
    // Windows are made when first shown; refreshing one that was never opened is a no-op.
    private var pokedexWindowIfOpened: PokedexWindowController?
    private var pokedexWindow: PokedexWindowController {
        if let window = pokedexWindowIfOpened { return window }
        let window = PokedexWindowController(model: self)
        pokedexWindowIfOpened = window
        return window
    }
    private var gameAttempt = UUID()
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private lazy var starterWindow = StarterWindowController(model: self)
    private var preferencesWindowIfOpened: PreferencesWindowController?
    private var preferencesWindow: PreferencesWindowController {
        if let window = preferencesWindowIfOpened { return window }
        let window = PreferencesWindowController(model: self)
        preferencesWindowIfOpened = window
        return window
    }
    private var petsWindowIfOpened: PetsWindowController?
    private var petsWindow: PetsWindowController {
        if let window = petsWindowIfOpened { return window }
        let window = PetsWindowController(model: self)
        petsWindowIfOpened = window
        return window
    }
    /// Shortcuts are off while a new one is being recorded.
    private var shortcutsSuspended = false
    /// What's registered now, so unrelated preference changes don't re-register (or rebuild menus).
    private var registeredShortcuts: [ShortcutAction: Shortcut] = [:]
    private var autoHideState = AutoHideState()
    private var lastAutoHideCheck: CFTimeInterval = 0
    private var lastPowerCheck: CFTimeInterval = 0
    private var sessionInactive = false
    private let notifier = Notifier()
    private var lastPomodoroCheck: CFTimeInterval = 0
    private var hotKeys: [GlobalHotKey] = []
    /// Shortcuts macOS refused because another app already uses them.
    private(set) var unavailableShortcuts: Set<ShortcutAction> = []
    /// Hidden by the auto-hide rules (a full-screen app, or one from the list, is in front).
    private var autoHidden = false
    /// Battery saver: the tick rate, and whether the screen is locked or asleep (ticking paused).
    private var tickInterval = 1.0 / 60
    private var screenLocked = false
    private var screensAsleep = false
    private var onBattery = false
    /// Called when menus need rebuilding (their shortcuts changed).
    var onMenusChanged: (() -> Void)?
    private lazy var gameUI = GameController(model: self)
    private let logger = Logger(subsystem: "local.poketoy.PokeToy", category: "app")

    init() {
        let settings = Settings.load(from: .standard)
        self.settings = settings
        playground = Playground(seed: .random(in: .min ... .max), scale: CGFloat(settings.scale),
                                friendships: Friendships(points: settings.friendships))
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeToy", isDirectory: true)
        store = SpriteStore(cacheDirectory: caches,
                            bundledSprites: Bundle.main.resourceURL?.appendingPathComponent("Sprites", isDirectory: true),
                            bundledPortraits: Bundle.main.resourceURL?.appendingPathComponent("Portraits", isDirectory: true))
        evolutionStore = EvolutionStore(cacheDirectory: caches.appendingPathComponent("pokeapi", isDirectory: true))
    }

    func start() {
        // Current pets belong in the Pokédex too (also covers pets from before it tracked them).
        for record in settings.pets { recordInPokedex(record) }
        settings.save(to: .standard)
        worldMonitor.mainScreenOnly = settings.preferences.screens == .main
        worldMonitor.start()
        for record in settings.pets {
            Task {
                do {
                    attach(record, sprites: try await loadSprites(record.spritePath))
                } catch {
                    logger.error("Couldn't load \(record.spritePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        observeScreenLock()
        onBattery = Self.isOnBattery()
        applyPreferences()
        if settings.pomodoro != nil { notifier.prepare() }
        refreshEvolutionOptions()
        if !settings.starterChosen { showStarterChoice() }
    }

    // MARK: - Preferences

    func showPreferences() {
        preferencesWindow.show()
    }

    func showPets() {
        petsWindow.show()
    }

    /// `save: false` for rapid changes (a slider being dragged); the last one saves.
    func updatePreferences(save shouldSave: Bool = true, _ change: (inout Preferences) -> Void) {
        change(&settings.preferences)
        applyPreferences()
        if shouldSave { save() }
    }

    func shortcut(for action: ShortcutAction) -> Shortcut? {
        switch action {
        case .feed: return settings.preferences.feedShortcut
        case .catchGame: return settings.preferences.catchGameShortcut
        case .showHide: return settings.preferences.showHideShortcut
        }
    }

    func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        updatePreferences { prefs in
            switch action {
            case .feed: prefs.feedShortcut = shortcut
            case .catchGame: prefs.catchGameShortcut = shortcut
            case .showHide: prefs.showHideShortcut = shortcut
            }
        }
    }

    /// Pushes the preferences into the playground, the world, the shortcuts and the tick rate.
    private func applyPreferences() {
        let prefs = settings.preferences
        playground.petSpeed = CGFloat(prefs.petSpeed)
        playground.napAfter = prefs.naps.seconds
        if worldMonitor.mainScreenOnly != (prefs.screens == .main) {
            worldMonitor.mainScreenOnly = prefs.screens == .main
            worldMonitor.refresh()
        }
        let wanted = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.compactMap { action in
            shortcut(for: action).map { (action, $0) }
        })
        if wanted != registeredShortcuts {
            registerShortcuts()
            onMenusChanged?()
        }
        updatePacing()
        updateAutoHide()
    }

    private func registerShortcuts() {
        for hotKey in hotKeys { hotKey.unregister() }
        hotKeys = []
        unavailableShortcuts = []
        registeredShortcuts = [:]
        for action in ShortcutAction.allCases {
            guard let shortcut = shortcut(for: action) else { continue }
            registeredShortcuts[action] = shortcut
            guard !shortcutsSuspended else { continue }
            let hotKey = GlobalHotKey(shortcut) { [weak self] in self?.perform(action) }
            if hotKey.isRegistered { hotKeys.append(hotKey) } else { unavailableShortcuts.insert(action) }
        }
    }

    /// While a new shortcut is being recorded, the current ones mustn't fire (not even after other changes).
    func suspendShortcuts() {
        shortcutsSuspended = true
        for hotKey in hotKeys { hotKey.unregister() }
        hotKeys = []
    }

    func resumeShortcuts() {
        guard shortcutsSuspended else { return }
        shortcutsSuspended = false
        registerShortcuts()
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .feed: feed()
        case .catchGame: if isGameRunning { endCatchGame() } else { startCatchGame() }
        case .showHide: toggleHidden()
        }
    }

    // MARK: - Pomodoro

    var pomodoro: Pomodoro? { settings.pomodoro }
    var pomodoroOptions: PomodoroOptions { settings.preferences.pomodoro }

    /// "🍅 Focus — 12:34 left", for menus.
    var pomodoroStatus: String? {
        guard let timer = settings.pomodoro else { return nil }
        if timer.isWaiting {
            return timer.phase == .focus ? "🍅 Ready for the next focus?" : "☕️ Time for a \(timer.phase.title.lowercased())"
        }
        let icon = timer.phase == .focus ? "🍅" : "☕️"
        return "\(icon) \(timer.phase.title) — \(Pomodoro.clock(timer.remaining(at: Date()))) left"
            + (timer.isPaused ? " (paused)" : "")
    }

    /// The countdown shown above the pet carrying the timer.
    func pomodoroBadge(for id: UUID) -> String? {
        guard let timer = settings.pomodoro, timer.petID == id else { return nil }
        if timer.isWaiting { return timer.phase == .focus ? "🍅 Ready?" : "☕️ Break?" }
        let icon = timer.isPaused ? "⏸" : timer.phase == .focus ? "🍅" : "☕️"
        return "\(icon) \(Pomodoro.clock(timer.remaining(at: Date())))"
    }

    func startPomodoro(_ phase: Pomodoro.Phase, on id: UUID) {
        if var timer = settings.pomodoro {
            timer.petID = id
            timer.start(phase, at: Date(), options: pomodoroOptions)  // keeps the count towards the long break
            settings.pomodoro = timer
        } else {
            settings.pomodoro = Pomodoro(petID: id, phase: phase, now: Date(), options: pomodoroOptions)
        }
        playground.stopSeekingAttention()
        if pomodoroOptions.notifications { notifier.prepare() }
        save()
    }

    func pausePomodoro() {
        settings.pomodoro?.pause(at: Date())
        playground.stopSeekingAttention()
        save()
    }

    func resumePomodoro() {
        settings.pomodoro?.resume(at: Date())
        playground.stopSeekingAttention()
        save()
    }

    /// Ends the current focus or break now (quietly: the player chose it).
    func skipPomodoro() {
        _ = settings.pomodoro?.skip(at: Date(), options: pomodoroOptions)
        playground.stopSeekingAttention()
        save()
    }

    func stopPomodoro() {
        settings.pomodoro = nil
        playground.stopSeekingAttention()
        save()
    }

    func movePomodoro(to id: UUID) {
        settings.pomodoro?.petID = id
        save()
    }

    /// The user is looking (opened a pet's menu): pets can stop trying to get their attention.
    func noticedPets() {
        playground.stopSeekingAttention()
    }

    /// When a focus or break runs out: the pet reacts and a notification says what's next.
    private func checkPomodoro() {
        let options = pomodoroOptions
        guard var timer = settings.pomodoro, let outcome = timer.advance(at: Date(), options: options) else { return }
        settings.pomodoro = timer
        save()
        let name = settings.pets.first { $0.id == timer.petID }?.name ?? "Your Pokémon"
        let title: String, body: String
        switch outcome {
        case .focusDone(let next):
            playground.celebrate(timer.petID)
            // A finished focus counts towards evolving the pet that carried the timer (skipped ones don't).
            if let index = settings.pets.firstIndex(where: { $0.id == timer.petID }) {
                settings.pets[index].focusSessions += 1
                save()
                petsChanged()
            }
            title = "Focus done! 🍅"
            let rest = "a \(options.minutes(of: next))-minute \(next == .longBreak ? "long " : "")break"
            body = timer.isWaiting ? "\(name) says: time for \(rest) — right-click it to start."
                : "\(name) says: time for \(rest)."
        case .breakDone:
            playground.nudge(timer.petID)
            title = "Break's over ☕️"
            body = timer.isWaiting ? "\(name) is ready when you are — right-click it to start the next focus."
                : "\(name) says: back to focus for \(options.focusMinutes) minutes!"
        }
        if options.seekAttention { playground.seekAttention(timer.petID) }
        notifier.post(title: title, body: body, notify: options.notifications, sound: options.sound)
    }

    // MARK: - Launch at login

    var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    var launchAtLoginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    // MARK: - Battery saver

    private static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    private func observeScreenLock() {
        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.screenLocked = locked
                    self?.updatePacing()
                }
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        // Fast user switching: another user's session is in front.
        for (name, inactive) in [(NSWorkspace.sessionDidResignActiveNotification, true),
                                 (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sessionInactive = inactive
                    self?.updatePacing()
                }
            }
        }
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.screensAsleep = asleep
                    self?.updatePacing()
                }
            }
        }
    }

    /// 30 fps on battery and paused while the screen is locked or asleep (with the battery saver on), else 60 fps.
    private func updatePacing() {
        let saver = settings.preferences.batterySaver
        if saver && (screenLocked || screensAsleep || sessionInactive) {
            timer?.invalidate()
            timer = nil
            worldMonitor.stop()
            return
        }
        let interval = FramePacing.interval(onBattery: onBattery, batterySaver: saver)
        worldMonitor.resume()
        guard timer == nil || interval != tickInterval else { return }
        tickInterval = interval
        timer?.invalidate()
        lastTick = 0  // no catch-up jump after a pause
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Visibility

    /// Out of sight: hidden by the player, or by auto-hide.
    var petsHidden: Bool { settings.hidden || autoHidden }

    private func applyVisibility() {
        let hidden = petsHidden
        for record in settings.pets {
            if hidden { petViews[record.id]?.hide() } else { petViews[record.id]?.show() }
        }
        for view in itemViews.values {
            if hidden { view.hide() } else { view.show() }
        }
    }

    private func updateAutoHide() {
        let hide = autoHideState.update(frontmost: worldMonitor.frontmostBundleID,
                                        isFullScreen: worldMonitor.frontmostIsFullScreen,
                                        preferences: settings.preferences, gameRunning: isGameRunning)
        guard hide != autoHidden else { return }
        autoHidden = hide
        applyVisibility()
    }

    // MARK: - Pets window

    /// Gives a pet a nickname (an empty name or the species name clears it).
    func rename(_ id: UUID, to name: String) {
        guard let index = settings.pets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let species = settings.pets[index].displayName
        let speciesNames = [species, species.replacingOccurrences(of: " (Shiny)", with: "")]
        settings.pets[index].nickname = trimmed.isEmpty || speciesNames.contains(trimmed) ? nil : trimmed
        save()
        petsChanged()
    }

    /// Open windows that show pets pick up the change.
    private func petsChanged() {
        petsWindowIfOpened?.refreshIfVisible()
        pokedexWindowIfOpened?.refreshIfVisible()
    }

    func portrait(forPet path: String) async -> URL? {
        await portrait(forCatch: path)
    }

    // MARK: - Pets

    /// A new player (or one who reset the game) still has to pick their first Pokémon.
    var needsStarter: Bool { !settings.starterChosen }

    func showStarterChoice() {
        starterWindow.show()
    }

    /// Makes the chosen starter the first pet. The only way to get a pet besides catching one.
    func chooseStarter(_ entry: CatalogEntry) async throws {
        guard needsStarter else { return }
        let sprites = try await loadSprites(entry.path)
        guard needsStarter else { return }
        let record = PetRecord(spritePath: entry.path, displayName: entry.displayName, joined: Date())
        settings.pets.append(record)
        settings.starterChosen = true
        recordInPokedex(record)
        if settings.hidden { setHidden(false) }
        attach(record, sprites: sprites)
        save()
        refreshEvolutionOptions()
        petsChanged()
    }

    /// Releases a pet: it leaves the screen (its Pokédex entry stays, as a former pet).
    /// Asks first, then releases the pet.
    func confirmRelease(_ id: UUID) {
        guard let pet = settings.pets.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Release \(pet.name)?"
        alert.informativeText = "It leaves for good. Its Pokédex entry stays."
        alert.addButton(withTitle: "Release").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        removePet(id)
    }

    func removePet(_ id: UUID) {
        playground.removePet(id)
        petViews.removeValue(forKey: id)?.close()
        settings.pets.removeAll { $0.id == id }
        if settings.pomodoro?.petID == id {
            // The timer moves to another pet (or stops when none is left).
            if let other = settings.pets.first { settings.pomodoro?.petID = other.id } else { settings.pomodoro = nil }
        }
        save()
        petsChanged()
    }

    func bestFriendName(of id: UUID) -> String? {
        guard let friend = playground.friendships.bestFriend(of: id, among: settings.pets.map(\.id)) else { return nil }
        return settings.pets.first { $0.id == friend }?.name
    }

    func handle(_ event: PetEvent, pet id: UUID) {
        playground.handle(event, pet: id)
    }

    func movePet(_ id: UUID, to point: CGPoint) {
        playground.movePet(id, to: point)
    }

    func stroke(pet id: UUID, cursorX: CGFloat) {
        playground.stroke(pet: id, cursorX: cursorX)
    }

    func strokeEnded(pet id: UUID) {
        playground.strokeEnded(pet: id)
    }

    // MARK: - Evolution

    enum EvolutionStatus {
        case none
        case notReady(treatsLeft: Int, focusSessionsLeft: Int, needsBestFriend: Bool)
        case ready([CatalogEntry])

        /// "Evolves after 3 more treats, 12 more focus sessions and a best friend"
        var waitingText: String? {
            guard case .notReady(let treats, let sessions, let needsFriend) = self else { return nil }
            let parts = [treats > 0 ? (treats == 1 ? "1 more treat" : "\(treats) more treats") : nil,
                         sessions > 0 ? (sessions == 1 ? "1 more focus session" : "\(sessions) more focus sessions") : nil,
                         needsFriend ? "a best friend" : nil].compactMap { $0 }
            guard let last = parts.last else { return nil }
            let list = parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " and " + last
            return "Evolves after " + list
        }
    }

    func evolutionStatus(of id: UUID) -> EvolutionStatus {
        guard !evolving.contains(id), let record = settings.pets.first(where: { $0.id == id }),
              let options = evolutionOptions[id], !options.isEmpty else { return .none }
        let needed = pomodoroOptions.focusSessionsToEvolve
        let hasBestFriend = bestFriendName(of: id) != nil
        if Evolution.isReady(treatsEaten: record.treatsEaten, focusSessions: record.focusSessions,
                             focusSessionsNeeded: needed, hasBestFriend: hasBestFriend) { return .ready(options) }
        return .notReady(treatsLeft: max(0, Evolution.treatsNeeded - record.treatsEaten),
                         focusSessionsLeft: max(0, needed - record.focusSessions), needsBestFriend: !hasBestFriend)
    }

    /// Asks PokeAPI (cached on disk) what each pet can evolve into, for pets not known yet.
    func refreshEvolutionOptions() {
        for record in settings.pets where evolutionOptions[record.id] == nil && !evolutionLookups.contains(record.id) {
            let id = record.id
            if let failed = evolutionFailedAt[id], Date().timeIntervalSince(failed) < 300 { continue }
            guard let dex = Evolution.dexNumber(of: record.spritePath), dex > 0 else {
                evolutionOptions[id] = []  // not a real species (e.g. 0000): nothing to evolve into
                continue
            }
            evolutionLookups.insert(id)
            let store = self.store, evolutions = self.evolutionStore
            Task {
                defer { self.evolutionLookups.remove(id) }
                let next: [Int]
                do {
                    next = try await evolutions.nextForms(of: dex)
                } catch SpriteStoreError.http(404, _) {
                    self.evolutionOptions[id] = []  // PokeAPI doesn't know it: no evolution
                    return
                } catch {
                    self.evolutionFailedAt[id] = Date()  // offline: try again in a while
                    return
                }
                guard !next.isEmpty else {
                    self.evolutionOptions[id] = []
                    return
                }
                guard let catalog = try? await store.catalog() else {
                    self.evolutionFailedAt[id] = Date()
                    return
                }
                self.evolutionOptions[id] = next.compactMap { dex in catalog.first { $0.path == Evolution.path(for: dex) } }
            }
        }
    }

    /// Evolves a pet: new sprites and name; same pet, friends and place. Plays a white flash.
    func evolve(_ id: UUID, into entry: CatalogEntry) {
        guard !evolving.contains(id) else { return }
        evolving.insert(id)
        Task {
            defer { self.evolving.remove(id) }
            // A shiny stays shiny: it evolves into the shiny form when SpriteCollab has one.
            var path = entry.path
            if settings.pets.first(where: { $0.id == id })?.isShiny == true,
               let catalog = try? await store.catalog(), catalog.contains(where: { $0.path == "\(entry.path)/0000/0001" }) {
                path = "\(entry.path)/0000/0001"
            }
            guard let sprites = try? await loadSprites(path),
                  let index = settings.pets.firstIndex(where: { $0.id == id }) else { return }
            settings.pets[index].spritePath = path
            settings.pets[index].displayName = settings.pets[index].isShiny ? "\(entry.displayName) (Shiny)" : entry.displayName
            settings.pets[index].treatsEaten = 0
            settings.pets[index].focusSessions = 0
            recordInPokedex(settings.pets[index])
            playground.replaceMetrics(of: id, with: PetMetrics(sprites: sprites))
            petViews[id]?.replaceSprites(sprites)
            petViews[id]?.flash()
            showEmotion(.joyous, pet: id)
            evolutionOptions[id] = nil
            save()
            refreshEvolutionOptions()
            petsChanged()
        }
    }

    // MARK: - Fetch

    var canPlayFetch: Bool { !isGameRunning && playground.canDropToy }

    /// Drops the fetch ball from a random spot at the top of a screen with pets.
    func playFetch() {
        guard canPlayFetch, let spot = playground.randomFeedingSpot(world: worldMonitor.world) else { return }
        playground.dropToy(at: spot)
    }

    // MARK: - Treats

    var canFeed: Bool { !isGameRunning && playground.canDropTreat }

    /// Drops a random treat right next to the mouse pointer; it falls onto whatever is below.
    func feed() {
        guard canFeed else { return }
        let kind: ItemKind = Bool.random() ? .apple : .oranBerry
        let mouse = NSEvent.mouseLocation
        let world = worldMonitor.world
        if world.isOnAnyScreen(mouse, margin: 0) {
            playground.dropTreat(kind, at: CGPoint(x: mouse.x + 24, y: mouse.y))
        } else if let spot = playground.randomFeedingSpot(world: world) {
            playground.dropTreat(kind, at: spot)  // the pointer is on a screen pets don't use
        }
    }

    func handle(_ event: ItemEvent, item id: UUID) {
        playground.handle(event, item: id)
    }

    func moveItem(_ id: UUID, to point: CGPoint) {
        playground.moveItem(id, to: point)
    }

    // MARK: - Catch game

    var isGameRunning: Bool { gameUI.status != .idle || playground.game != nil }

    /// Loads a roster of wild Pokémon (complete sprite sets first, cached ones when offline) and starts a round.
    func startCatchGame() {
        guard !isGameRunning else { return }
        gameUI.beginLoading()
        let attempt = UUID()
        gameAttempt = attempt
        let seed = UInt64.random(in: .min ... .max)
        Task {
            let roster = await loadRoster()
            guard gameAttempt == attempt, gameUI.status == .loading else { return }  // cancelled meanwhile
            if roster.isEmpty {
                gameUI.fail("Couldn't load wild Pokémon")
            } else {
                playground.startGame(roster: roster, seed: seed)
                gameUI.begin()
            }
        }
    }

    /// Throws a Razz Berry, or a ball once the round's berries are used up.
    func throwBerry(from point: CGPoint, velocity: CGVector) {
        if (playground.game?.berriesLeft ?? 0) > 0 {
            playground.throwBerry(from: point, velocity: velocity)
        } else {
            playground.throwBall(from: point, velocity: velocity)
        }
    }

    private func recordInPokedex(_ pet: PetRecord) {
        Pokedex.recordPet(path: pet.spritePath, displayName: pet.displayName, isShiny: pet.isShiny,
                          into: &settings.pokedex, at: Date())
        pokedexWindowIfOpened?.refreshIfVisible()
    }

    /// Species keys (e.g. `0025`) of the current pets.
    var currentPetSpecies: Set<String> {
        Set(settings.pets.compactMap { Pokedex.key(forPath: $0.spritePath) })
    }

    func showPokedex() {
        pokedexWindow.show()
    }

    /// The Pokémon list and a portrait loader for the Pokédex window.
    func catalogForPokedex() async -> [CatalogEntry] {
        (try? await store.catalog()) ?? []
    }

    func normalPortrait(for key: String) async -> URL? {
        await store.portrait(for: key, names: ["Normal"])
    }

    /// A caught Pokémon's portrait: its own form's if available, else its species'.
    func portrait(forCatch path: String) async -> URL? {
        if let url = await store.portrait(for: path, names: ["Normal"]) { return url }
        guard path.contains("/"), let key = Pokedex.key(forPath: path) else { return nil }
        return await store.portrait(for: key, names: ["Normal"])
    }

    func endCatchGame() {
        if case .finalScore = gameUI.status { return }  // already over; the results are on their way
        if playground.game != nil {
            playground.endGame()
        } else {
            gameAttempt = UUID()
            gameUI.finish()
        }
    }

    func throwBall(from point: CGPoint, velocity: CGVector) {
        playground.throwBall(from: point, velocity: velocity)
    }

    /// Turns kept catches into pets where they were caught.
    func keepCatches(_ records: [CatchRecord]) {
        for record in records {
            guard settings.pets.count < Playground.maxOwnPets, let sprites = wildSprites[record.path] else { continue }
            let name = record.isShiny ? "\(record.displayName) (Shiny)" : record.displayName
            let pet = PetRecord(spritePath: record.path, displayName: name, position: record.position,
                                isShiny: record.isShiny, joined: Date())
            settings.pets.append(pet)
            recordInPokedex(pet)
            attach(pet, sprites: sprites)
        }
        save()
        refreshEvolutionOptions()
        petsChanged()
    }

    // MARK: - Settings

    /// The player's Show / Hide. Showing also overrides auto-hide until another app comes to the front.
    func setHidden(_ hidden: Bool) {
        settings.hidden = hidden
        if !hidden && autoHidden {
            autoHideState.userShowed(frontmost: worldMonitor.frontmostBundleID)
            autoHidden = false
        }
        applyVisibility()
        save()
    }

    func toggleHidden() {
        setHidden(!petsHidden)
    }

    func setCursorMode(_ mode: CursorMode) {
        settings.cursorMode = mode
        save()
    }

    func setScale(_ scale: Int) {
        settings.scale = min(max(scale, 1), 3)
        playground.setScale(CGFloat(settings.scale))
        save()
    }

    // MARK: - Reset

    var canReset: Bool { !isGameRunning }

    /// Asks first, then starts over: no pets, empty Pokédex, default settings, downloads deleted.
    func confirmReset() {
        guard canReset else { return }
        let alert = NSAlert()
        alert.messageText = "Reset PokeToy?"
        alert.informativeText = "This releases all your pets, erases your Pokédex, scores, friendships and settings, "
            + "and deletes downloaded Pokémon. Then you choose a new first Pokémon."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        resetGame()
    }

    private func resetGame() {
        guard canReset else { return }
        gameUI.closeResults()
        for view in petViews.values { view.close() }
        for view in itemViews.values { view.close() }
        petViews = [:]
        itemViews = [:]
        wildSprites = [:]
        rosterSpecs = [:]
        wildPaths = [:]
        evolutionOptions = [:]
        evolutionLookups = []
        evolutionFailedAt = [:]
        evolving = []
        settings = .default
        playground = Playground(seed: .random(in: .min ... .max), scale: CGFloat(settings.scale))
        settings.save(to: .standard)
        autoHidden = false
        autoHideState = AutoHideState()
        applyPreferences()
        petsChanged()
        preferencesWindowIfOpened?.refreshIfVisible()
        let store = self.store
        Task {
            await store.clearDownloads()
            pokedexWindowIfOpened?.refreshIfVisible()
            showStarterChoice()
        }
    }

    /// Sprite paths downloaded so far (and the bundled ones), for the Pokédex.
    func downloadedSpritePaths() async -> [String] {
        await store.cachedSpritePaths()
    }

    /// A species' short description ("Electric · Mouse Pokémon — …"), nil when PokeAPI can't be reached.
    func pokemonDescription(for key: String) async -> String? {
        guard let dex = Evolution.dexNumber(of: key) else { return nil }
        let evolutions = evolutionStore
        return try? await withDeadline(seconds: 5) { try await evolutions.description(of: dex) }.summary
    }

    /// Records current pet positions and friendships and writes settings to disk.
    func save() {
        for index in settings.pets.indices {
            if let pet = playground.pet(settings.pets[index].id) { settings.pets[index].position = pet.body.position }
        }
        settings.friendships = playground.friendships.points
        settings.save(to: .standard)
    }

    // MARK: - Private

    private func loadSprites(_ path: String) async throws -> SpriteSet {
        let directory = try await store.spriteDirectory(for: path)
        return try SpriteSet(directory: directory)
    }

    private func attach(_ record: PetRecord, sprites: SpriteSet) {
        // A pet removed while its sprites were loading is dropped.
        guard settings.pets.contains(where: { $0.id == record.id }), petViews[record.id] == nil else { return }
        let world = worldMonitor.world
        let start = record.position.flatMap { world.isOnAnyScreen($0, margin: 0) ? $0 : nil }
            ?? world.spawnPoint(fraction: .random(in: 0.2...0.8))
        playground.addPet(id: record.id, role: .own, metrics: PetMetrics(sprites: sprites), at: start)
        let view = PetController(id: record.id, sprites: sprites, model: self, interactive: true)
        if !petsHidden { view.show() }
        petViews[record.id] = view
    }

    /// A normal round gets at least this many different wild Pokémon when they can be loaded.
    private static let minimumRoster = 10

    /// 12 regular Pokémon plus a legendary (base forms; in a normal round, species not yet in the Pokédex first),
    /// with shiny sprites when SpriteCollab has them and flying types from PokeAPI. A normal round tops up to at
    /// least 10 with more picks, then (offline) with Pokémon already on disk.
    private func loadRoster() async -> [WildSpec] {
        let store = self.store, evolutions = self.evolutionStore
        // Keep loading short: the overlay captures the mouse meanwhile.
        let catalog = (try? await withDeadline(seconds: 3) { try await store.catalog() }) ?? []
        // Keep only sprites still needed by an open results window; this round loads its own.
        let pending = gameUI.pendingCatchPaths
        wildSprites = wildSprites.filter { pending.contains($0.key) }
        let base = catalog.filter { $0.isComplete && !$0.path.contains("/") }
        var rng = SystemRandomNumberGenerator()
        let legendaries = Pokedex.newFirst(base.filter { Legendaries.isLegendary(path: $0.path) },
                                           pokedex: settings.pokedex, using: &rng)
        let regular = Pokedex.newFirst(base.filter { !Legendaries.isLegendary(path: $0.path) },
                                       pokedex: settings.pokedex, using: &rng)
        let picks = Array(regular.prefix(CatchGame.rosterRegulars)) + Array(legendaries.prefix(1))
        let spares = Array(regular.dropFirst(CatchGame.rosterRegulars).prefix(Self.minimumRoster))
        var loaded = await loadWild(picks)
        if loaded.count < Self.minimumRoster {
            // Some didn't load in time: try a few more picks, then fill up with Pokémon already on disk
            // (the bundled Pikachu is always there).
            if loaded.count > 0, !spares.isEmpty {
                loaded += await loadWild(Array(spares.prefix(Self.minimumRoster - loaded.count + 2)))
            }
            let names = Dictionary(catalog.map { ($0.path, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            let have = Set(loaded.map(\.entry.path))
            let cached = await store.cachedSpritePaths().filter { !have.contains($0) && !$0.contains("/") }
                .shuffled().prefix(max(0, Self.minimumRoster - loaded.count))
            loaded += await loadWild(cached.map {
                CatalogEntry(path: $0, displayName: names[$0] ?? ($0 == "0025" ? "Pikachu" : "Pokémon #\($0)"))
            })
        }
        // Shiny sprites for the roster, where SpriteCollab has them.
        let paths = Set(catalog.map(\.path))
        let shinyEntries = loaded.compactMap { wild -> CatalogEntry? in
            let shinyPath = "\(wild.entry.path)/0000/0001"
            return paths.contains(shinyPath) ? CatalogEntry(path: shinyPath, displayName: wild.entry.displayName) : nil
        }
        // Shiny sprites and PokeAPI types load side by side, each within its own 3–3.5 s budget.
        let dexes = Set(loaded.compactMap { Evolution.dexNumber(of: $0.entry.path) })
        async let shinyLoad = loadWild(shinyEntries)
        async let typeLoad = withTaskGroup(of: (Int, [String]).self) { group in
            for dex in dexes {
                group.addTask { (dex, (try? await withDeadline(seconds: 3) { try await evolutions.types(of: dex) }) ?? []) }
            }
            var types: [Int: [String]] = [:]
            for await (dex, list) in group { types[dex] = list }
            return types
        }
        let (shinies, types) = await (shinyLoad, typeLoad)
        for wild in loaded + shinies { wildSprites[wild.entry.path] = wild.sprites }
        let shinyPaths = Set(shinies.map(\.entry.path))

        var roster: [WildSpec] = []
        for wild in loaded {
            let dex = Evolution.dexNumber(of: wild.entry.path) ?? 0
            let shinyPath = "\(wild.entry.path)/0000/0001"
            roster.append(WildSpec(path: wild.entry.path, displayName: wild.entry.displayName,
                                   metrics: PetMetrics(sprites: wild.sprites),
                                   isLegendary: Legendaries.isLegendary(path: wild.entry.path),
                                   shinyPath: shinyPaths.contains(shinyPath) ? shinyPath : nil,
                                   canFly: types[dex]?.contains("flying") ?? false))
        }
        rosterSpecs = Dictionary(roster.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return roster
    }

    private func loadWild(_ entries: [CatalogEntry]) async -> [LoadedWild] {
        let store = self.store
        return await withTaskGroup(of: LoadedWild?.self) { group in
            for entry in entries {
                group.addTask {
                    guard let directory = try? await store.spriteDirectory(for: entry.path, timeout: 3.5),
                          let sprites = try? SpriteSet(directory: directory) else { return nil }
                    return LoadedWild(entry: entry, sprites: sprites)
                }
            }
            var result: [LoadedWild] = []
            for await wild in group {
                if let wild { result.append(wild) }
            }
            return result
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTick == 0 ? 1.0 / 60.0 : min(now - lastTick, 0.1)
        lastTick = now
        let cursor = NSEvent.mouseLocation
        tickCount += 1
        if tickCount % 60 == 1 {  // once a second is plenty for the clock and accessibility settings
            playground.timeOfDay = TimeOfDay(hour: Calendar.current.component(.hour, from: Date()))
            playground.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        if now - lastPomodoroCheck >= 0.25 {
            lastPomodoroCheck = now
            checkPomodoro()
        }
        if now - lastAutoHideCheck >= 0.2 {  // 5 Hz, like the world updates
            lastAutoHideCheck = now
            updateAutoHide()
        }
        if now - lastPowerCheck >= 5 {  // plugged in or unplugged
            lastPowerCheck = now
            let battery = Self.isOnBattery()
            if battery != onBattery {
                onBattery = battery
                updatePacing()
            }
        }
        if tickCount % 6 == 1 {  // 10 Hz is plenty for noticing the user
            playground.setUserIdle(CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                                           eventType: CGEventType(rawValue: ~0)!))
        }
        playground.mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        let events = playground.tick(dt: dt, world: worldMonitor.world, cursor: cursor, cursorMode: settings.cursorMode)
        var friendshipsChanged = false
        for event in events {
            switch event {
            case .wildSpawned(let id, let path):
                wildPaths[id] = path
                if let sprites = wildSprites[path] {
                    let view = PetController(id: id, sprites: sprites, model: self, interactive: false)
                    view.show()
                    petViews[id] = view
                }
                if let pet = playground.pet(id) { gameUI.addEffect(.flash, at: pet.body.position) }  // it pops up
            case .wildShiny(let id):
                // A shiny: swap in its shiny sprites and make it sparkle.
                if let path = wildPaths[id], let shinyPath = rosterSpecs[path]?.shinyPath,
                   let sprites = wildSprites[shinyPath] {
                    petViews[id]?.replaceSprites(sprites)
                    wildPaths[id] = shinyPath
                }
                if let pet = playground.pet(id) { gameUI.addEffect(.stars, at: pet.body.position) }
            case .wildRemoved(let id):
                petViews.removeValue(forKey: id)?.close()
                wildPaths[id] = nil
            case .ballHit(let id):
                if let pet = playground.pet(id) { gameUI.addEffect(.flash, at: pet.body.position) }
            case .caught(let id):
                let catches = (playground.game?.catches ?? []) + (playground.lastResults?.catches ?? [])
                if let record = catches.last(where: { $0.petID == id }) { gameUI.addEffect(.stars, at: record.position) }
            case .friendshipChanged:
                friendshipsChanged = true
            case .emotion(let id, let emotion):
                showEmotion(emotion, pet: id)
            case .treatEaten(let id):
                if let index = settings.pets.firstIndex(where: { $0.id == id }) {
                    settings.pets[index].treatsEaten += 1
                    friendshipsChanged = true  // save the count too
                    petsChanged()
                }
            case .roundEnded:
                showResults()
            default:
                break
            }
        }
        if friendshipsChanged { save() }
        syncItemViews()
        for pet in playground.pets { petViews[pet.id]?.render(pet, cursor: cursor) }
        for item in playground.items { itemViews[item.id]?.render(item, cursor: cursor, scale: playground.scale) }
        gameUI.redraw()
    }

    private func showResults() {
        guard let results = playground.lastResults, results.score > 0 || !results.catches.isEmpty else {
            gameUI.finish()  // nothing happened (e.g. ended during the countdown): no results window
            return
        }
        Pokedex.record(results.catches, into: &settings.pokedex, at: Date())
        pokedexWindowIfOpened?.refreshIfVisible()  // right after the round, even before the results are closed
        let previousBest = settings.bestCatchScore
        let isNewBest = results.score > previousBest
        if isNewBest {
            settings.bestCatchScore = results.score
        }
        save()
        let best = max(previousBest, results.score)
        gameUI.showFinalScore(results.score) { [weak self] in
            guard let self else { return }
            let keepable = CatchGame.keepable(results.catches, ownPetCount: self.settings.pets.count,
                                              cap: Playground.maxOwnPets)
            self.gameUI.showResults(results, best: best, isNewBest: isNewBest, keepable: keepable)
        }
    }

    /// Shows an emotion bubble: the emoji at once, then the Pokémon's portrait once it's loaded.
    private func showEmotion(_ emotion: Emotion, pet id: UUID) {
        guard let view = petViews[id] else { return }
        view.showEmotion(emotion)
        guard let path = settings.pets.first(where: { $0.id == id })?.spritePath ?? wildPaths[id] else { return }
        let store = self.store
        Task {
            var url = await store.portrait(for: path, emotion: emotion)
            if url == nil, path.contains("/"), let dex = Evolution.dexNumber(of: path) {
                url = await store.portrait(for: Evolution.path(for: dex), emotion: emotion)  // forms often share
            }
            if let url { self.petViews[id]?.showPortrait(url, for: emotion) }
        }
    }

    /// Opens a panel for each new treat or fetch ball and closes panels whose item is gone.
    private func syncItemViews() {
        let treats = Set(playground.items.filter { $0.kind.isHandheld }.map(\.id))
        for (id, view) in itemViews where !treats.contains(id) {
            view.close()
            itemViews[id] = nil
        }
        for id in treats where itemViews[id] == nil {
            let view = ItemController(id: id, model: self)
            if petsHidden { view.hide() }
            itemViews[id] = view
        }
    }
}
