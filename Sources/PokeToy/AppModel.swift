import AppKit
import OSLog
import PokeToyCore

enum AppError: LocalizedError {
    case tooManyPets

    var errorDescription: String? {
        switch self {
        case .tooManyPets: return "You already have \(Playground.maxOwnPets) pets — release one first."
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
    private var roundIsDaily = false
    private lazy var pokedexWindow = PokedexWindowController(model: self)
    private var gameAttempt = UUID()
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private lazy var picker = PickerWindowController(model: self)
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
                            bundledSprites: Bundle.main.resourceURL?.appendingPathComponent("Sprites", isDirectory: true))
        evolutionStore = EvolutionStore(cacheDirectory: caches.appendingPathComponent("pokeapi", isDirectory: true))
    }

    func start() {
        // Current pets belong in the Pokédex too (also covers pets from before it tracked them).
        for record in settings.pets { recordInPokedex(record) }
        settings.save(to: .standard)
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
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshEvolutionOptions()
    }

    // MARK: - Pets

    func addPet(_ entry: CatalogEntry) async throws {
        guard settings.pets.count < Playground.maxOwnPets else { throw AppError.tooManyPets }
        let sprites = try await loadSprites(entry.path)
        guard settings.pets.count < Playground.maxOwnPets else { throw AppError.tooManyPets }
        let record = PetRecord(spritePath: entry.path, displayName: entry.displayName)
        settings.pets.append(record)
        recordInPokedex(record)
        if settings.hidden { setHidden(false) }
        attach(record, sprites: sprites)
        save()
        refreshEvolutionOptions()
    }

    /// Releases a pet: it leaves the screen (its Pokédex entry stays, as a former pet).
    func removePet(_ id: UUID) {
        playground.removePet(id)
        petViews.removeValue(forKey: id)?.close()
        settings.pets.removeAll { $0.id == id }
        save()
        pokedexWindow.refreshIfVisible()
    }

    func bestFriendName(of id: UUID) -> String? {
        guard let friend = playground.friendships.bestFriend(of: id, among: settings.pets.map(\.id)) else { return nil }
        return settings.pets.first { $0.id == friend }?.displayName
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
        case notReady(treatsLeft: Int, needsBestFriend: Bool)
        case ready([CatalogEntry])
    }

    func evolutionStatus(of id: UUID) -> EvolutionStatus {
        guard !evolving.contains(id), let record = settings.pets.first(where: { $0.id == id }),
              let options = evolutionOptions[id], !options.isEmpty else { return .none }
        let hasBestFriend = bestFriendName(of: id) != nil
        if Evolution.isReady(treatsEaten: record.treatsEaten, hasBestFriend: hasBestFriend) { return .ready(options) }
        return .notReady(treatsLeft: max(0, Evolution.treatsNeeded - record.treatsEaten), needsBestFriend: !hasBestFriend)
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
            guard let sprites = try? await loadSprites(entry.path),
                  let index = settings.pets.firstIndex(where: { $0.id == id }) else { return }
            settings.pets[index].spritePath = entry.path
            settings.pets[index].displayName = entry.displayName
            settings.pets[index].treatsEaten = 0
            recordInPokedex(settings.pets[index])
            playground.replaceMetrics(of: id, with: PetMetrics(sprites: sprites))
            petViews[id]?.replaceSprites(sprites)
            petViews[id]?.flash()
            showEmotion(.joyous, pet: id)
            evolutionOptions[id] = nil
            save()
            refreshEvolutionOptions()
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
        playground.dropTreat(kind, at: CGPoint(x: mouse.x + 24, y: mouse.y))
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
    /// The daily challenge uses the day's fixed roster and seed.
    func startCatchGame(daily: Bool = false) {
        guard !isGameRunning else { return }
        gameUI.beginLoading()
        let attempt = UUID()
        gameAttempt = attempt
        roundIsDaily = daily
        let seed = daily ? DailyChallenge.seed(for: Date()) : UInt64.random(in: .min ... .max)
        Task {
            let roster = await loadRoster(daily: daily, seed: seed)
            guard gameAttempt == attempt, gameUI.status == .loading else { return }  // cancelled meanwhile
            if roster.isEmpty {
                gameUI.fail("Couldn't load wild Pokémon")
            } else {
                playground.startGame(roster: roster, seed: seed)
                gameUI.begin()
            }
        }
    }

    func throwBerry(from point: CGPoint, velocity: CGVector) {
        playground.throwBerry(from: point, velocity: velocity)
    }

    private func recordInPokedex(_ pet: PetRecord) {
        Pokedex.recordPet(path: pet.spritePath, displayName: pet.displayName, into: &settings.pokedex, at: Date())
        pokedexWindow.refreshIfVisible()
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
            let pet = PetRecord(spritePath: record.path, displayName: name, position: record.position)
            settings.pets.append(pet)
            recordInPokedex(pet)
            attach(pet, sprites: sprites)
        }
        save()
        refreshEvolutionOptions()
    }

