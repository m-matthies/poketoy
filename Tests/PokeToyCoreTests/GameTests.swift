import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct GameTests {
    let spec = WildSpec(path: "0025", displayName: "Pikachu", metrics: .uniform())

    func started(_ xs: [CGFloat] = [500]) -> (Playground, [UUID]) {
        var (playground, ids) = makePlayground(xs)
        playground.startGame(roster: [spec], seed: 3)
        return (playground, ids)
    }

    func wild(_ playground: Playground) -> PetActor? {
        playground.pets.first { $0.role == .wild }
    }

    /// Plays until a wild Pokémon stands on the floor, and returns it.
    func untilWildLands(_ playground: inout Playground) -> PetActor? {
        playUntil(&playground, seconds: 6) { p, _ in wild(p)?.body.isGrounded == true }
        return wild(playground)
    }

    func ballAbove(_ pet: PetActor) -> CGPoint {
        CGPoint(x: pet.body.position.x, y: pet.body.position.y + 10)
    }

    @Test func wildPokemonArriveAfterTheCountdown() {
        var (playground, _) = started()
        let early = play(&playground, seconds: 2.9)
        #expect(!early.contains { if case .wildSpawned = $0 { return true }; return false })
        let later = play(&playground, seconds: 1)
        let arrived = wild(playground)
        #expect(arrived != nil)
        #expect(later.contains(.wildSpawned(petID: arrived!.id, path: "0025")))
        #expect(arrived?.brain.personality == .wild)
    }

    @Test func ownPetsSitWhileTreatsAndMomentsPause() {
        var (playground, ids) = started([490, 510])
        play(&playground, seconds: 0.1)
        #expect(playground.pet(ids[0])?.brain.script?.anim == .sit)
        #expect(playground.pet(ids[0])?.brain.script?.priority == 3)
        #expect(!playground.canDropTreat)
        #expect(playground.dropTreat(.apple, at: CGPoint(x: 500, y: 300)) == nil)
        play(&playground, seconds: 5)
        #expect(playground.moments.isEmpty)
    }

    @Test func aHitScoresAndACatchIsRecorded() {
        var (playground, ids) = started()
        playground.game!.catchChance = 1
        let target = untilWildLands(&playground)!
        let ok1 = playground.throwBall(from: ballAbove(target), velocity: .zero)
        #expect(ok1)
        let hit = play(&playground, seconds: 1.0 / 60)
        #expect(hit.contains(.ballHit(petID: target.id)))
        #expect(playground.game?.score == 25)
        #expect(playground.pet(target.id)?.visible == false)
        let result = playUntil(&playground, seconds: 3) { _, events in events.contains(.caught(petID: target.id)) }
        #expect(result.met)
        #expect(result.events.contains(.wildRemoved(petID: target.id)))
        #expect(playground.game?.score == 125)
        #expect(playground.game?.catches.map(\.displayName) == ["Pikachu"])
        #expect(playground.pet(target.id) == nil)
        #expect(playground.pet(ids[0])?.brain.script?.anim == .cheer)
    }

    @Test func aWildThatBreaksFreeComesBack() {
        var (playground, _) = started()
        playground.game!.catchChance = 0
        let target = untilWildLands(&playground)!
        playground.throwBall(from: ballAbove(target), velocity: .zero)
        let result = playUntil(&playground, seconds: 3) { _, events in events.contains(.brokeFree(petID: target.id)) }
        #expect(result.met)
        #expect(playground.pet(target.id)?.visible == true)
        #expect(playground.game?.score == 25)
        #expect(!playground.items.contains { if case .wobbling = $0.state { return true }; return false })
    }

    @Test func theRoundEndsWithResults() {
        var (playground, ids) = started()
        let events = play(&playground, seconds: 63.2)
        #expect(events.contains(.roundEnded))
        #expect(playground.game == nil)
        #expect(playground.lastResults != nil)
        #expect((playground.pet(ids[0])?.brain.script?.priority ?? 0) < 3)
        #expect(playground.canDropTreat)
    }

    @Test func endingMidWobbleResolvesTheCatch() {
        var (playground, _) = started()
        playground.game!.catchChance = 1
        let target = untilWildLands(&playground)!
        playground.throwBall(from: ballAbove(target), velocity: .zero)
        play(&playground, seconds: 1.0 / 60)
        playground.endGame()
        let events = play(&playground, seconds: 1.0 / 60)
        #expect(events.contains(.roundEnded))
        #expect(events.contains(.caught(petID: target.id)))
        #expect(playground.lastResults?.catches.map(\.petID) == [target.id])
        #expect(!playground.pets.contains { !$0.visible })
    }

    @Test func wildPokemonLeaveWhenTheirTimeIsUp() {
        var (playground, _) = started()
        let target = untilWildLands(&playground)!
        let index = playground.pets.firstIndex { $0.id == target.id }!
        playground.pets[index].lifetime = 0.05
        let result = playUntil(&playground, seconds: 12) { _, events in events.contains(.wildRemoved(petID: target.id)) }
        #expect(result.met)
    }

    @Test func throwsOnlyWhilePlayingAndAtMostEightInFlight() {
        var (playground, _) = started()
        let up = CGVector(dx: 0, dy: 800)
        let ok2 = playground.throwBall(from: CGPoint(x: 500, y: 600), velocity: up)
        #expect(!ok2)
        play(&playground, seconds: 3.1)
        for _ in 0..<CatchGame.maxBallsInFlight {
            let ok3 = playground.throwBall(from: CGPoint(x: 500, y: 600), velocity: up)
            #expect(ok3)
        }
        let ok4 = playground.throwBall(from: CGPoint(x: 500, y: 600), velocity: up)
        #expect(!ok4)
        #expect(playground.ballsInFlight == CatchGame.maxBallsInFlight)
    }

    @Test func ballsPassThroughOwnPets() {
        var (playground, ids) = started()
        play(&playground, seconds: 3.1)
        playground.throwBall(from: ballAbove(playground.pet(ids[0])!), velocity: .zero)
        let events = play(&playground, seconds: 1)
        #expect(!events.contains { if case .ballHit = $0 { return true }; return false })
    }
}
