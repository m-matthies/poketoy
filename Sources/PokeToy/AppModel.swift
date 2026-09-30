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

/// Owns the settings, the sprite store and the playground, and drives the 60 Hz tick.
@MainActor
final class AppModel {
    private(set) var settings: Settings
    private(set) var playground: Playground
    private let store: SpriteStore
    private let worldMonitor = WorldMonitor()
    private var petViews: [UUID: PetController] = [:]
    private var itemViews: [UUID: ItemController] = [:]
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private lazy var picker = PickerWindowController(model: self)
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

    var canFeed: Bool { playground.canDropTreat }

    /// Drops a random treat from the top of the screen under the cursor.
    func feed() {
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

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTick == 0 ? 1.0 / 60.0 : min(now - lastTick, 0.1)
        lastTick = now
        let cursor = NSEvent.mouseLocation
        let events = playground.tick(dt: dt, world: worldMonitor.world, cursor: cursor, cursorMode: settings.cursorMode)
        if events.contains(.friendshipChanged) { save() }
        syncItemViews()
        for pet in playground.pets { petViews[pet.id]?.render(pet, cursor: cursor) }
        for item in playground.items { itemViews[item.id]?.render(item, cursor: cursor, scale: playground.scale) }
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
