import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct PlaygroundTests {
    @Test func addedPetsFallAndLand() {
        var playground = Playground(seed: 1, scale: 1)
        let id = playground.addPet(metrics: .uniform(), at: CGPoint(x: 500, y: 400))
        play(&playground, seconds: 1)
        #expect(playground.pet(id)?.body.surfaceID == -1)
        #expect(playground.pet(id)?.role == .own)
        #expect(playground.pet(id)?.brain.personality == .pet)
    }

    @Test func clicksReachTheBrainAndTheReactionEnds() {
        var (playground, ids) = makePlayground([500])
        playground.handle(.click, pet: ids[0])
        #expect(playground.pet(ids[0])?.brain.state == .react)
        play(&playground, seconds: 0.5)
        #expect(playground.pet(ids[0])?.brain.isFree == true)
    }

    @Test func draggedPetsStayWhereTheyAreMoved() {
        var (playground, ids) = makePlayground([500])
        playground.handle(.dragBegan, pet: ids[0])
        playground.movePet(ids[0], to: CGPoint(x: 300, y: 500))
        play(&playground, seconds: 0.5)
        #expect(playground.pet(ids[0])?.body.position == CGPoint(x: 300, y: 500))
        playground.handle(.dragEnded(velocity: .zero), pet: ids[0])
        play(&playground, seconds: 1)
        #expect(playground.pet(ids[0])?.body.isGrounded == true)
    }

    @Test func ownPetsLostOffScreenRespawn() {
        var (playground, ids) = makePlayground([500])
        playground.handle(.dragBegan, pet: ids[0])
        playground.movePet(ids[0], to: CGPoint(x: 500, y: -2000))
        playground.handle(.dragEnded(velocity: .zero), pet: ids[0])
        play(&playground, seconds: 1.0 / 60)
        #expect((playground.pet(ids[0])?.body.position.y ?? 0) > 700)
    }

    @Test func wildPetsLeavingTheScreenAreRemoved() {
        var playground = Playground(seed: 1, scale: 1)
        let id = playground.addPet(role: .wild, metrics: .uniform(), at: CGPoint(x: 500, y: 51))
        #expect(playground.pet(id)?.brain.personality == .wild)
        playground.movePet(id, to: CGPoint(x: 1300, y: 51))
        let events = play(&playground, seconds: 1.0 / 60)
        #expect(playground.pet(id) == nil)
        #expect(events.contains(.wildRemoved(petID: id)))
    }

    @Test func removingAPetDropsItsFriendships() {
        var (playground, ids) = makePlayground([300, 600])
        playground.friendships.add(ids[0], ids[1], 5)
        playground.removePet(ids[0])
        #expect(playground.pet(ids[0]) == nil)
        #expect(playground.friendships.score(ids[0], ids[1]) == 0)
    }

    @Test func treatsDropFallAndAreCapped() {
        var playground = Playground(seed: 1, scale: 1)
        let id = playground.dropTreat(.apple, at: CGPoint(x: 500, y: 400))
        #expect(id != nil)
        #expect(playground.dropTreat(.pokeBall, at: .zero) == nil)
        play(&playground, seconds: 1)
        #expect(playground.items.first?.body.surfaceID == -1)
        for _ in 0..<20 { playground.dropTreat(.oranBerry, at: CGPoint(x: 200, y: 400)) }
        #expect(playground.items.count == Playground.maxTreats)
        #expect(!playground.canDropTreat)
    }

    @Test func treatsCanBeDraggedAndThrown() {
        var playground = Playground(seed: 1, scale: 1)
        let id = playground.dropTreat(.apple, at: CGPoint(x: 500, y: 60))!
        play(&playground, seconds: 0.2)
        playground.handle(.pressed, item: id)
        playground.handle(.dragBegan, item: id)
        playground.moveItem(id, to: CGPoint(x: 300, y: 400))
        play(&playground, seconds: 0.5)
        #expect(playground.items.first?.body.position == CGPoint(x: 300, y: 400))
        playground.handle(.dragEnded(velocity: CGVector(dx: 300, dy: 0)), item: id)
        play(&playground, seconds: 1)
        #expect(playground.items.first?.state == .free)
        #expect((playground.items.first?.body.position.x ?? 0) > 330)
        #expect(playground.items.first?.body.isGrounded == true)
    }

    @Test func pressedTreatsHangUntilReleased() {
        var playground = Playground(seed: 1, scale: 1)
        let id = playground.dropTreat(.apple, at: CGPoint(x: 500, y: 400))!
        playground.handle(.pressed, item: id)
        play(&playground, seconds: 0.5)
        #expect(playground.items.first?.body.position.y == 400)
        playground.handle(.released, item: id)
        play(&playground, seconds: 1)
        #expect(playground.items.first?.body.isGrounded == true)
    }

    @Test func scaleAppliesToEveryPet() {
        var (playground, ids) = makePlayground([300, 600])
        let before = playground.pet(ids[0])!.halfWidth
        playground.setScale(3)
        #expect(abs(playground.pet(ids[1])!.halfWidth - before * 3) < 1e-9)
        let wild = playground.addPet(role: .wild, metrics: .uniform(), at: CGPoint(x: 500, y: 51))
        #expect(playground.pet(wild)?.scale == 3)
    }

    @Test func hiddenActorsAreNotSimulated() {
        var (playground, ids) = makePlayground([500])
        playground.pets[0].visible = false
        playground.movePet(ids[0], to: CGPoint(x: 500, y: 400))
        play(&playground, seconds: 0.5)
        #expect(playground.pet(ids[0])?.body.position.y == 400)
    }

    @Test func rectanglesTrackTheFeet() {
        let (playground, ids) = makePlayground([500], scale: 2)
        let pet = playground.pet(ids[0])!
        #expect(pet.halfWidth == 32 * 2 * 0.3)
        #expect(abs(pet.bodyRect.midX - 500) < 1e-9)
        #expect(pet.bodyRect.minY == 50)
        #expect(pet.hitRect.width == 32 * 2 * 0.8)
        #expect(pet.hitRect.contains(CGPoint(x: 500, y: 80)))
    }
}