    // MARK: - Settings

    func setHidden(_ hidden: Bool) {
        settings.hidden = hidden
        for record in settings.pets {
            if hidden { petViews[record.id]?.hide() } else { petViews[record.id]?.show() }
        }
        for view in itemViews.values {
            if hidden { view.hide() } else { view.show() }
        }
        save()
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

    func showPicker() {
        picker.show()
    }

    func catalog(forceRefresh: Bool) async throws -> [CatalogEntry] {
        try await store.catalog(forceRefresh: forceRefresh)
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
        if !settings.hidden { view.show() }
        petViews[record.id] = view
    }

    /// Up to 7 regular Pokémon plus a legendary (base forms), with shiny sprites when SpriteCollab has them and
    /// flying types from PokeAPI. Offline, fills up with Pokémon already on disk.
    private func loadRoster(daily: Bool, seed: UInt64) async -> [WildSpec] {
        let store = self.store, evolutions = self.evolutionStore
        // Keep loading short: the overlay captures the mouse meanwhile.
        let catalog = (try? await withDeadline(seconds: 3) { try await store.catalog() }) ?? []
        // Keep only sprites still needed by an open results window; this round loads its own.
        let pending = gameUI.pendingCatchPaths
        wildSprites = wildSprites.filter { pending.contains($0.key) }
        let picks: [CatalogEntry]
        if daily {
            picks = DailyChallenge.roster(from: catalog, seed: seed)
        } else {
            let base = catalog.filter { $0.isComplete && !$0.path.contains("/") }
            let legendaries = base.filter { Legendaries.isLegendary(path: $0.path) }
            let regular = base.filter { !Legendaries.isLegendary(path: $0.path) }
            picks = Array(regular.shuffled().prefix(DailyChallenge.regulars)) + Array(legendaries.shuffled().prefix(1))
        }
        var loaded = await loadWild(picks)
        if loaded.count < 3 {
            // Offline or unlucky: fill up with Pokémon already on disk (the bundled Pikachu is always there).
            let names = Dictionary(catalog.map { ($0.path, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            let have = Set(loaded.map(\.entry.path))
            let cached = await store.cachedSpritePaths().filter { !have.contains($0) && !$0.contains("/") }
                .shuffled().prefix(8 - loaded.count)
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
        let shinies = await loadWild(shinyEntries)
        for wild in loaded + shinies { wildSprites[wild.entry.path] = wild.sprites }
        let shinyPaths = Set(shinies.map(\.entry.path))

        var roster: [WildSpec] = []
        for wild in loaded {
            let dex = Evolution.dexNumber(of: wild.entry.path) ?? 0
            let types = (try? await withDeadline(seconds: 3) { try await evolutions.types(of: dex) }) ?? []
            let shinyPath = "\(wild.entry.path)/0000/0001"
            roster.append(WildSpec(path: wild.entry.path, displayName: wild.entry.displayName,
                                   metrics: PetMetrics(sprites: wild.sprites),
                                   isLegendary: Legendaries.isLegendary(path: wild.entry.path),
                                   shinyPath: shinyPaths.contains(shinyPath) ? shinyPath : nil,
                                   canFly: types.contains("flying")))
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
        pokedexWindow.refreshIfVisible()  // right after the round, even before the results are closed
        let daily = roundIsDaily
        let dayKey = DailyChallenge.key(for: Date())
        let previousBest = daily ? (settings.dailyBest[dayKey] ?? 0) : settings.bestCatchScore
        let isNewBest = results.score > previousBest
        if isNewBest {
            if daily { settings.dailyBest[dayKey] = results.score } else { settings.bestCatchScore = results.score }
        }
        save()
        let best = max(previousBest, results.score)
        gameUI.showFinalScore(results.score) { [weak self] in
            guard let self else { return }
            let keepable = CatchGame.keepable(results.catches, ownPetCount: self.settings.pets.count,
                                              cap: Playground.maxOwnPets)
            self.gameUI.showResults(results, best: best, isNewBest: isNewBest, keepable: keepable, daily: daily)
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
            if settings.hidden { view.hide() }
            itemViews[id] = view
        }
    }
}
