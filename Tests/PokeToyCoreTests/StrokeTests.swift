import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct StrokeTests {
    /// Moves the cursor over pet `id` through `xs`, one tick per position.
    func stroke(_ playground: inout Playground, _ id: UUID, _ xs: [CGFloat]) -> [PlaygroundEvent] {
        var events: [PlaygroundEvent] = []
        for x in xs {
            playground.stroke(pet: id, cursorX: x)
            events += play(&playground, seconds: 1.0 / 60)
        }
        return events
    }

    func happy(_ events: [PlaygroundEvent], _ id: UUID) -> Bool {
        events.contains(.emotion(petID: id, .happy))
    }

    /// Back and forth over the pet: 500 → 520 → 500 → 520 → 500, a few pixels per tick.
    var rubbing: [CGFloat] {
        let right = stride(from: 500, through: 520, by: 4).map { CGFloat($0) }
        let left = Array(right.reversed())
        return right + left + right + left
    }

    @Test func threeReversalsStroke() {
        var (playground, ids) = makePlayground([510])
        let events = stroke(&playground, ids[0], rubbing)
        #expect(happy(events, ids[0]))
        #expect(playground.pet(ids[0])?.pose.anim == .greet)
        #expect(playground.pet(ids[0])?.pose.hearts == 2)
    }

    @Test func smallWigglesDoNotCount() {
        var (playground, ids) = makePlayground([510])
        let wiggle: [CGFloat] = Array(repeating: [500, 503, 500, 503], count: 6).flatMap { $0 }
        #expect(!happy(stroke(&playground, ids[0], wiggle), ids[0]))
    }

    @Test func slowStrokesDoNotCount() {
        var (playground, ids) = makePlayground([510])
        var events: [PlaygroundEvent] = []
        for x in rubbing {
            playground.stroke(pet: ids[0], cursorX: x)
            events += play(&playground, seconds: 0.15)  // far too slow: > 1.5 s for three reversals
        }
        #expect(!happy(events, ids[0]))
    }

    @Test func strokingASleeperKeepsItAsleep() {
        var (playground, ids) = makePlayground([510])
        let asleep = playground.pets[0].fallAsleep()
        #expect(asleep)
        let events = stroke(&playground, ids[0], rubbing)
        #expect(happy(events, ids[0]))
        #expect(playground.pet(ids[0])?.brain.isSleeping == true)
        #expect(playground.pet(ids[0])?.pose.hearts == 2)
    }

    @Test func strokeCooldown() {
        var (playground, ids) = makePlayground([510])
        let first = stroke(&playground, ids[0], rubbing)
        let second = stroke(&playground, ids[0], rubbing)
        #expect(happy(first, ids[0]))
        #expect(!happy(second, ids[0]))
    }

    @Test func pressedMouseIsNotStroking() {
        var (playground, ids) = makePlayground([510])
        playground.handle(.pressed, pet: ids[0])
        #expect(!happy(stroke(&playground, ids[0], rubbing), ids[0]))
        playground.handle(.dragBegan, pet: ids[0])
        #expect(!happy(stroke(&playground, ids[0], rubbing), ids[0]))
    }

    @Test func fiveQuickClicksAnnoy() {
        var (playground, ids) = makePlayground([510])
        var events: [PlaygroundEvent] = []
        for _ in 0..<5 {
            playground.handle(.click, pet: ids[0])
            events += play(&playground, seconds: 0.2)
        }
        #expect(events.contains(.emotion(petID: ids[0], .angry)))
        #expect(playground.pet(ids[0])?.brain.script?.anim == .shoot || playground.pet(ids[0])?.brain.script?.anim == .walk)
        // Then it storms off, away from the cursor (which was left of it in these tests: far away at -5000).
        play(&playground, seconds: 4)
        #expect((playground.pet(ids[0])?.body.position.x ?? 0) > 600)
    }

    @Test func clicksWhileAnnoyedAreIgnored() {
        var (playground, ids) = makePlayground([510])
        for _ in 0..<5 {
            playground.handle(.click, pet: ids[0])
            play(&playground, seconds: 0.1)
        }
        playground.handle(.click, pet: ids[0])
        #expect(playground.pet(ids[0])?.brain.state != .react)
    }

    @Test func slowClicksDoNotAnnoy() {
        var (playground, ids) = makePlayground([510])
        var events: [PlaygroundEvent] = []
        for _ in 0..<5 {
            playground.handle(.click, pet: ids[0])
            events += play(&playground, seconds: 1.2)
        }
        #expect(!events.contains(.emotion(petID: ids[0], .angry)))
    }
}
