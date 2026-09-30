import Foundation

/// One species in the user's Pokédex: caught in the catch game and/or kept as a pet.
public struct PokedexEntry: Codable, Equatable, Sendable {
    public var displayName: String
    /// When it first entered the Pokédex (first catch or first time it became a pet).
    public var firstCaught: Date
    /// Times caught in the catch game.
    public var count: Int
    /// A shiny one was caught or kept.
    public var shinyCaught: Bool
    /// It has been one of the user's pets (now or in the past).
    public var everOwned: Bool

    public init(displayName: String, firstCaught: Date, count: Int, shinyCaught: Bool, everOwned: Bool = false) {
        self.displayName = displayName
        self.firstCaught = firstCaught
        self.count = count
        self.shinyCaught = shinyCaught
        self.everOwned = everOwned
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, firstCaught, count, shinyCaught, everOwned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        firstCaught = try container.decode(Date.self, forKey: .firstCaught)
        count = (try? container.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        shinyCaught = (try? container.decodeIfPresent(Bool.self, forKey: .shinyCaught)) ?? false
        everOwned = (try? container.decodeIfPresent(Bool.self, forKey: .everOwned)) ?? false
    }
}

public enum Pokedex {
    /// The species key (base form path, e.g. `0025`) for any SpriteCollab path.
    public static func key(forPath path: String) -> String? {
        Evolution.dexNumber(of: path).map(Evolution.path(for:))
    }

    public static func record(_ catches: [CatchRecord], into pokedex: inout [String: PokedexEntry], at date: Date) {
        for record in catches {
            guard let key = key(forPath: record.path) else { continue }
            if var entry = pokedex[key] {
                entry.count += 1
                entry.shinyCaught = entry.shinyCaught || record.isShiny
                pokedex[key] = entry
            } else {
                pokedex[key] = PokedexEntry(displayName: record.displayName, firstCaught: date, count: 1,
                                            shinyCaught: record.isShiny)
            }
        }
    }

    /// Records that the Pokémon at `path` became (or is) one of the user's pets.
    public static func recordPet(path: String, displayName: String, isShiny: Bool? = nil,
                                 into pokedex: inout [String: PokedexEntry], at date: Date) {
        guard let key = key(forPath: path) else { return }
        let shiny = isShiny ?? displayName.contains("(Shiny")
        if var entry = pokedex[key] {
            entry.everOwned = true
            entry.shinyCaught = entry.shinyCaught || shiny
            pokedex[key] = entry
        } else {
            pokedex[key] = PokedexEntry(displayName: speciesName(displayName), firstCaught: date, count: 0,
                                        shinyCaught: shiny, everOwned: true)
        }
    }

    /// "Pikachu (Shiny, Female)" → "Pikachu".
    static func speciesName(_ displayName: String) -> String {
        displayName.components(separatedBy: " (").first ?? displayName
    }

    /// Share of species with complete sprites that have been caught or kept (0…1).
    public static func completion(caught: [String: PokedexEntry], catalog: [CatalogEntry]) -> Double {
        let species = Set(catalog.filter(\.isComplete).compactMap { key(forPath: $0.path) })
        guard !species.isEmpty else { return 0 }
        return Double(species.intersection(caught.keys).count) / Double(species.count)
    }
}

extension Pokedex {
    /// `entries` shuffled, species not yet in the Pokédex first.
    public static func newFirst(_ entries: [CatalogEntry], pokedex: [String: PokedexEntry],
                                using rng: inout some RandomNumberGenerator) -> [CatalogEntry] {
        let isKnown = { (entry: CatalogEntry) in key(forPath: entry.path).map { pokedex[$0] != nil } ?? false }
        return entries.filter { !isKnown($0) }.shuffled(using: &rng) + entries.filter(isKnown).shuffled(using: &rng)
    }
}
