import Foundation

/// One species in the user's Pokédex.
public struct PokedexEntry: Codable, Equatable, Sendable {
    public var displayName: String
    public var firstCaught: Date
    public var count: Int
    public var shinyCaught: Bool

    public init(displayName: String, firstCaught: Date, count: Int, shinyCaught: Bool) {
        self.displayName = displayName
        self.firstCaught = firstCaught
        self.count = count
        self.shinyCaught = shinyCaught
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

    /// Share of species with complete sprites that have been caught (0…1).
    public static func completion(caught: [String: PokedexEntry], catalog: [CatalogEntry]) -> Double {
        let species = Set(catalog.filter(\.isComplete).compactMap { key(forPath: $0.path) })
        guard !species.isEmpty else { return 0 }
        return Double(species.intersection(caught.keys).count) / Double(species.count)
    }
}
