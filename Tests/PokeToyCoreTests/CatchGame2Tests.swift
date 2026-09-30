import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct CatchGame2Tests {
    let regular = WildSpec(path: "0025", displayName: "Pikachu", metrics: .uniform())
    let legend = WildSpec(path: "0150", displayName: "Mewtwo", metrics: .uniform(), isLegendary: true)
    let shinyable = WildSpec(path: "0133", displayName: "Eevee", metrics: .uniform(), shinyPath: "0133/0000/0001")

    func playing(_ roster: [WildSpec], seed: UInt64 = 1) -> CatchGame {
        var game = CatchGame(roster: roster, seed: seed)
        for _ in 0..<186 { game.advance(dt: 1.0 / 60) }
        return game
    }

    /// `count` spawns in a row (a long `dt` makes one due every call).
    func spawns(_ game: inout CatchGame, _ count: Int) -> [(spec: WildSpec, shiny: Bool)] {
        (0..<count).compactMap { _ in game.spawn(dt: 10, wildCount: 0) }
    }

    @Test func legendariesSpawnRarely() {
        var game = playing([regular, legend])
        let picks = spawns(&game, 4000)
        let share = Double(picks.filter { $0.spec.isLegendary }.count) / Double(picks.count)
        #expect(share > 0.03 && share < 0.07)
    }

    @Test func shiniesNeedAShinyPath() {
        var game = playing([regular])
        #expect(!spawns(&game, 2000).contains { $0.shiny })
    }

    @Test func shinyRate() {
        var game = playing([shinyable])
        let picks = spawns(&game, 20000)
        let share = Double(picks.filter(\.shiny).count) / Double(picks.count)
        #expect(share > 0.010 && share < 0.022)
    }

    @Test func comboRaisesTheBallTier() {
        var game = playing([regular])
        #expect(game.ballTier == .poke)
        for _ in 0..<3 { game.recordHit() }
        #expect(game.ballTier == .great)
        for _ in 0..<2 { game.recordHit() }
        #expect(game.ballTier == .ultra)
    }

    @Test func aMissResetsTheCombo() {
        var game = playing([regular])
        for _ in 0..<5 { game.recordHit() }
        game.registerMiss()
        #expect(game.combo == 0)
        #expect(game.ballTier == .poke)
    }

    @Test func catchChanceFollowsTheTierAndCalm() {
        #expect(BallTier.poke.catchChance == 0.6)
        #expect(BallTier.great.catchChance == 0.75)
        #expect(BallTier.ultra.catchChance == 0.9)
        let game = playing([regular])
        #expect(abs(game.catchChance(tier: .great, calmed: true) - 0.9) < 1e-9)
        #expect(game.catchChance(tier: .ultra, calmed: true) == 1)
    }

    @Test func pointsMultiply() {
        var game = playing([regular])
        game.recordHit(isLegendary: true)  // 25 × 3, combo 1
        #expect(game.score == 75)
        game.recordHit(isShiny: true)  // 25 × 2 × 1.25 (combo 2) = 62.5
        #expect(game.score == 75 + 63)
        game.recordCatch(CatchRecord(petID: UUID(), path: "0150", displayName: "Mewtwo", position: .zero, isShiny: true),
                         isLegendary: true)  // 100 × 3 × 2 × 1.25
        #expect(game.score == 75 + 63 + 750)
    }

    @Test func comboMultiplierIsCapped() {
        var game = playing([regular])
        for _ in 0..<10 { game.recordHit() }
        let before = game.score
        game.recordHit()
        #expect(game.score - before == 50)  // 25 × 2
    }

    @Test func firstThrowBonus() {
        var game = playing([regular])
        game.recordHit()
        game.recordCatch(CatchRecord(petID: UUID(), path: "0025", displayName: "Pikachu", position: .zero), firstThrow: true)
        #expect(game.score == 25 + 100 + 50)
    }

    @Test func threeBerriesPerRound() {
        var game = playing([regular])
        #expect(game.berriesLeft == 3)
        let uses = (0..<4).map { _ in game.useBerry() }
        #expect(uses == [true, true, true, false])
        #expect(game.berriesLeft == 0)
    }

    func sequence(_ game: inout CatchGame, _ count: Int) -> [String] {
        (0..<count).compactMap { _ in game.spawn(dt: 10, wildCount: 0) }.map { $0.spec.path }
    }

    @Test func rosterOrderDoesNotChangeTheRound() {
        let a = WildSpec(path: "0001", displayName: "A", metrics: .uniform())
        let b = WildSpec(path: "0004", displayName: "B", metrics: .uniform())
        let c = WildSpec(path: "0007", displayName: "C", metrics: .uniform())
        var first = playing([a, b, c], seed: 9)
        var second = playing([c, a, b], seed: 9)
        #expect(sequence(&first, 50) == sequence(&second, 50))
        #expect(first.rollCatch().caught == second.rollCatch().caught)
    }

    @Test func optionalExtrasDoNotShiftTheRandomSequence() {
        let plain = WildSpec(path: "0133", displayName: "Eevee", metrics: .uniform())
        var withShiny = playing([shinyable, regular], seed: 5)
        var withoutShiny = playing([plain, regular], seed: 5)
        #expect(sequence(&withShiny, 50) == sequence(&withoutShiny, 50))
        #expect((0..<20).map { _ in withShiny.rollCatch().caught } == (0..<20).map { _ in withoutShiny.rollCatch().caught })
        #expect(withShiny.randomUnit() == withoutShiny.randomUnit())
    }

    @Test func catchesCanPayTheComboOfTheHit() {
        var game = playing([regular])
        game.recordCatch(CatchRecord(petID: UUID(), path: "0025", displayName: "Pikachu", position: .zero), multiplier: 1.75)
        #expect(game.score == 175)
    }
}
