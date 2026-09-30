import CoreGraphics
import Testing
@testable import PokeToyCore

@Suite struct BallAnimationTests {
    @Test func returningShrinksThePetIntoTheBall() {
        let start = BallAnimation.frame(.recall, at: 0)
        #expect(start.petScale == 1 && start.tint == 0 && start.toBall == 0)
        let middle = BallAnimation.frame(.recall, at: 0.4)
        #expect(middle.petScale > 0 && middle.petScale < 1)
        #expect(middle.tint > 0 && middle.tintIsRed)
        #expect(middle.toBall > 0)
        let wobbling = BallAnimation.frame(.recall, at: 0.7)
        #expect(wobbling.petScale == 0)
        #expect(abs(wobbling.ballAngle) > 0)
        let end = BallAnimation.frame(.recall, at: BallAnimation.duration(.recall))
        #expect(end.ballAlpha == 0 && end.petScale == 0)
    }

    @Test func lettingOutGrowsThePetFromTheBall() {
        let start = BallAnimation.frame(.release, at: 0)
        #expect(start.petScale == 0)
        #expect(start.ballDrop > 0)  // falling in from above
        let landed = BallAnimation.frame(.release, at: 0.35)
        #expect(landed.ballDrop == 0)
        #expect(landed.burst > 0)
        let growing = BallAnimation.frame(.release, at: 0.55)
        #expect(growing.petScale > 0 && growing.petScale < 1)
        #expect(growing.tint > 0 && !growing.tintIsRed)  // glowing white
        let end = BallAnimation.frame(.release, at: BallAnimation.duration(.release))
        #expect(end.petScale == 1 && end.tint == 0 && end.ballAlpha == 0)
    }

    @Test func framesStayInRangeThroughout() {
        for kind in [BallAnimation.Kind.recall, .release] {
            for step in 0...100 {
                let f = BallAnimation.frame(kind, at: BallAnimation.duration(kind) * Double(step) / 100)
                #expect((0...1).contains(f.petScale) && (0...1).contains(f.tint) && (0...1).contains(f.ballAlpha))
                #expect((0...1).contains(f.toBall) && (0...1).contains(f.burst) && f.ballDrop >= 0)
            }
        }
    }
}
