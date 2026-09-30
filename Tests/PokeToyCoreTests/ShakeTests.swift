import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct ShakeTests {
    /// A world with window 7's top at y 250 and its left edge at `origin`.
    func world(windowAt origin: CGFloat) -> World {
        World(screens: [TestWorld.screen],
              surfaces: [TestWorld.floor, Surface(id: 7, minX: origin, maxX: origin + 300, y: 250, kind: .window)],
              windowOrigins: [7: origin])
    }

    /// A pet standing on window 7 (left edge at 300).
    func petOnWindow() -> (Playground, UUID) {
        var playground = Playground(seed: 1, scale: 1)
        playground.mouseDown = true  // the user is dragging the window
        let id = playground.addPet(metrics: .uniform(), at: CGPoint(x: 450, y: 251))
        play(&playground, seconds: 0.1, world: world(windowAt: 300))
        return (playground, id)
    }

    @discardableResult
    /// Moves the window through `origins`, holding each for `hold` seconds (the monitor refreshes at 5 Hz).
    func move(_ playground: inout Playground, through origins: [CGFloat], hold: Double = 0.2) -> [PlaygroundEvent] {
        var events: [PlaygroundEvent] = []
        for origin in origins { events += play(&playground, seconds: hold, world: world(windowAt: origin)) }
        return events
    }

    func knockedOff(_ playground: Playground, _ id: UUID) -> Bool {
        if case .fall(_, true) = playground.pet(id)?.brain.state { return true }
        return playground.pet(id)?.body.surfaceID == -1
    }

    @Test func shakingAWindowThrowsPetsOff() {
        var (playground, id) = petOnWindow()
        let events = move(&playground, through: [360, 300, 360, 300])
        #expect(knockedOff(playground, id))
        #expect(events.contains(.emotion(petID: id, .surprised)))
    }

    @Test func aVeryFastMoveThrowsPetsOff() {
        var (playground, id) = petOnWindow()
        move(&playground, through: [700], hold: 0.2)  // 400 pt in one 0.2 s step = 2,000 pt/s
        #expect(knockedOff(playground, id))
    }

    @Test func slowDragKeepsPetsOn() {
        var (playground, id) = petOnWindow()
        // A normal drag: steady 40 pt steps at 5 Hz (200 pt/s), then back the other way once.
        let there = stride(from: 340, through: 540, by: 40).map { CGFloat($0) }
        let back = Array(there.reversed().dropFirst())
        let events = move(&playground, through: there + back)
        #expect(playground.pet(id)?.body.surfaceID == 7)
        #expect(!events.contains(.emotion(petID: id, .surprised)))
    }

    @Test func surfersFaceTheMoveDirection() {
        var (playground, id) = petOnWindow()
        move(&playground, through: [340, 380])
        #expect(playground.pet(id)?.body.surfaceID == 7)
        #expect(playground.pet(id)?.pose.facing == .right)
    }

    @Test func aNudgeAfterRestingIsNotAShake() {
        var (playground, id) = petOnWindow()
        move(&playground, through: [360])
        move(&playground, through: [360], hold: 5)  // rest
        let events = move(&playground, through: [325, 360])  // nudge left, then right
        #expect(playground.pet(id)?.body.surfaceID == 7)
        #expect(!events.contains(.emotion(petID: id, .surprised)))
    }

    @Test func petsShakenOffTogetherDoNotKnockEachOtherOver() {
        for gap in [10, 18, 25] as [CGFloat] {
            var playground = Playground(seed: 1, scale: 1)
            playground.mouseDown = true
            let a = playground.addPet(metrics: .uniform(), at: CGPoint(x: 450, y: 251))
            let b = playground.addPet(metrics: .uniform(), at: CGPoint(x: 450 + gap, y: 251))
            play(&playground, seconds: 0.1, world: world(windowAt: 300))
            var events = move(&playground, through: [360, 300, 360, 300])
            events += play(&playground, seconds: 2, world: world(windowAt: 300))
            #expect(!events.contains(.emotion(petID: a, .pain)) && !events.contains(.emotion(petID: b, .pain)))
            #expect(playground.pet(a)?.body.surfaceID != 7 && playground.pet(b)?.body.surfaceID != 7)
        }
    }

    @Test func windowsMovedWithoutTheMouseDoNotShake() {
        var (playground, id) = petOnWindow()
        playground.mouseDown = false  // e.g. tiling or zoom animations
        let events = move(&playground, through: [700, 300, 700, 300])
        #expect(playground.pet(id)?.body.surfaceID == 7)
        #expect(!events.contains(.emotion(petID: id, .surprised)))
    }

    @Test func speedIsMeasuredOnTheWallClock() {
        var (playground, id) = petOnWindow()
        // The app stalled: the window moved 225 pt over half a second of real time, but only one tick passed.
        var stalled = world(windowAt: 525)
        stalled.timestamp = 10.5
        var before = world(windowAt: 300)
        before.timestamp = 10.0
        play(&playground, seconds: 1.0 / 60, world: before)
        let events = play(&playground, seconds: 1.0 / 60, world: stalled)
        #expect(!events.contains(.emotion(petID: id, .surprised)))
    }
}
