import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct CollisionTests {
    func isThrownFall(_ state: PetBrain.State?) -> Bool {
        if case .fall(_, true) = state { return true }
        return false
    }

    @Test func aThrownPetKnocksAnotherOver() {
        var (playground, ids) = makePlayground([500], scale: 2)
        let thrown = playground.addPet(metrics: .uniform(), at: CGPoint(x: 420, y: 120))
        playground.handle(.dragBegan, pet: thrown)
        playground.handle(.dragEnded(velocity: CGVector(dx: 600, dy: 0)), pet: thrown)
        let result = playUntil(&playground, seconds: 1) { p, _ in isThrownFall(p.pet(ids[0])?.brain.state) }
        #expect(result.met)
        #expect(playground.pet(ids[0])?.body.velocity == CGVector(dx: 220, dy: 380))
        #expect(playground.pet(ids[0])?.pose.anim == .dangle)
        #expect((playground.pet(thrown)?.body.velocity.dx ?? 0) < 0)
        #expect((playground.knockCooldowns[Friendships.key(thrown, ids[0])] ?? 0) > 0)
        play(&playground, seconds: 2)
        #expect(playground.pet(ids[0])?.body.isGrounded == true)
        #expect((playground.pet(ids[0])?.body.position.x ?? 0) > 520)
    }

    @Test func aGentleDropDoesNotKnockAnyoneOver() {
        var (playground, ids) = makePlayground([500], scale: 2)
        let dropped = playground.addPet(metrics: .uniform(), at: CGPoint(x: 470, y: 52))
        playground.handle(.dragBegan, pet: dropped)
        playground.handle(.dragEnded(velocity: CGVector(dx: 100, dy: 0)), pet: dropped)
        for _ in 0..<30 {
            play(&playground, seconds: 1.0 / 60)
            #expect(!isThrownFall(playground.pet(ids[0])?.brain.state))
        }
    }


    @Test func wildPokemonAreNeverKnocked() {
        var playground = Playground(seed: 1, scale: 2)
        let wild = playground.addPet(role: .wild, metrics: .uniform(), at: CGPoint(x: 500, y: 51))
        let thrown = playground.addPet(metrics: .uniform(), at: CGPoint(x: 420, y: 120))
        play(&playground, seconds: 1.0 / 60)
        playground.handle(.dragBegan, pet: thrown)
        playground.handle(.dragEnded(velocity: CGVector(dx: 600, dy: 0)), pet: thrown)
        for _ in 0..<60 {
            play(&playground, seconds: 1.0 / 60)
            #expect(!isThrownFall(playground.pet(wild)?.brain.state))
        }
    }
}
