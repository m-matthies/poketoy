import Foundation
import Testing
@testable import PokeToyCore

@Suite struct StarterAndPokedexTests {
    func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PokeToyTests-\(UUID().uuidString)")!
    }

    // MARK: - Starter

    @Test func aFirstStartHasNoPetsAndAsksForAStarter() {
        let settings = Settings.load(from: freshDefaults())
        #expect(settings.pets.isEmpty)
        #expect(!settings.starterChosen)
    }

    @Test func existingPlayersAreNotAskedAgain() {
        let defaults = freshDefaults()
        let json = #"{"pets": [{"id": "00000000-0000-0000-0000-000000000025", "spritePath": "0025", "displayName": "Pikachu"}]}"#
        defaults.set(Data(json.utf8), forKey: "settings")
        let settings = Settings.load(from: defaults)
        #expect(settings.starterChosen)
        #expect(settings.pets.map(\.spritePath) == ["0025"])
    }

    @Test func theChoiceIsRemembered() {
        let defaults = freshDefaults()
        var settings = Settings.default
        settings.starterChosen = true
        settings.save(to: defaults)
        #expect(Settings.load(from: defaults).starterChosen)
    }

    @Test func fourStartersToChooseFrom() {
        #expect(Starters.all.map(\.path) == ["0025", "0004", "0007", "0001"])
        #expect(Starters.all.map(\.displayName) == ["Pikachu", "Charmander", "Squirtle", "Bulbasaur"])
    }

    // MARK: - Pokédex rows

    @Test func pokedexListsDownloadedSpeciesInDexOrder() {
        let pikachu = PokedexEntry(displayName: "Pikachu", firstCaught: Date(timeIntervalSince1970: 0), count: 1,
                                   shinyCaught: false)
        let rows = Pokedex.rows(pokedex: ["0025": pikachu],
                                downloaded: ["0150", "0025/0000/0001", "0004", "0004/0000/0001"],
                                names: ["0004": "Charmander", "0150": "Mewtwo", "0025": "Pikachu"])
        #expect(rows.map(\.key) == ["0004", "0025", "0150"])
        #expect(rows.map(\.displayName) == ["Charmander", "Pikachu", "Mewtwo"])
        #expect(rows.map { $0.entry != nil } == [false, true, false])
    }

    @Test func unnamedDownloadsShowTheirNumber() {
        let rows = Pokedex.rows(pokedex: [:], downloaded: ["0999"], names: [:])
        #expect(rows.map(\.displayName) == ["Pokémon #0999"])
    }

    // MARK: - Descriptions

    let speciesJSON = #"""
    {"id": 25, "is_legendary": false, "is_mythical": false, "evolution_chain": null,
     "genera": [{"genus": "Souris Pokémon", "language": {"name": "fr"}}, {"genus": "Mouse Pokémon", "language": {"name": "en"}}],
     "flavor_text_entries": [
       {"flavor_text": "When several of\nthese POKéMON\ngather, their\felectricity could\nbuild and cause\nlightning storms.", "language": {"name": "en"}},
       {"flavor_text": "Il stocke l'électricité.", "language": {"name": "fr"}},
       {"flavor_text": "Pikachu that can generate\npowerful electricity have cheek sacs that are extra soft­and super stretchy.", "language": {"name": "en"}}
     ]}
    """#

    @Test func descriptionsUseTheNewestEnglishText() throws {
        let description = try PokemonDescription.parse(speciesJSON: Data(speciesJSON.utf8), types: ["electric"])
        #expect(description.genus == "Mouse Pokémon")
        #expect(description.flavor == "Pikachu that can generate powerful electricity have cheek sacs that are extra soft and super stretchy.")
        #expect(description.summary.hasPrefix("Electric · Mouse Pokémon — Pikachu that can"))
    }

    @Test func descriptionsTolerateMissingText() throws {
        let json = #"{"id": 1, "is_legendary": false, "is_mythical": false}"#
        let description = try PokemonDescription.parse(speciesJSON: Data(json.utf8), types: ["grass", "poison"])
        #expect(description.summary == "Grass/Poison")
    }

    @Test func storeFetchesDescriptions() async throws {
        let base = makeTempDirectory()
        for folder in ["pokemon-species", "pokemon"] {
            try FileManager.default.createDirectory(at: base.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data(speciesJSON.utf8).write(to: base.appendingPathComponent("pokemon-species/25"))
        try Data(#"{"types": [{"slot": 1, "type": {"name": "electric"}}]}"#.utf8).write(to: base.appendingPathComponent("pokemon/25"))
        let store = EvolutionStore(cacheDirectory: makeTempDirectory(), remoteBase: base)
        let description = try await store.description(of: 25)
        #expect(description.genus == "Mouse Pokémon")
        #expect(description.types == ["electric"])
    }

    // MARK: - Reset

    @Test func resetDeletesDownloadsButKeepsBundledSprites() async throws {
        let cache = makeTempDirectory()
        try writeSpriteDirectory(at: cache.appendingPathComponent("sprite/0004"), anims: [TestAnim(name: "Idle"), TestAnim(name: "Walk")])
        try FileManager.default.createDirectory(at: cache.appendingPathComponent("portrait/0004"), withIntermediateDirectories: true)
        let bundle = makeTempDirectory()
        try writeSpriteDirectory(at: bundle.appendingPathComponent("0025"), anims: [TestAnim(name: "Idle"), TestAnim(name: "Walk")])
        let store = SpriteStore(cacheDirectory: cache, remoteBase: URL(fileURLWithPath: "/nonexistent-remote"),
                                bundledSprites: bundle)
        #expect(await store.cachedSpritePaths() == ["0004", "0025"])
        await store.clearDownloads()
        #expect(await store.cachedSpritePaths() == ["0025"])
        #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent("portrait").path))
    }
}
