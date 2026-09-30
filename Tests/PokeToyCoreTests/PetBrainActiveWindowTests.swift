import CoreGraphics
import Testing
@testable import PokeToyCore

@Suite struct PetBrainActiveWindowTests {
    let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                            visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))
    let floor = Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor)

    /// Runs brain + physics; returns true as soon as `until` holds.
    @discardableResult
    func run(_ brain: inout PetBrain, _ body: inout Body, seconds: Double, world: World,
             until: (Body) -> Bool = { _ in false }, each: (Body) -> Void = { _ in }) -> Bool {
        for _ in 0..<Int(seconds * 60) {
            let context = BrainContext(dt: 1.0 / 60, world: world, cursor: CGPoint(x: -5000, y: -5000),
                                       cursorMode: .off, halfWidth: 20, animationFinished: true)
            brain.update(context, body: &body)
            Physics.step(&body, dt: 1.0 / 60, world: world)
            each(body)
            if until(body) { return true }
        }
        return false
    }

    @Test func jumpsOntoTheActiveWindow() {
        let active = Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)
        let other = Surface(id: 8, minX: 650, maxX: 950, y: 250, kind: .window)
        let world = World(screens: [screen], surfaces: [floor, active, other], activeWindowID: 7)
        var brain = PetBrain(seed: 1)
        var body = Body(position: CGPoint(x: 100, y: 50), surfaceID: -1)
        #expect(run(&brain, &body, seconds: 60, world: world, until: { $0.surfaceID == 7 }))
    }

    @Test func walksUnderAnActiveWindowThatIsOutOfReach() {
        let active = Surface(id: 9, minX: 700, maxX: 950, y: 300, kind: .window)
        let world = World(screens: [screen], surfaces: [floor, active], activeWindowID: 9)
        var brain = PetBrain(seed: 2)
        var body = Body(position: CGPoint(x: 50, y: 50), surfaceID: -1)
        #expect(run(&brain, &body, seconds: 60, world: world, until: { $0.surfaceID == 9 }))
    }

    @Test func dropsDownToALowerActiveWindow() {
        let high = Surface(id: 9, minX: 300, maxX: 600, y: 500, kind: .window)
        let active = Surface(id: 7, minX: 100, maxX: 900, y: 250, kind: .window)
        let world = World(screens: [screen], surfaces: [floor, active, high], activeWindowID: 7)
        var brain = PetBrain(seed: 3)
        var body = Body(position: CGPoint(x: 450, y: 500), surfaceID: 9)
        #expect(run(&brain, &body, seconds: 60, world: world, until: { $0.surfaceID == 7 }))
    }

    @Test func staysOnTheActiveWindow() {
        let active = Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)
        let other = Surface(id: 8, minX: 650, maxX: 950, y: 250, kind: .window)
        let world = World(screens: [screen], surfaces: [floor, active, other], activeWindowID: 7)
        var brain = PetBrain(seed: 4)
        var body = Body(position: CGPoint(x: 450, y: 250), surfaceID: 7)
        var leftIt = false
        run(&brain, &body, seconds: 120, world: world, each: { body in
            if body.isGrounded && body.surfaceID != 7 { leftIt = true }
        })
        #expect(!leftIt)
    }

    @Test func withoutAnActiveWindowPetsStillWanderOff() {
        let window = Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)
        let world = World(screens: [screen], surfaces: [floor, window])
        var brain = PetBrain(seed: 5)
        var body = Body(position: CGPoint(x: 450, y: 250), surfaceID: 7)
        #expect(run(&brain, &body, seconds: 180, world: world, until: { $0.surfaceID == -1 }))
    }

    @Test func jumpsUpToAnActiveWindowOfAnyHeight() {
        let active = Surface(id: 7, minX: 300, maxX: 600, y: 700, kind: .window)  // 650 pt up: beyond a normal jump
        let world = World(screens: [screen], surfaces: [floor, active], activeWindowID: 7)
        var brain = PetBrain(seed: 6)
        var body = Body(position: CGPoint(x: 100, y: 50), surfaceID: -1)
        #expect(run(&brain, &body, seconds: 60, world: world, until: { $0.surfaceID == 7 }))
    }
}
