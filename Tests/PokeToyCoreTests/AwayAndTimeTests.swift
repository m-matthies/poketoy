import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct AwayTests {
    @Test func petsNapWhileTheUserIsAway() {
        var (playground, ids) = makePlayground([300, 600])
        playground.setUserIdle(301)
        play(&playground, seconds: 1)
        #expect(ids.allSatisfy { playground.pet($0)?.brain.isSleeping == true })
        playground.setUserIdle(600)
        play(&playground, seconds: 200)
        #expect(ids.allSatisfy { playground.pet($0)?.brain.isSleeping == true })
    }

    @Test func returningUserWakesEveryone() {
        var (playground, ids) = makePlayground([300, 600])
        playground.setUserIdle(301)
        play(&playground, seconds: 1)
        playground.setUserIdle(0.5)
        let events = play(&playground, seconds: 1.0 / 60)
        for id in ids {
            #expect(events.contains(.emotion(petID: id, .happy)))
            #expect(playground.pet(id)?.pose.anim == .wake)
        }
        play(&playground, seconds: 2)
        #expect(ids.allSatisfy { playground.pet($0)?.brain.isSleeping == false })
    }
}

@Suite struct TimeOfDayTests {
    @Test func hoursMapToTimesOfDay() {
        #expect(TimeOfDay(hour: 23) == .night)
        #expect(TimeOfDay(hour: 3) == .night)
        #expect(TimeOfDay(hour: 6) == .morning)
        #expect(TimeOfDay(hour: 9) == .morning)
        #expect(TimeOfDay(hour: 10) == .day)
        #expect(TimeOfDay(hour: 21) == .day)
    }

    @Test func nightPetsGetSleepyFast() {
        var (playground, ids) = makePlayground([500])
        playground.timeOfDay = .night
        let result = playUntil(&playground, seconds: 40) { p, _ in p.pet(ids[0])?.brain.isSleeping == true }
        #expect(result.met)
    }

    /// Fastest wandering speed seen over `seconds`.
    func topSpeed(_ configure: (inout Playground) -> Void, seconds: Double = 30) -> CGFloat {
        var (playground, ids) = makePlayground([500])
        configure(&playground)
        var top: CGFloat = 0
        for _ in 0..<Int(seconds * 60) {
            play(&playground, seconds: 1.0 / 60)
            if let pet = playground.pet(ids[0]), pet.body.isGrounded { top = max(top, abs(pet.body.velocity.dx)) }
        }
        return top
    }

    @Test func morningPetsAreFaster() {
        #expect(abs(topSpeed { $0.timeOfDay = .day } - PetBrain.walkSpeed) < 0.01)
        #expect(abs(topSpeed { $0.timeOfDay = .morning } - PetBrain.walkSpeed * 1.2) < 0.01)
    }
}

@Suite struct ReduceMotionTests {
    @Test func reduceMotionMeansNoRandomJumps() {
        var (playground, ids) = makePlayground([450], world: TestWorld.withShelf)
        playground.reduceMotion = true
        for _ in 0..<(120 * 60) {
            play(&playground, seconds: 1.0 / 60, world: TestWorld.withShelf)
            #expect(playground.pet(ids[0])?.brain.state != .jump)
        }
    }

    @Test func reduceMotionWalksSlower() {
        var (playground, ids) = makePlayground([500])
        playground.reduceMotion = true
        var top: CGFloat = 0
        for _ in 0..<(30 * 60) {
            play(&playground, seconds: 1.0 / 60)
            top = max(top, abs(playground.pet(ids[0])?.body.velocity.dx ?? 0))
        }
        #expect(top > 0)
        #expect(top <= PetBrain.walkSpeed * 0.7 + 0.01)
    }

    @Test func reduceMotionTurnsBackInsteadOfHopping() {
        for seed in 0..<UInt64(100) {
            var (playground, _) = makePlayground([440, 460], seed: seed)
            guard playground.moments.isEmpty else { continue }
            playground.reduceMotion = true
            playground.pets[0].update(BrainContext(dt: 1.0 / 60, world: TestWorld.floorOnly, cursor: CGPoint(x: 900, y: 60),
                                                   cursorMode: .follow, halfWidth: playground.pets[0].halfWidth,
                                                   animationFinished: false))
            playground.passingRules(dt: 1.0 / 60, world: TestWorld.floorOnly)
            if case .hop = playground.pets[0].brain.state { Issue.record("hopped with Reduce Motion (seed \(seed))") }
        }
    }
}

@Suite struct ReduceMotionMoreTests {
    @Test func followingIsCalmerWithReduceMotion() {
        var (playground, ids) = makePlayground([450], world: TestWorld.withShelf)
        playground.reduceMotion = true
        var top: CGFloat = 0
        for _ in 0..<(10 * 60) {
            play(&playground, seconds: 1.0 / 60, world: TestWorld.withShelf, cursor: CGPoint(x: 450, y: 320), mode: .follow)
            #expect(playground.pet(ids[0])?.brain.state != .jump)
            top = max(top, abs(playground.pet(ids[0])?.body.velocity.dx ?? 0))
        }
        var (walker, others) = makePlayground([100])
        walker.reduceMotion = true
        for _ in 0..<(3 * 60) {
            play(&walker, seconds: 1.0 / 60, cursor: CGPoint(x: 900, y: 60), mode: .follow)
            top = max(top, abs(walker.pet(others[0])?.body.velocity.dx ?? 0))
        }
        #expect(top <= PetBrain.walkSpeed * 1.4 * 0.7 + 0.01)
    }

    @Test func scriptedWalksAreCalmerWithReduceMotion() {
        var (playground, ids) = makePlayground([100])
        playground.reduceMotion = true
        playground.pets[0].perform(Script(anim: .walk, moveTo: 900, speed: 100, end: .arrived, priority: 1))
        play(&playground, seconds: 0.5)
        #expect(abs(abs(playground.pet(ids[0])?.body.velocity.dx ?? 0) - 70) < 0.01)
    }
}
