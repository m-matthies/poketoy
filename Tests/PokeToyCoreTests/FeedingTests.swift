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

    @Test func feedingSpotIsWhereAPetCanReachIt() {
        let left = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                              visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))
        let right = ScreenInfo(frame: CGRect(x: 1000, y: 0, width: 2000, height: 800),
                               visibleFrame: CGRect(x: 1000, y: 0, width: 2000, height: 775))
        let world = World.build(screens: [left, right], windows: [], primaryScreenHeight: 800)
        var empty = Playground(seed: 1, scale: 1)
        #expect(empty.feedingSpot(cursor: CGPoint(x: 1500, y: 400), world: world) == CGPoint(x: 1500, y: 765))
        empty.addPet(metrics: .uniform(), at: CGPoint(x: 300, y: 51))
        play(&empty, seconds: 0.05, world: world)
        // Cursor on a screen without pets: drop above the pet instead.
        #expect(empty.feedingSpot(cursor: CGPoint(x: 1500, y: 400), world: world).x == empty.pets[0].body.position.x)
        // Cursor near the pet on its screen: drop at the cursor.
        #expect(empty.feedingSpot(cursor: CGPoint(x: 900, y: 400), world: world) == CGPoint(x: 900, y: 765))

        var wide = Playground(seed: 1, scale: 1)
        wide.addPet(metrics: .uniform(), at: CGPoint(x: 1100, y: 1))
        play(&wide, seconds: 0.05, world: world)
        // Same screen but beyond sight range: drop above the pet.
        #expect(wide.feedingSpot(cursor: CGPoint(x: 2900, y: 400), world: world).x == wide.pets[0].body.position.x)
    }

    @Test func uneatenTreatsSpoil() {
        let high = Surface(id: 9, minX: 300, maxX: 600, y: 600, kind: .window)
        let world = World(screens: [TestWorld.screen], surfaces: [TestWorld.floor, high])
        var playground = Playground(seed: 1, scale: 1)
        playground.dropTreat(.apple, at: CGPoint(x: 450, y: 650))
        play(&playground, seconds: Playground.treatLifetime - 1, world: world)
        #expect(playground.items.count == 1)
        play(&playground, seconds: 2, world: world)
        #expect(playground.items.isEmpty)
    }

    @Test func handlingATreatKeepsItFresh() {
        let high = Surface(id: 9, minX: 300, maxX: 600, y: 600, kind: .window)
        let world = World(screens: [TestWorld.screen], surfaces: [TestWorld.floor, high])
        var playground = Playground(seed: 1, scale: 1)
        let treat = playground.dropTreat(.apple, at: CGPoint(x: 450, y: 650))!
        play(&playground, seconds: Playground.treatLifetime - 5, world: world)
        playground.handle(.pressed, item: treat)
        playground.handle(.released, item: treat)
        play(&playground, seconds: 10, world: world)
        #expect(playground.items.count == 1)
    }

    @Test func petsGoForTheClosestTreatNotTheFirstDropped() {
        var (playground, ids) = makePlayground([300])
        let far = playground.dropTreat(.apple, at: CGPoint(x: 800, y: 60))!
        let near = playground.dropTreat(.oranBerry, at: CGPoint(x: 400, y: 60))!
        let result = playUntil(&playground, seconds: 10) { _, events in eaten(events) != nil }
        #expect(eaten(result.events) == ids[0])
        #expect(playground.items.map(\.id) == [far])
        #expect(!playground.items.contains { $0.id == near })
    }

    @Test func twoPetsSplitTwoTreatsWithoutClashing() {
        var (playground, ids) = makePlayground([300, 700])
        playground.dropTreat(.apple, at: CGPoint(x: 450, y: 60))
        playground.dropTreat(.oranBerry, at: CGPoint(x: 550, y: 60))
        var eaters: [UUID] = []
        for _ in 0..<(8 * 60) {
            for event in play(&playground, seconds: 1.0 / 60) {
                if case .treatEaten(let id) = event { eaters.append(id) }
            }
            let a = playground.pet(ids[0])!, b = playground.pet(ids[1])!
            #expect(abs(a.body.position.x - b.body.position.x) >= a.halfWidth + b.halfWidth - 1)
        }
        #expect(Set(eaters) == Set(ids))
        #expect(eaters.count == 2)
    }

    @Test func onlyOnePetChasesASingleTreat() {
        var (playground, _) = makePlayground([250, 600])
        playground.dropTreat(.apple, at: CGPoint(x: 400, y: 60))
        for _ in 0..<(4 * 60) {
            play(&playground, seconds: 1.0 / 60)
            #expect(playground.treatTargets.count <= 1)
        }
    }
}
