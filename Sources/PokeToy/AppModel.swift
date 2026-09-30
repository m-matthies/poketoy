import AppKit
import OSLog
import PokeToyCore

enum AppError: LocalizedError {
    case tooManyPets

    var errorDescription: String? {
        switch self {
        case .tooManyPets: return "You already have \(Playground.maxOwnPets) pets — remove one first."
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
    private let worldMonitor = WorldMonitor()
    private var petViews: [UUID: PetController] = [:]
    private var itemViews: [UUID: ItemController] = [:]
    private var wildSprites: [String: SpriteSet] = [:]
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
    }

    func start() {
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
    }

    // MARK: - Pets

    func addPet(_ entry: CatalogEntry) async throws {
        guard settings.pets.count < Playground.maxOwnPets else { throw AppError.tooManyPets }
        let sprites = try await loadSprites(entry.path)
        guard settings.pets.count < Playground.maxOwnPets else { throw AppError.tooManyPets }
        let record = PetRecord(spritePath: entry.path, displayName: entry.displayName)
        settings.pets.append(record)
        if settings.hidden { setHidden(false) }
        attach(record, sprites: sprites)
        save()
    }

    func removePet(_ id: UUID) {
        playground.removePet(id)
        petViews.removeValue(forKey: id)?.close()
        settings.pets.removeAll { $0.id == id }
        save()
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

    // MARK: - Treats

    var canFeed: Bool { !isGameRunning && playground.canDropTreat }

    /// Drops a random treat from the top of the screen under the cursor.
    func feed() {
        guard canFeed else { return }
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        let kind: ItemKind = Bool.random() ? .apple : .oranBerry
        playground.dropTreat(kind, at: CGPoint(x: cursor.x, y: screen.visibleFrame.maxY - 10))
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
        Task {
            let roster = await loadRoster()
            guard gameAttempt == attempt, gameUI.status == .loading else { return }  // cancelled meanwhile
            if roster.isEmpty {
                gameUI.fail("Couldn't load wild Pokémon")
            } else {
                playground.startGame(roster: roster, seed: .random(in: .min ... .max))
                gameUI.begin()
            }
        }
    }

    func endCatchGame() {
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
            let pet = PetRecord(spritePath: record.path, displayName: record.displayName, position: record.position)
            settings.pets.append(pet)
            attach(pet, sprites: sprites)
        }
        save()
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

    private func loadRoster() async -> [WildSpec] {
        let store = self.store
        // Keep loading short: the overlay captures the mouse meanwhile.
        let catalog = (try? await withDeadline(seconds: 3) { try await store.catalog() }) ?? []
        let complete = catalog.filter(\.isComplete)
        let pool = complete.isEmpty ? catalog : complete
        var loaded = await loadWild(Array(pool.shuffled().prefix(8)))
        if loaded.count < 3 {
            // Offline or unlucky: fill up with Pokémon already on disk (the bundled Pikachu is always there).
            let names = Dictionary(catalog.map { ($0.path, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            let have = Set(loaded.map(\.entry.path))
            let cached = await store.cachedSpritePaths().filter { !have.contains($0) }.shuffled().prefix(8 - loaded.count)
            loaded += await loadWild(cached.map {
                CatalogEntry(path: $0, displayName: names[$0] ?? ($0 == "0025" ? "Pikachu" : "Pokémon #\($0)"))
            })
        }
        for wild in loaded { wildSprites[wild.entry.path] = wild.sprites }
        return loaded.map {
            WildSpec(path: $0.entry.path, displayName: $0.entry.displayName, metrics: PetMetrics(sprites: $0.sprites))
        }
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
        let events = playground.tick(dt: dt, world: worldMonitor.world, cursor: cursor, cursorMode: settings.cursorMode)
        var friendshipsChanged = false
        for event in events {
            switch event {
            case .wildSpawned(let id, let path):
                if let sprites = wildSprites[path] {
                    let view = PetController(id: id, sprites: sprites, model: self, interactive: false)
                    view.show()
                    petViews[id] = view
                }
            case .wildRemoved(let id):
                petViews.removeValue(forKey: id)?.close()
            case .friendshipChanged:
                friendshipsChanged = true
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
        gameUI.finish()
        guard let results = playground.lastResults else { return }
        let isNewBest = results.score > settings.bestCatchScore
        if isNewBest {
            settings.bestCatchScore = results.score
            save()
        }
        let keepable = CatchGame.keepable(results.catches, ownPetCount: settings.pets.count, cap: Playground.maxOwnPets)
        gameUI.showResults(results, best: settings.bestCatchScore, isNewBest: isNewBest, keepable: keepable)
    }

    /// Opens a panel for each new treat and closes panels whose treat is gone.
    private func syncItemViews() {
        let treats = Set(playground.items.filter { $0.kind.isTreat }.map(\.id))
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
