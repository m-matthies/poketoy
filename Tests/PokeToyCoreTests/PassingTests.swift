import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct PassingTests {
    /// True when both pets stand on the same surface with their bodies overlapping.
    func overlapping(_ a: PetActor, _ b: PetActor) -> Bool {
        a.body.isGrounded && a.body.surfaceID == b.body.surfaceID
            && abs(a.body.position.x - b.body.position.x) < a.halfWidth + b.halfWidth - 1
    }

    func isHopping(_ state: PetBrain.State?) -> Bool {
        if case .hop = state { return true }
        return false
    }

    @Test func aHopKeepsTheScriptGoing() {
        var brain = PetBrain(seed: 1)
        var body = Body(position: CGPoint(x: 400, y: 50), surfaceID: -1)
        brain.perform(Script(anim: .walk, moveTo: 700, end: .arrived, priority: 1), body: &body)
        let hopped = brain.hop(to: 480, on: TestWorld.floor, halfWidth: 10, body: &body)
        #expect(hopped)
        #expect(isHopping(brain.state))
        #expect(brain.script?.moveTo == 700)
        for _ in 0..<(6 * 60) {
            brain.update(BrainContext(dt: 1.0 / 60, world: TestWorld.floorOnly, cursor: farAway, cursorMode: .off,
                                      halfWidth: 10, animationFinished: false), body: &body)
            Physics.step(&body, dt: 1.0 / 60, world: TestWorld.floorOnly)
        }
        #expect(abs(body.position.x - 700) <= 2)
    }

    @Test func aPetOnItsWayHopsOverASleeper() {
        var (playground, ids) = makePlayground([400, 460])
        let asleep = playground.pets[1].fallAsleep()
        #expect(asleep)
        playground.pets[0].perform(Script(anim: .walk, moveTo: 700, end: .arrived, priority: 1))
        var hopped = false
        for _ in 0..<(8 * 60) {
            play(&playground, seconds: 1.0 / 60)
            let walker = playground.pet(ids[0])!, sleeper = playground.pet(ids[1])!
            #expect(!overlapping(walker, sleeper))
            if isHopping(walker.brain.state) { hopped = true }
        }
        #expect(hopped)
        #expect(abs(playground.pet(ids[0])!.body.position.x - 700) <= 2)
    }

    @Test func aPetWhoseGoalIsInFrontStopsShort() {
        var (playground, ids) = makePlayground([400, 460])
        let asleep = playground.pets[1].fallAsleep()
        #expect(asleep)
        playground.pets[0].perform(Script(anim: .walk, moveTo: 455, end: .arrived, priority: 1))
        play(&playground, seconds: 2)
        let walker = playground.pet(ids[0])!, sleeper = playground.pet(ids[1])!
        #expect(!overlapping(walker, sleeper))
        #expect(walker.body.position.x < 460)
        #expect(walker.brain.script == nil)
    }

    @Test func blockedWanderersHopTurnBackOrPlay() {
        var hops = 0, turns = 0, chases = 0, fights = 0
        let trials = 300
        for seed in 0..<UInt64(trials) {
            var (playground, _) = makePlayground([440, 460], seed: seed)
            guard playground.moments.isEmpty else { continue }  // they already met during setup
            // The first pet walks right (following a cursor far to the right) straight into the second.
            playground.pets[0].update(BrainContext(dt: 1.0 / 60, world: TestWorld.floorOnly, cursor: CGPoint(x: 900, y: 60),
                                                   cursorMode: .follow, halfWidth: playground.pets[0].halfWidth,
                                                   animationFinished: false))
            playground.passingRules(dt: 1.0 / 60, world: TestWorld.floorOnly)
            if let moment = playground.moments.first {
                if moment.kind == .tag { chases += 1 } else { fights += 1 }
                #expect(moment.kind != .greet)
            } else if isHopping(playground.pets[0].brain.state) {
                hops += 1
            } else {
                turns += 1
                #expect(playground.pets[0].body.velocity.dx <= 0)
            }
        }
        #expect(hops > trials / 5 && turns > trials / 5)
        #expect(chases > trials / 20 && fights > trials / 20)
    }

    @Test func wildAndOwnPetsDoNotBlockEachOther() {
        var (playground, ids) = makePlayground([400])
        let wild = playground.addPet(role: .wild, metrics: .uniform(), at: CGPoint(x: 460, y: 51))
        play(&playground, seconds: 0.05)
        playground.pets[0].perform(Script(anim: .walk, moveTo: 700, end: .arrived, priority: 1))
        for _ in 0..<(5 * 60) {
            play(&playground, seconds: 1.0 / 60)
            #expect(!isHopping(playground.pet(ids[0])?.brain.state))
            _ = wild
        }
    }

    @Test func petsSqueezePastWhenThereIsNoRoomToHop() {
        let world = TestWorld.withShelf  // shelf 300…600
        var (playground, _) = makePlayground([], world: world)
        let blocker = playground.addPet(metrics: .uniform(), at: CGPoint(x: 580, y: 251))
        let walker = playground.addPet(metrics: .uniform(), at: CGPoint(x: 450, y: 251))
        play(&playground, seconds: 0.1, world: world)
        let asleep = playground.pets[0].fallAsleep()
        #expect(asleep)
        playground.pets[1].perform(Script(anim: .walk, moveTo: 595, end: .arrived, priority: 1))
        var hopped = false, arrived = false
        for _ in 0..<(6 * 60) {
            play(&playground, seconds: 1.0 / 60, world: world)
            if isHopping(playground.pet(walker)?.brain.state) { hopped = true }
            if abs((playground.pet(walker)?.body.position.x ?? 0) - 595) <= 2 { arrived = true }
        }
        #expect(!hopped)
        #expect(arrived)
        #expect(playground.pet(blocker) != nil)
    }

    @Test func petsStuckBehindAnotherEventuallySqueezePast() {
        var (playground, ids) = makePlayground([900, 980])
        let asleep = playground.pets[1].fallAsleep()
        #expect(asleep)
        // Following a cursor beyond the sleeper, with no room to land past it at the screen edge.
        let result = playUntil(&playground, seconds: 15, cursor: CGPoint(x: 995, y: 60), mode: .follow) { p, _ in
            (p.pet(ids[0])?.body.position.x ?? 0) > 981
        }
        #expect(result.met)
    }
}
