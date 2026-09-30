import CoreGraphics
import Foundation

public struct PetRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// SpriteCollab path, e.g. `0025` or `0025/0000/0001`.
    public var spritePath: String
    public var displayName: String
    /// Last known feet position; nil means "spawn at the top of the screen".
    public var position: CGPoint?

    public init(id: UUID = UUID(), spritePath: String, displayName: String, position: CGPoint? = nil) {
        self.id = id
        self.spritePath = spritePath
        self.displayName = displayName
        self.position = position
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var pets: [PetRecord]
    public var hidden: Bool
    public var cursorMode: CursorMode
    /// Pixel scale, 1...3.
    public var scale: Int

    public static let defaultPet = PetRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
                                             spritePath: "0025", displayName: "Pikachu")
    public static let `default` = Settings(pets: [defaultPet], hidden: false, cursorMode: .off, scale: 2)

    public init(pets: [PetRecord], hidden: Bool, cursorMode: CursorMode, scale: Int) {
        self.pets = pets
        self.hidden = hidden
        self.cursorMode = cursorMode
        self.scale = scale
    }

    private enum CodingKeys: String, CodingKey {
        case pets, hidden, cursorMode, scale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pets = try container.decodeIfPresent([PetRecord].self, forKey: .pets) ?? Self.default.pets
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        cursorMode = (try? container.decodeIfPresent(CursorMode.self, forKey: .cursorMode)) ?? .off
        scale = min(max(try container.decodeIfPresent(Int.self, forKey: .scale) ?? 2, 1), 3)
    }

    public static func load(from defaults: UserDefaults, key: String = "settings") -> Settings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return .default }
        return settings
    }

    public func save(to defaults: UserDefaults, key: String = "settings") {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: key)
        }
    }
}
