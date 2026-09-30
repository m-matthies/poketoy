import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct CatchDataTests {
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    var catalog: [CatalogEntry] {
        var entries = (1...40).map { CatalogEntry(path: Evolution.path(for: $0), displayName: "Mon \($0)", isComplete: true) }
        entries += [144, 150, 151, 249].map { CatalogEntry(path: Evolution.path(for: $0), displayName: "Legend \($0)", isComplete: true) }
        entries.append(CatalogEntry(path: "0025/0000/0001", displayName: "Pikachu (Shiny)", isComplete: true))
        entries.append(CatalogEntry(path: "0041", displayName: "Incomplete", isComplete: false))
        return entries
    }

    @Test func knowsLegendaries() {
        for dex in [144, 150, 151, 249, 384, 493, 800, 1025] { #expect(Legendaries.isLegendary(dex: dex)) }
        for dex in [1, 25, 133, 149, 448] { #expect(!Legendaries.isLegendary(dex: dex)) }
    }

    @Test func dailySeedAndKeyFollowTheDate() {
        #expect(DailyChallenge.seed(for: date(2026, 9, 30)) == 20_260_930)
        #expect(DailyChallenge.key(for: date(2026, 9, 30)) == "2026-09-30")
        #expect(DailyChallenge.seed(for: date(2026, 10, 1)) != DailyChallenge.seed(for: date(2026, 9, 30)))
    }

    @Test func dailyRosterIsDeterministic() {
        let seed = DailyChallenge.seed(for: date(2026, 9, 30))
        let first = DailyChallenge.roster(from: catalog, seed: seed)
        #expect(first == DailyChallenge.roster(from: catalog.shuffled(), seed: seed))
        #expect(first != DailyChallenge.roster(from: catalog, seed: seed + 1))
    }

    @Test func dailyRosterHasOneLegendaryAndBaseFormsOnly() {
        let roster = DailyChallenge.roster(from: catalog, seed: 20_260_930)
        #expect(roster.count == 8)
        #expect(roster.filter { Legendaries.isLegendary(dex: Evolution.dexNumber(of: $0.path) ?? 0) }.count == 1)
        #expect(roster.allSatisfy { !$0.path.contains("/") && $0.isComplete })
        #expect(Set(roster.map(\.path)).count == 8)
    }

    @Test func pokedexRecordsCatches() {
        var pokedex: [String: PokedexEntry] = [:]
        let pikachu = CatchRecord(petID: UUID(), path: "0025", displayName: "Pikachu", position: .zero)
        let shiny = CatchRecord(petID: UUID(), path: "0025/0000/0001", displayName: "Pikachu", position: .zero, isShiny: true)
        Pokedex.record([pikachu], into: &pokedex, at: date(2026, 9, 1))
        Pokedex.record([shiny], into: &pokedex, at: date(2026, 9, 2))
        #expect(pokedex["0025"] == PokedexEntry(displayName: "Pikachu", firstCaught: date(2026, 9, 1), count: 2, shinyCaught: true))
    }

    @Test func pokedexCompletion() {
        var pokedex: [String: PokedexEntry] = [:]
        Pokedex.record([CatchRecord(petID: UUID(), path: "0001", displayName: "Mon 1", position: .zero)], into: &pokedex, at: Date())
        // 44 distinct complete species (1…40, 144, 150, 151, 249; the shiny form is Pikachu again, 41 is incomplete).
        #expect(abs(Pokedex.completion(caught: pokedex, catalog: catalog) - 1.0 / 44) < 1e-9)
        #expect(Pokedex.completion(caught: [:], catalog: []) == 0)
    }

    @Test func settingsDecodePokedexAndDailyBest() throws {
        var settings = Settings.default
        settings.pokedex = ["0025": PokedexEntry(displayName: "Pikachu", firstCaught: Date(timeIntervalSince1970: 0), count: 1, shinyCaught: false)]
        settings.dailyBest = ["2026-09-30": 450]
        let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(again == settings)
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"scale": 2}"#.utf8))
        #expect(old.pokedex.isEmpty && old.dailyBest.isEmpty)
    }

    @Test func storeFetchesTypes() async throws {
        let base = makeTempDirectory()
        try FileManager.default.createDirectory(at: base.appendingPathComponent("pokemon"), withIntermediateDirectories: true)
        let json = #"{"types": [{"slot": 1, "type": {"name": "normal"}}, {"slot": 2, "type": {"name": "flying"}}]}"#
        try Data(json.utf8).write(to: base.appendingPathComponent("pokemon/16"))
        let store = EvolutionStore(cacheDirectory: makeTempDirectory(), remoteBase: base)
        #expect(try await store.types(of: 16) == ["normal", "flying"])
    }

    @Test func pokedexRecordsPets() {
        var pokedex: [String: PokedexEntry] = [:]
        Pokedex.recordPet(path: "0133", displayName: "Eevee", into: &pokedex, at: date(2026, 9, 1))
        #expect(pokedex["0133"] == PokedexEntry(displayName: "Eevee", firstCaught: date(2026, 9, 1), count: 0,
                                                shinyCaught: false, everOwned: true))
        // A caught species that later becomes a pet keeps its catch history.
        Pokedex.record([CatchRecord(petID: UUID(), path: "0025", displayName: "Pikachu", position: .zero)],
                       into: &pokedex, at: date(2026, 9, 2))
        Pokedex.recordPet(path: "0025/0000/0001", displayName: "Pikachu (Shiny)", into: &pokedex, at: date(2026, 9, 3))
        #expect(pokedex["0025"] == PokedexEntry(displayName: "Pikachu", firstCaught: date(2026, 9, 2), count: 1,
                                                shinyCaught: true, everOwned: true))
    }

    @Test func petsCountTowardCompletion() {
        var pokedex: [String: PokedexEntry] = [:]
        Pokedex.recordPet(path: "0001", displayName: "Mon 1", into: &pokedex, at: Date())
        #expect(abs(Pokedex.completion(caught: pokedex, catalog: catalog) - 1.0 / 44) < 1e-9)
    }

    @Test func oldEntriesDecodeWithoutEverOwned() throws {
        let json = #"{"displayName": "Pikachu", "firstCaught": 0, "count": 2, "shinyCaught": false}"#
        let entry = try JSONDecoder().decode(PokedexEntry.self, from: Data(json.utf8))
        #expect(!entry.everOwned)
        #expect(entry.count == 2)
    }
}
