import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct AttentionTests {
    let cursor = CGPoint(x: 800, y: 60)

    @Test func petsComeToTheCursor() {
        var (playground, ids) = makePlayground([200, 300])
        playground.seekAttention(ids[0])
        #expect(playground.isSeekingAttention)
        play(&playground, seconds: 10, cursor: cursor)  // cursor mode is off: they come anyway
        for id in ids { #expect(abs(playground.pet(id)!.body.position.x - cursor.x) < 80) }
    }

    @Test func onlyTheTimersPetWhenAsked() {
        var (playground, ids) = makePlayground([200, 300])
        playground.seekAttention(ids[0], everyone: false)
        play(&playground, seconds: 10, cursor: cursor)
        #expect(abs(playground.pet(ids[0])!.body.position.x - cursor.x) < 80)
        #expect(abs(playground.pet(ids[1])!.body.position.x - cursor.x) > 200)
    }

    @Test func atTheCursorTheyHopAndCallOut() {
        var (playground, ids) = makePlayground([780])
        playground.seekAttention(ids[0])
        var hops = 0
        var calls = 0
        for _ in 0..<(8 * 60) {
            let events = playground.tick(dt: 1.0 / 60, world: TestWorld.floorOnly, cursor: cursor, cursorMode: .off)
            calls += events.filter { if case .emotion(ids[0], _) = $0 { return true }; return false }.count
            if playground.pet(ids[0])!.brain.pose.anim == .react { hops += 1 }
        }
        #expect(hops > 0)
        #expect(calls >= 3)
    }

    @Test func sleepersWakeUp() {
        var (playground, ids) = makePlayground([200])
        _ = playground.pets[0].fallAsleep(indefinitely: true)  // as when the user is away
        #expect(playground.pet(ids[0])!.brain.isSleeping)
        playground.seekAttention(ids[0])
        play(&playground, seconds: 3, cursor: cursor)
        #expect(!playground.pet(ids[0])!.brain.isSleeping)
    }

    @Test func clickingAnyOfThemEndsIt() {
        var (playground, ids) = makePlayground([200, 300])
        playground.seekAttention(ids[0])
        play(&playground, seconds: 1, cursor: cursor)
        playground.handle(.pressed, pet: ids[1])
        playground.handle(.click, pet: ids[1])
        #expect(!playground.isSeekingAttention)
    }

    @Test func theyGiveUpAfterAMinute() {
        var (playground, ids) = makePlayground([200])
        playground.seekAttention(ids[0])
        play(&playground, seconds: Playground.attentionTime - 1, cursor: cursor)
        #expect(playground.isSeekingAttention)
        play(&playground, seconds: 2, cursor: cursor)
        #expect(!playground.isSeekingAttention)
    }

    @Test func theOptionIsOnByDefault() {
        #expect(PomodoroOptions().seekAttention)
    }
}
