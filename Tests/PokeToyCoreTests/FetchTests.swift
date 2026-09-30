import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct FetchTests {
    let cursor = CGPoint(x: 100, y: 60)

    func toy(_ playground: Playground) -> Item? {
        playground.items.first { $0.kind == .toyBall }
    }

    func carrier(_ playground: Playground) -> UUID? {
        if case .carried(let id)? = toy(playground)?.state { return id }
        return nil
    }

    @Test func nearestPetFetchesAndBringsItBack() {
        var (playground, ids) = makePlayground([300])
        let dropped = playground.dropToy(at: CGPoint(x: 500, y: 60))
        #expect(dropped != nil)
        let result = playUntil(&playground, seconds: 15, cursor: cursor) { _, events in
            events.contains(.fetched(petID: ids[0]))
        }
        #expect(result.met)
        #expect(result.events.contains(.emotion(petID: ids[0], .joyous)))
        play(&playground, seconds: 1, cursor: cursor)
        #expect(toy(playground)?.state == .free)
        #expect(abs((toy(playground)?.body.position.x ?? 0) - 100) < 40)
    }

    @Test func carriedBallFollowsThePet() {
        var (playground, ids) = makePlayground([300])
        playground.dropToy(at: CGPoint(x: 400, y: 60))
        let picked = playUntil(&playground, seconds: 10, cursor: cursor) { p, _ in carrier(p) != nil }
        #expect(picked.met)
        #expect(carrier(playground) == ids[0])
        for _ in 0..<30 {
            play(&playground, seconds: 1.0 / 60, cursor: cursor)
            guard carrier(playground) != nil, let pet = playground.pet(ids[0]), let ball = toy(playground) else { break }
            #expect(ball.body.position.x == pet.body.position.x)
            #expect(ball.body.position.y > pet.body.position.y)
        }
    }

    @Test func racersWhoLoseAreSad() {
        var (playground, ids) = makePlayground([300, 800])
        playground.dropToy(at: CGPoint(x: 400, y: 60))
        let picked = playUntil(&playground, seconds: 10, cursor: cursor) { p, _ in carrier(p) != nil }
        #expect(carrier(playground) == ids[0])
        #expect(picked.events.contains(.emotion(petID: ids[1], .sad)))
    }

    @Test func interruptedCarrierDropsTheBall() {
        var (playground, ids) = makePlayground([300])
        playground.dropToy(at: CGPoint(x: 400, y: 60))
        playUntil(&playground, seconds: 10, cursor: cursor) { p, _ in carrier(p) != nil }
        playground.handle(.dragBegan, pet: ids[0])
        play(&playground, seconds: 1.0 / 60, cursor: cursor)
        #expect(carrier(playground) == nil)
        #expect(toy(playground)?.state == .free)
        play(&playground, seconds: 1, cursor: cursor)
        #expect(toy(playground)?.body.isGrounded == true)
    }

    @Test func onlyOneToyBall() {
        var playground = Playground(seed: 1, scale: 1)
        #expect(playground.dropToy(at: CGPoint(x: 400, y: 300)) != nil)
        #expect(!playground.canDropToy)
        #expect(playground.dropToy(at: CGPoint(x: 500, y: 300)) == nil)
    }

    @Test func toyBallsAreNotTreats() {
        var (playground, _) = makePlayground([300])
        playground.dropToy(at: CGPoint(x: 400, y: 60))
        #expect(!ItemKind.toyBall.isTreat)
        #expect(playground.canDropTreat)
        play(&playground, seconds: 10, cursor: cursor)
        #expect(toy(playground) != nil)
    }

    @Test func untouchedToyDisappears() {
        let high = Surface(id: 9, minX: 300, maxX: 600, y: 600, kind: .window)
        let world = World(screens: [TestWorld.screen], surfaces: [TestWorld.floor, high])
        var playground = Playground(seed: 1, scale: 1)
        playground.dropToy(at: CGPoint(x: 450, y: 650))
        play(&playground, seconds: Playground.toyLifetime - 1, world: world)
        #expect(toy(playground) != nil)
        play(&playground, seconds: 2, world: world)
        #expect(toy(playground) == nil)
    }

    @Test func grabbingTheBallFromTheCarrierStopsItsWalk() {
        var (playground, ids) = makePlayground([300])
        playground.dropToy(at: CGPoint(x: 400, y: 60))
        playUntil(&playground, seconds: 10, cursor: cursor) { p, _ in carrier(p) != nil }
        let ball = toy(playground)!.id
        playground.handle(.pressed, item: ball)
        #expect(toy(playground)?.state == .held)
        #expect(playground.pet(ids[0])?.brain.script == nil)
    }

    @Test func carriersKeepTheBallWhileHoppingOverOthers() {
        var (playground, ids) = makePlayground([200, 380])
        let asleep = playground.pets[0].fallAsleep()  // a bystander between the carrier and the cursor
        #expect(asleep)
        playground.dropToy(at: CGPoint(x: 420, y: 60))
        let cursorLeft = CGPoint(x: 60, y: 60)
        playUntil(&playground, seconds: 10, cursor: cursorLeft) { p, _ in carrier(p) == ids[1] }
        var dropped = false
        let result = playUntil(&playground, seconds: 15, cursor: cursorLeft) { p, events in
            if carrier(p) == nil && !events.contains(.fetched(petID: ids[1])) { dropped = true }
            return events.contains(.fetched(petID: ids[1])) || dropped
        }
        #expect(result.met)
        #expect(!dropped)
    }

    @Test func startingAGameDropsTheBall() {
        var (playground, _) = makePlayground([300])
        playground.dropToy(at: CGPoint(x: 400, y: 60))
        playUntil(&playground, seconds: 10, cursor: cursor) { p, _ in carrier(p) != nil }
        playground.startGame(roster: [WildSpec(path: "0025", displayName: "Pikachu", metrics: .uniform())], seed: 1)
        play(&playground, seconds: 1.0 / 60, cursor: cursor)
        #expect(carrier(playground) == nil)
    }

    @Test func racersWhoGiveUpAreForgotten() {
        var (playground, ids) = makePlayground([300, 900])
        playground.dropToy(at: CGPoint(x: 600, y: 60))
        playUntil(&playground, seconds: 3, cursor: cursor) { p, _ in p.fetchRacers.count == 2 }
        playground.handle(.dragBegan, pet: ids[1])
        play(&playground, seconds: 1.0 / 60, cursor: cursor)
        #expect(!playground.fetchRacers.contains(ids[1]))
    }
}
