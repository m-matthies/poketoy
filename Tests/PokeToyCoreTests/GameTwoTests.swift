import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct GameTwoTests {
    let regular = WildSpec(path: "0025", displayName: "Pikachu", metrics: .uniform())
    let shinyable = WildSpec(path: "0133", displayName: "Eevee", metrics: .uniform(), shinyPath: "0133/0000/0001")
    let flyer = WildSpec(path: "0016", displayName: "Pidgey", metrics: .uniform(), canFly: true)

    func started(_ roster: [WildSpec], pets: [CGFloat] = [500]) -> (Playground, [UUID]) {
        var (playground, ids) = makePlayground(pets)
        playground.startGame(roster: roster, seed: 3)
        return (playground, ids)
    }

    func wild(_ playground: Playground) -> PetActor? {
        playground.pets.first { $0.role == .wild && $0.visible }
    }

    @Test func throwsUseTheCurrentTier() {
        var (playground, _) = started([regular])
        play(&playground, seconds: 3.1)
        for _ in 0..<3 { playground.game!.recordHit() }
        playground.throwBall(from: CGPoint(x: 500, y: 600), velocity: CGVector(dx: 0, dy: 300))
        #expect(playground.items.last?.kind == .greatBall)
    }

    @Test func landingBallsResetTheComboButBerriesDoNot() {
        var (playground, _) = started([regular])
        play(&playground, seconds: 3.1)
        for _ in 0..<2 { playground.game!.recordHit() }
        let berry = playground.throwBerry(from: CGPoint(x: 500, y: 120), velocity: .zero)
        #expect(berry)
        play(&playground, seconds: 0.5)
        #expect(playground.game?.combo == 2)
        playground.throwBall(from: CGPoint(x: 500, y: 120), velocity: .zero)
        play(&playground, seconds: 0.5)
        #expect(playground.game?.combo == 0)
    }

    @Test func berriesCalmWilds() {
        var (playground, _) = started([regular], pets: [])
        let landed = playUntil(&playground, seconds: 6) { p, _ in wild(p)?.body.isGrounded == true }
        #expect(landed.met)
        let target = wild(playground)!
        playground.throwBerry(from: CGPoint(x: target.body.position.x, y: target.body.position.y + 10), velocity: .zero)
        let events = play(&playground, seconds: 1.0 / 60)
        #expect(events.contains(.emotion(petID: target.id, .happy)))
        // Calm: it no longer runs from a cursor right next to it, and moves at most half speed.
        var top: CGFloat = 0
        for _ in 0..<60 {
            let p = playground.pet(target.id)!.body.position
            play(&playground, seconds: 1.0 / 60, cursor: CGPoint(x: p.x + 10, y: p.y + 10))
            top = max(top, abs(playground.pet(target.id)?.body.velocity.dx ?? 0))
        }
        #expect(top <= PetBrain.walkSpeed * 0.8 + 0.01)
    }

    @Test func shinySpawnsAreReported() {
        var (playground, _) = started([shinyable])
        playground.game!.shinyOdds = 1
        let result = playUntil(&playground, seconds: 5) { _, events in
            events.contains { if case .wildShiny = $0 { return true }; return false }
        }
        #expect(result.met)
    }

    @Test func catchesRecordShinyAndBonus() {
        var (playground, _) = started([shinyable], pets: [])
        playground.game!.shinyOdds = 1
        playground.game!.catchChance = 1
        playUntil(&playground, seconds: 6) { p, _ in wild(p)?.body.isGrounded == true }
        let target = wild(playground)!
        playground.throwBall(from: CGPoint(x: target.body.position.x, y: target.body.position.y + 10), velocity: .zero)
        playUntil(&playground, seconds: 4) { _, events in events.contains(.caught(petID: target.id)) }
        let record = playground.game?.catches.last
        #expect(record?.isShiny == true)
        #expect(record?.path == "0133/0000/0001")
        #expect(playground.game?.score == 50 + 200 + 50)  // shiny hit, shiny catch, first-throw bonus
    }

    @Test func flyingWildsGlideAndLeave() {
        var (playground, _) = started([flyer], pets: [])
        playUntil(&playground, seconds: 5) { p, _ in wild(p) != nil }
        let id = wild(playground)!.id
        for _ in 0..<(3 * 60) {
            play(&playground, seconds: 1.0 / 60)
            guard let bird = playground.pet(id) else { break }
            #expect(!bird.body.isGrounded)
            #expect(bird.body.position.y > TestWorld.floor.y + 100)
        }
        let index = playground.pets.firstIndex { $0.id == id }!
        playground.pets[index].lifetime = 0.05
        let gone = playUntil(&playground, seconds: 20) { _, events in events.contains(.wildRemoved(petID: id)) }
        #expect(gone.met)
    }

    @Test func flyingWildsCanBeHitAndFallAfterBreakingFree() {
        var (playground, _) = started([flyer], pets: [])
        playground.game!.catchChance = 0
        playUntil(&playground, seconds: 5) { p, _ in wild(p) != nil }
        let bird = wild(playground)!
        playground.throwBall(from: CGPoint(x: bird.body.position.x, y: bird.body.position.y + 10), velocity: .zero)
        let freed = playUntil(&playground, seconds: 5) { _, events in events.contains(.brokeFree(petID: bird.id)) }
        #expect(freed.met)
        let landed = playUntil(&playground, seconds: 3) { p, _ in p.pet(bird.id)?.body.isGrounded == true }
        #expect(landed.met)
    }

    @Test func wildsPreferWindowTops() {
        var brain = PetBrain(seed: 4, personality: .wild)
        var body = Body(position: CGPoint(x: 450, y: 50), surfaceID: -1)
        var reached = false
        for _ in 0..<(20 * 60) {
            brain.update(BrainContext(dt: 1.0 / 60, world: TestWorld.withShelf, cursor: farAway, cursorMode: .off,
                                      halfWidth: 10, animationFinished: true), body: &body)
            Physics.step(&body, dt: 1.0 / 60, world: TestWorld.withShelf)
            if body.surfaceID == 7 { reached = true; break }
        }
        #expect(reached)
    }
}
