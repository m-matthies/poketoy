import AppKit
import OSLog
import PokeToyCore

/// Owns the settings, the sprite store and every pet, and drives the 60 Hz tick.
@MainActor
final class AppModel {
    private(set) var settings: Settings
    private let store: SpriteStore
    private let worldMonitor = WorldMonitor()
    private var pets: [UUID: PetController] = [:]
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private lazy var picker = PickerWindowController(model: self)
    private let logger = Logger(subsystem: "local.poketoy.PokeToy", category: "app")

    init() {
        settings = Settings.load(from: .standard)
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
                    attach(try await makeController(for: record))
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

    func addPet(_ entry: CatalogEntry) async throws {
        let record = PetRecord(spritePath: entry.path, displayName: entry.displayName)
        let pet = try await makeController(for: record)
        settings.pets.append(record)
        if settings.hidden { setHidden(false) }
        attach(pet)
        save()
    }

    func removePet(_ id: UUID) {
        pets.removeValue(forKey: id)?.close()
        settings.pets.removeAll { $0.id == id }
        save()
    }

    func setHidden(_ hidden: Bool) {
        settings.hidden = hidden
        for pet in pets.values {
            if hidden { pet.hide() } else { pet.show() }
        }
        save()
    }

    func setCursorMode(_ mode: CursorMode) {
        settings.cursorMode = mode
        save()
    }

    func setScale(_ scale: Int) {
        settings.scale = min(max(scale, 1), 3)
        for pet in pets.values { pet.scale = CGFloat(settings.scale) }
        save()
    }

    func showPicker() {
        picker.show()
    }

    func catalog(forceRefresh: Bool) async throws -> [CatalogEntry] {
        try await store.catalog(forceRefresh: forceRefresh)
    }

    /// Records current pet positions and writes settings to disk.
    func save() {
        for index in settings.pets.indices {
            if let pet = pets[settings.pets[index].id] { settings.pets[index].position = pet.position }
        }
        settings.save(to: .standard)
    }

    private func makeController(for record: PetRecord) async throws -> PetController {
        let directory = try await store.spriteDirectory(for: record.spritePath)
        let sprites = try SpriteSet(directory: directory)
        return PetController(record: record, sprites: sprites, world: worldMonitor.world, scale: settings.scale)
    }

    private func attach(_ pet: PetController) {
        // addPet appends the record before attaching; a pet removed while loading is dropped.
        guard settings.pets.contains(where: { $0.id == pet.id }) else {
            pet.close()
            return
        }
        pets[pet.id] = pet
        if !settings.hidden { pet.show() }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTick == 0 ? 1.0 / 60.0 : min(now - lastTick, 0.1)
        lastTick = now
        guard !settings.hidden else { return }
        let world = worldMonitor.world
        let cursor = NSEvent.mouseLocation
        for pet in pets.values {
            pet.tick(dt: dt, world: world, cursor: cursor, mode: settings.cursorMode)
        }
    }
}
