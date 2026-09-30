import Testing
@testable import PokeToyCore

@Suite struct AnimatorTests {
    @Test func advancesAndLoops() {
        var animator = Animator()
        animator.play(.walk)
        animator.advance(dt: 2.5 / 60, durations: [2, 4])
        #expect(animator.frameIndex == 1)
        animator.advance(dt: 4.0 / 60, durations: [2, 4])
        #expect(animator.frameIndex == 0)
        #expect(!animator.finished)
    }

    @Test func nonLoopingAnimationFinishesOnLastFrame() {
        var animator = Animator()
        animator.play(.react)
        animator.advance(dt: 7.0 / 60, durations: [2, 4])
        #expect(animator.finished)
        #expect(animator.frameIndex == 1)
        animator.advance(dt: 1, durations: [2, 4])
        #expect(animator.frameIndex == 1)
    }

    @Test func playingSameKindKeepsProgressButNewKindResets() {
        var animator = Animator()
        animator.play(.walk)
        animator.advance(dt: 2.5 / 60, durations: [2, 4])
        animator.play(.walk)
        #expect(animator.frameIndex == 1)
        animator.play(.idle)
        #expect(animator.frameIndex == 0)
        #expect(animator.kind == .idle)
    }

    @Test func restartResetsFinishedAnimation() {
        var animator = Animator()
        animator.play(.land)
        animator.advance(dt: 1, durations: [1])
        #expect(animator.finished)
        animator.restart()
        #expect(!animator.finished)
        #expect(animator.frameIndex == 0)
    }

    @Test func zeroDurationsDoNotHang() {
        var animator = Animator()
        animator.play(.walk)
        animator.advance(dt: 1, durations: [0, 0])
        animator.advance(dt: 1, durations: [])
        #expect(animator.frameIndex >= 0)
    }
}
