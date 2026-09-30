import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct VariedWildsTests {
    let regular = WildSpec(path: "0025", displayName: "Pikachu", metrics: .uniform())
    let legend = WildSpec(path: "0150", displayName: "Mewtwo", metrics: .uniform(), isLegendary: true)
    let flyer = WildSpec(path: "0016", displayName: "Pidgey", metrics: .uniform(), canFly: true)

    func specs(_ count: Int) -> [WildSpec] {
        (1...count).map { WildSpec(path: String(format: "%04d", $0), displayName: "Mon \($0)", metrics: .uniform()) }
    }

    func playing(_ roster: [WildSpec], seed: UInt64 = 1) -> CatchGame {
        var game = CatchGame(roster: roster, seed: seed)
        for _ in 0..<186 { game.advance(dt: 1.0 / 60) }
        return game
    }

    func spawned(_ game: inout CatchGame, _ count: Int) -> [String] {
        (0..<count).compactMap { _ in game.spawn(dt: 10, wildCount: 0) }.map { $0.spec.path }
    }

    func caught(_ path: String) -> CatchRecord {
        CatchRecord(petID: UUID(), path: path, displayName: "Mon", position: .zero)
    }

    // MARK: - Variety

    @Test(arguments: 1...20 as ClosedRange<UInt64>) func everyRosterPokemonAppearsBeforeAnyRepeats(seed: UInt64) {
        var game = playing(specs(10), seed: seed)
        #expect(Set(spawned(&game, 10)).count == 10)
    }

    @Test(arguments: 1...20 as ClosedRange<UInt64>) func noPokemonAppearsTwiceInARow(seed: UInt64) {
        var game = playing(specs(3), seed: seed)
        let paths = spawned(&game, 60)
        #expect(zip(paths, paths.dropFirst()).allSatisfy { $0 != $1 })
    }

    @Test func caughtSpeciesDontSpawnAgain() {
        var game = playing(specs(4))
        game.recordCatch(caught("0002/0000/0001"))  // a shiny catch counts for its species
        #expect(!spawned(&game, 40).contains("0002"))
    }

    @Test func aCaughtLegendaryDoesntReturn() {
        var game = playing([regular, legend])
        game.recordCatch(caught("0150"), isLegendary: true)
        #expect(!spawned(&game, 2000).contains("0150"))
    }

    @Test func onceEverythingIsCaughtTheRosterComesBack() {
        var game = playing(specs(2))
        game.recordCatch(caught("0001"))
        game.recordCatch(caught("0002"))
        #expect(spawned(&game, 3).count == 3)
    }

    // MARK: - Where they appear

    /// Where the first wild Pokémon of a round with `seed` appears.
    func firstSpawn(_ roster: [WildSpec], seed: UInt64) -> CGPoint? {
        var playground = Playground(seed: seed)
        playground.startGame(roster: roster, seed: seed)
        var point: CGPoint?
        playUntil(&playground, seconds: 4, world: TestWorld.withShelf) { p, _ in
            point = p.pets.first { $0.role == .wild }?.body.position
            return point != nil
        }
        return point
    }

    @Test func wildsAppearAllOverNotOnlyAtTheEdges() {
        let points = (1...60 as ClosedRange<UInt64>).compactMap { firstSpawn([regular], seed: $0) }
        #expect(points.count == 60)
        #expect(points.filter { $0.x > 120 && $0.x < 880 && $0.y < 100 }.count >= 10)  // out on the floor
        #expect(points.filter { $0.y > 200 && $0.x >= 300 && $0.x <= 600 }.count >= 5)  // on the window
        #expect(points.contains { $0.x < 60 || $0.x > 940 })  // and still walking in from the edges
    }

    @Test func flyersAppearAcrossTheScreen() {
        let xs = (1...40 as ClosedRange<UInt64>).compactMap { firstSpawn([flyer], seed: $0)?.x }
        #expect(xs.count == 40)
        #expect(xs.filter { $0 > 120 && $0 < 880 }.count >= 10)
    }

    // MARK: - Roster

    @Test func newSpeciesComeFirst() {
        let entries = (1...20).map { CatalogEntry(path: String(format: "%04d", $0), displayName: "Mon \($0)") }
        let known = Dictionary(uniqueKeysWithValues: entries.prefix(15).map {
            ($0.path, PokedexEntry(displayName: $0.displayName, firstCaught: Date(), count: 1, shinyCaught: false))
        })
        var rng = SplitMix64(seed: 3)
        let ordered = Pokedex.newFirst(entries, pokedex: known, using: &rng)
        #expect(Set(ordered.prefix(5).map(\.path)) == Set(entries.suffix(5).map(\.path)))
        #expect(Set(ordered.map(\.path)) == Set(entries.map(\.path)))
    }
}
