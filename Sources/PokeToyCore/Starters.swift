import Foundation

/// The Pokémon a new player chooses their first pet from.
public enum Starters {
    public static let all: [CatalogEntry] = [
        CatalogEntry(path: "0025", displayName: "Pikachu"),
        CatalogEntry(path: "0004", displayName: "Charmander"),
        CatalogEntry(path: "0007", displayName: "Squirtle"),
        CatalogEntry(path: "0001", displayName: "Bulbasaur"),
    ]
}
