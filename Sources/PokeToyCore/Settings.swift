import CoreGraphics
import Foundation

public struct PetRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// SpriteCollab path, e.g. `0025` or `0025/0000/0001`.
    public var spritePath: String
    public var displayName: String
    /// Last known feet position; nil means "spawn at the top of the screen".
    public var position: CGPoint?
    /// Treats eaten since joining (or since the last evolution).
    public var treatsEaten: Int
    /// A shiny Pokémon (stays shiny when it evolves).
    public var isShiny: Bool

    public init(id: UUID = UUID(), spritePath: String, displayName: String, position: CGPoint? = nil,
                treatsEaten: Int = 0, isShiny: Bool = false) {
        self.id = id
        self.spritePath = spritePath
        self.displayName = displayName
        self.position = position
        self.treatsEaten = treatsEaten
        self.isShiny = isShiny
    }

    private enum CodingKeys: String, CodingKey {
        case id, spritePath, displayName, position, treatsEaten, isShiny
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        spritePath = try container.decode(String.self, forKey: .spritePath)
        displayName = try container.decode(String.self, forKey: .displayName)
        position = try container.decodeIfPresent(CGPoint.self, forKey: .position)
        treatsEaten = (try? container.decodeIfPresent(Int.self, forKey: .treatsEaten)) ?? 0
        // Older records only said so in the name.
        isShiny = (try? container.decodeIfPresent(Bool.self, forKey: .isShiny)) ?? displayName.contains("(Shiny")
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var pets: [PetRecord]
    public var hidden: Bool
    public var cursorMode: CursorMode
    /// Pixel scale, 1...3.
    public var scale: Int
    /// `Friendships.points`, keyed `"<uuidA>+<uuidB>"`.
    public var friendships: [String: Int]
    public var bestCatchScore: Int
    /// Caught species by base form path (`0025`).
    public var pokedex: [String: PokedexEntry]
    /// Best daily-challenge score by day (`yyyy-MM-dd`).
    public var dailyBest: [String: Int]

    public static let defaultPet = PetRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
                                             spritePath: "0025", displayName: "Pikachu")
    public static let `default` = Settings(pets: [defaultPet], hidden: false, cursorMode: .off, scale: 2)

    public init(pets: [PetRecord], hidden: Bool, cursorMode: CursorMode, scale: Int,
                friendships: [String: Int] = [:], bestCatchScore: Int = 0,
                pokedex: [String: PokedexEntry] = [:], dailyBest: [String: Int] = [:]) {
        self.pets = pets
        self.hidden = hidden
        self.cursorMode = cursorMode
        self.scale = scale
        self.friendships = friendships
        self.bestCatchScore = bestCatchScore
        self.pokedex = pokedex
        self.dailyBest = dailyBest
    }

    private enum CodingKeys: String, CodingKey {
        case pets, hidden, cursorMode, scale, friendships, bestCatchScore, pokedex, dailyBest
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pets = try container.decodeIfPresent([PetRecord].self, forKey: .pets) ?? Self.default.pets
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        cursorMode = (try? container.decodeIfPresent(CursorMode.self, forKey: .cursorMode)) ?? .off
        scale = min(max(try container.decodeIfPresent(Int.self, forKey: .scale) ?? 2, 1), 3)
        friendships = (try? container.decodeIfPresent([String: Int].self, forKey: .friendships)) ?? [:]
        bestCatchScore = (try? container.decodeIfPresent(Int.self, forKey: .bestCatchScore)) ?? 0
        pokedex = (try? container.decodeIfPresent([String: PokedexEntry].self, forKey: .pokedex)) ?? [:]
        dailyBest = (try? container.decodeIfPresent([String: Int].self, forKey: .dailyBest)) ?? [:]
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
