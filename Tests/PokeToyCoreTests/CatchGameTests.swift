import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct CatchGameTests {
    let spec = WildSpec(path: "0025", displayName: "Pikachu", metrics: .uniform())

    /// Advances `seconds` in 1/60 s steps and returns how many steps reported the round finishing.
    @discardableResult
    func advance(_ game: inout CatchGame, seconds: Double) -> Int {
        var finishes = 0
        for _ in 0..<Int((seconds * 60).rounded()) where game.advance(dt: 1.0 / 60) { finishes += 1 }
        return finishes
    }

    @Test func metricsComeFromTheSpriteSet() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk", width: 8, height: 6, durations: [2, 4])])
        let metrics = PetMetrics(sprites: try SpriteSet(directory: dir))
        #expect(metrics.durations[.walk] == [2, 4])
        #expect(metrics.frameSizes[.eat] == CGSize(width: 8, height: 6))
        #expect(PetMetrics.uniform().frameSizes[.idle] == CGSize(width: 32, height: 40))
    }

    @Test func countsDownThenPlaysThenFinishesOnce() {
        var game = CatchGame(roster: [spec], seed: 1)
        #expect(game.phase == .countdown(remaining: 3))
        advance(&game, seconds: 2.9)
        #expect(!game.isPlaying)
        #expect(game.isActive)
        advance(&game, seconds: 0.2)
        #expect(game.isPlaying)
        #expect(advance(&game, seconds: 61) == 1)
        #expect(game.phase == .finished)
        #expect(!game.isActive)
    }

    @Test func requestingTheEndFinishesOnTheNextStep() {
        var countingDown = CatchGame(roster: [spec], seed: 1)
        countingDown.requestEnd()
        let ok1 = countingDown.advance(dt: 1.0 / 60)
        #expect(ok1)
        #expect(countingDown.phase == .finished)

        var playing = CatchGame(roster: [spec], seed: 1)
        advance(&playing, seconds: 4)
        playing.requestEnd()
        let ok2 = playing.advance(dt: 1.0 / 60)
        #expect(ok2)
    }

    @Test func noSpawnsDuringCountdownAndTheFirstSoonAfterGo() {
        var game = CatchGame(roster: [spec], seed: 2)
        for _ in 0..<(3 * 60 - 2) {
            game.advance(dt: 1.0 / 60)
            #expect(game.spawn(dt: 1.0 / 60, wildCount: 0) == nil)
        }
        var spawnedAt: Int?
        for step in 0..<120 {
            game.advance(dt: 1.0 / 60)
            if game.spawn(dt: 1.0 / 60, wildCount: 0) != nil { spawnedAt = step; break }
        }
        #expect(spawnedAt != nil)
        #expect((spawnedAt ?? 999) <= 40)
    }

    @Test func respectsTheWildCap() {
        var game = CatchGame(roster: [spec], seed: 3)
        advance(&game, seconds: 3.1)
        for _ in 0..<(20 * 60) {
            game.advance(dt: 1.0 / 60)
            #expect(game.spawn(dt: 1.0 / 60, wildCount: CatchGame.maxWild) == nil)
        }
    }

    @Test func spawnsEveryFourToSevenSeconds() {
        var game = CatchGame(roster: [spec], seed: 4)
        advance(&game, seconds: 3.1)
        var times: [Double] = []
        for step in 0..<(55 * 60) {
            game.advance(dt: 1.0 / 60)
            if game.spawn(dt: 1.0 / 60, wildCount: 0) != nil { times.append(Double(step) / 60) }
        }
        #expect(times.count >= 7)
        for (earlier, later) in zip(times, times.dropFirst()) {
            #expect(later - earlier >= 4 - 0.02 && later - earlier <= 7 + 0.02)
        }
    }

    @Test func emptyRosterNeverSpawns() {
        var game = CatchGame(roster: [], seed: 5)
        advance(&game, seconds: 3.1)
        for _ in 0..<(10 * 60) { #expect(game.spawn(dt: 1.0 / 60, wildCount: 0) == nil) }
    }

    @Test func lifetimesAreTwelveToTwentySeconds() {
        var game = CatchGame(roster: [spec], seed: 6)
        for _ in 0..<200 {
            let lifetime = game.wildLifetime()
            #expect(lifetime >= 12 && lifetime <= 20)
        }
    }

    @Test func catchRollsMatchTheChance() {
        var game = CatchGame(roster: [spec], seed: 7)
        var caught = 0
        var wobbleCounts = Set<Int>()
        for _ in 0..<2000 {
            let roll = game.rollCatch()
            if roll.caught { caught += 1 }
            wobbleCounts.insert(roll.wobbles)
        }
        #expect(Double(caught) / 2000 > 0.55 && Double(caught) / 2000 < 0.65)
        #expect(wobbleCounts == [1, 2, 3])
    }

    @Test func scoring() {
        var game = CatchGame(roster: [spec], seed: 8)
        game.recordHit()
        #expect(game.score == 25)
        game.recordCatch(CatchRecord(petID: UUID(), path: "0025", displayName: "Pikachu", position: .zero))
        #expect(game.score == 125)
        #expect(game.catches.count == 1)
    }

    @Test func keepableRespectsThePetCap() {
        let record = CatchRecord(petID: UUID(), path: "0025", displayName: "Pikachu", position: .zero)
        #expect(CatchGame.keepable([record, record, record], ownPetCount: 10, cap: 12) == 2)
        #expect(CatchGame.keepable([record], ownPetCount: 12, cap: 12) == 0)
        #expect(CatchGame.keepable([record], ownPetCount: 1, cap: 12) == 1)
    }
}
