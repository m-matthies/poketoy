import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct FeedingTests {
    func eaten(_ events: [PlaygroundEvent]) -> UUID? {
        for event in events { if case .treatEaten(let id) = event { return id } }
        return nil
    }

    @Test func aPetWalksToATreatAndEatsIt() {
        var (playground, ids) = makePlayground([300])
        playground.dropTreat(.apple, at: CGPoint(x: 500, y: 300))
        let result = playUntil(&playground, seconds: 10) { _, events in eaten(events) != nil }
        #expect(result.met)
        #expect(eaten(result.events) == ids[0])
        #expect(playground.items.isEmpty)
        #expect(playground.pet(ids[0])?.brain.script?.anim == .eat)
        play(&playground, seconds: 2.6)
        #expect(playground.pet(ids[0])?.pose.anim == .greet)
        #expect(playground.pet(ids[0])?.pose.hearts == 1)
    }

    @Test func closestPetWinsOthersAreSad() {
        var (playground, ids) = makePlayground([250, 700, 900])
        playground.dropTreat(.oranBerry, at: CGPoint(x: 400, y: 300))
        let result = playUntil(&playground, seconds: 10) { _, events in eaten(events) != nil }
        #expect(eaten(result.events) == ids[0])
        #expect(playground.pet(ids[1])?.pose.anim == .sad)
        #expect(playground.pet(ids[2])?.pose.anim == .sad)
        let more = play(&playground, seconds: 3)
        #expect(eaten(more) == nil)
    }

    @Test func sleepingPetsIgnoreTreats() {
        var (playground, ids) = makePlayground([500])
        let ok1 = playground.pets[0].fallAsleep()
        #expect(ok1)
        playground.dropTreat(.apple, at: CGPoint(x: 520, y: 60))
        play(&playground, seconds: 2)
        #expect(playground.items.count == 1)
        #expect(playground.pet(ids[0])?.brain.isSleeping == true)
    }

    @Test func heldTreatsAreIgnored() {
        var (playground, _) = makePlayground([300])
        let treat = playground.dropTreat(.apple, at: CGPoint(x: 350, y: 60))!
        playground.handle(.pressed, item: treat)
        play(&playground, seconds: 3)
        #expect(playground.items.count == 1)
        #expect(playground.treatTargets.isEmpty)
    }

    @Test func petsNearTheTreatBecomeFriendlier() {
        var (playground, ids) = makePlayground([380, 430])
        playground.dropTreat(.apple, at: CGPoint(x: 405, y: 52))
        let result = playUntil(&playground, seconds: 10) { _, events in eaten(events) != nil }
        #expect(result.met)
        #expect(playground.friendships.score(ids[0], ids[1]) >= 1)
        #expect(result.events.contains(.friendshipChanged))
    }

    @Test func treatsOnAReachableWindowAreReachedByJumping() {
        var (playground, ids) = makePlayground([700], world: TestWorld.withShelf)
        playground.dropTreat(.apple, at: CGPoint(x: 450, y: 300))
        let result = playUntil(&playground, seconds: 8, world: TestWorld.withShelf) { _, events in eaten(events) != nil }
        #expect(result.met)
        #expect(playground.pet(ids[0])?.body.surfaceID == 7)
    }

    @Test func unreachableTreatIsIgnored() {
        let high = Surface(id: 9, minX: 300, maxX: 600, y: 600, kind: .window)
        let world = World(screens: [TestWorld.screen], surfaces: [TestWorld.floor, high])
        var (playground, ids) = makePlayground([450], world: world)
        playground.dropTreat(.apple, at: CGPoint(x: 450, y: 650))
        play(&playground, seconds: 3, world: world)
        #expect(playground.items.count == 1)
        #expect(playground.items.first?.body.surfaceID == 9)
        #expect(playground.treatTargets.isEmpty)
        #expect(playground.pet(ids[0])?.body.surfaceID == -1)
    }
}
