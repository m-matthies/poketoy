import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct HoldStillTests {
    let cursor = CGPoint(x: 900, y: 60)

    @Test func aHeldPetStaysPutWhateverGoesOn() {
        var (playground, ids) = makePlayground([200])
        playground.hold(ids[0])
        playground.seekAttention(ids[0])  // would run to the cursor
        playground.dropTreat(.apple, at: CGPoint(x: 600, y: 300))  // would run to the treat
        let start = playground.pet(ids[0])!.body.position.x
        play(&playground, seconds: 8, cursor: cursor, mode: .follow)
        #expect(abs(playground.pet(ids[0])!.body.position.x - start) < 2)
    }

    @Test func lettingGoLetsItMoveAgain() {
        var (playground, ids) = makePlayground([200])
        playground.hold(ids[0])
        play(&playground, seconds: 1, cursor: cursor, mode: .follow)
        playground.letGo(ids[0])
        let start = playground.pet(ids[0])!.body.position.x
        play(&playground, seconds: 4, cursor: cursor, mode: .follow)
        #expect(playground.pet(ids[0])!.body.position.x - start > 50)
    }

    @Test func aPetInMidAirHoldsOnceItLands() {
        var (playground, ids) = makePlayground([200])
        playground.movePet(ids[0], to: CGPoint(x: 200, y: 400))  // up in the air
        playground.hold(ids[0])
        play(&playground, seconds: 2)  // falls and lands
        let landed = playground.pet(ids[0])!.body.position.x
        play(&playground, seconds: 6, cursor: cursor, mode: .follow)
        #expect(abs(playground.pet(ids[0])!.body.position.x - landed) < 2)
    }

    @Test func aSleepingPetSleepsOn() {
        var (playground, ids) = makePlayground([200])
        _ = playground.pets[0].fallAsleep(indefinitely: true)
        playground.hold(ids[0])
        play(&playground, seconds: 2)
        #expect(playground.pet(ids[0])!.brain.isSleeping)
    }
}
