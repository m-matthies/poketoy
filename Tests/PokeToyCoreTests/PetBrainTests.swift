import CoreGraphics
import Testing
@testable import PokeToyCore

@Suite struct PetBrainTests {
    let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                            visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))
    let floor = Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor)
    let shelf = Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)
    let far = CGPoint(x: -5000, y: -5000)
    let halfWidth: CGFloat = 20

    var floorOnly: World { World(screens: [screen], surfaces: [floor]) }
    var withShelf: World { World(screens: [screen], surfaces: [floor, shelf]) }

    func ctx(_ world: World, cursor: CGPoint? = nil, mode: CursorMode = .off, finished: Bool = false) -> BrainContext {
        BrainContext(dt: 1.0 / 60, world: world, cursor: cursor ?? far, cursorMode: mode,
                     halfWidth: halfWidth, animationFinished: finished)
    }

    /// Runs brain + physics like the app does. `check` sees every tick.
    func run(_ brain: inout PetBrain, _ body: inout Body, seconds: Double, _ context: BrainContext,
             check: (PetBrain, Body) -> Void = { _, _ in }) {
        for _ in 0..<Int(seconds * 60) {
            brain.update(context, body: &body)
            if brain.state != .dragged { Physics.step(&body, dt: 1.0 / 60, world: context.world) }
            check(brain, body)
        }
    }

    func grounded(x: CGFloat, on surface: Surface) -> Body {
        Body(position: CGPoint(x: x, y: surface.y), surfaceID: surface.id)
    }

    @Test func wandersWithinTheFloor() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500, on: floor)
        var walked = false
        run(&brain, &body, seconds: 40, ctx(floorOnly)) { brain, body in
            if body.velocity.dx != 0 { walked = true }
            #expect(body.position.x >= self.halfWidth - 3 && body.position.x <= 1000 - self.halfWidth + 3)
            #expect(body.isGrounded)
            if case .walk = brain.state { #expect(brain.pose.anim == .walk) }
        }
        #expect(walked)
    }

    @Test func fallsAsleepWhenLeftAloneAndWakesOnClick() {
        var brain = PetBrain(seed: 2)
        var body = grounded(x: 500, on: floor)
        run(&brain, &body, seconds: 90, ctx(floorOnly))
        #expect(brain.state == .sleep)
        #expect(brain.pose.anim == .sleep)
        brain.handle(.click, body: &body)
        #expect(brain.state == .react)
    }

    @Test func clickPlaysReactionWithHeartThenIdles() {
        var brain = PetBrain(seed: 3)
        var body = grounded(x: 500, on: floor)
        let before = brain.pose.token
        brain.handle(.click, body: &body)
        #expect(brain.state == .react)
        #expect(brain.pose.anim == .react)
        #expect(brain.pose.showHeart)
        #expect(brain.pose.token != before)
        brain.update(ctx(floorOnly), body: &body)
        #expect(brain.state == .react)
        brain.update(ctx(floorOnly, finished: true), body: &body)
        if case .idle = brain.state {} else { Issue.record("expected idle, got \(brain.state)") }
        #expect(!brain.pose.showHeart)
    }

    @Test func clickWhileAirborneIsIgnored() {
        var brain = PetBrain(seed: 3)
        var body = Body(position: CGPoint(x: 500, y: 400))
        brain.handle(.click, body: &body)
        #expect(brain.state != .react)
    }

    @Test func dragThenDropLandsHard() {
        var brain = PetBrain(seed: 4)
        var body = grounded(x: 500, on: floor)
        brain.handle(.dragBegan, body: &body)
        #expect(brain.state == .dragged)
        #expect(brain.pose.anim == .dangle)
        #expect(!body.isGrounded)
        body.position = CGPoint(x: 700, y: 500)
        run(&brain, &body, seconds: 0.5, ctx(floorOnly))
        #expect(body.position == CGPoint(x: 700, y: 500))  // physics paused while dragged
        brain.handle(.dragEnded(velocity: .zero), body: &body)
        run(&brain, &body, seconds: 1.5, ctx(floorOnly))
        #expect(body.isGrounded)
        #expect(brain.state == .landing)
        #expect(brain.pose.anim == .land)
        brain.update(ctx(floorOnly, finished: true), body: &body)
        if case .idle = brain.state {} else { Issue.record("expected idle, got \(brain.state)") }
    }

    @Test func walkingOffAnEdgeFallsAndSmallDropsLandSoftly() {
        let low = Surface(id: 9, minX: 300, maxX: 600, y: 120, kind: .window)
        let world = World(screens: [screen], surfaces: [floor, low])
        var brain = PetBrain(seed: 5)
        var body = Body(position: CGPoint(x: 610, y: 120))  // just stepped past the edge
        brain.update(ctx(world), body: &body)
        #expect(brain.state == .fall(startY: 120, thrown: false))
        #expect(brain.pose.anim == .walk)
        #expect(brain.pose.facing == .down)
        run(&brain, &body, seconds: 1, ctx(world))
        #expect(body.surfaceID == -1)
        #expect(brain.state != .landing)
    }

    @Test func bigFallsLandHard() {
        var brain = PetBrain(seed: 6)
        var body = Body(position: CGPoint(x: 610, y: 250))
        brain.update(ctx(withShelf), body: &body)
        run(&brain, &body, seconds: 1, ctx(withShelf))
        #expect(body.surfaceID == -1)
        #expect(brain.state == .landing)
    }

    @Test func followWalksTowardCursor() {
        var brain = PetBrain(seed: 7)
        var body = grounded(x: 500, on: floor)
        brain.update(ctx(floorOnly, cursor: CGPoint(x: 900, y: 60), mode: .follow), body: &body)
        #expect(body.velocity.dx > 0)
        #expect(brain.pose.facing == .right)
        run(&brain, &body, seconds: 6, ctx(floorOnly, cursor: CGPoint(x: 900, y: 60), mode: .follow))
        #expect(abs(body.position.x - 900) <= 31)
    }

    @Test func followJumpsUpToCursor() {
        var brain = PetBrain(seed: 8)
        var body = grounded(x: 450, on: floor)
        let context = ctx(withShelf, cursor: CGPoint(x: 450, y: 300), mode: .follow)
        brain.update(context, body: &body)
        #expect(brain.state == .jump)
        #expect(body.velocity.dy > 0)
        run(&brain, &body, seconds: 1.5, context)
        #expect(body.surfaceID == 7)
    }

    @Test func followNeverSleeps() {
        var brain = PetBrain(seed: 9)
        var body = grounded(x: 500, on: floor)
        run(&brain, &body, seconds: 90, ctx(floorOnly, cursor: CGPoint(x: 500, y: 60), mode: .follow)) { brain, _ in
            #expect(brain.state != .sleep)
        }
    }

    @Test func fleeRunsAwayFast() {
        var brain = PetBrain(seed: 10)
        var body = grounded(x: 500, on: floor)
        brain.update(ctx(floorOnly, cursor: CGPoint(x: 480, y: 60), mode: .flee), body: &body)
        #expect(body.velocity.dx > PetBrain.walkSpeed)
    }

    @Test func corneredFleeJumpsToEscape() {
        var brain = PetBrain(seed: 11)
        var body = grounded(x: halfWidth, on: floor)
        brain.update(ctx(withShelf, cursor: CGPoint(x: halfWidth + 30, y: 60), mode: .flee), body: &body)
        #expect(brain.state == .jump)
    }

    @Test func switchingCursorModeWakesSleeper() {
        var brain = PetBrain(seed: 2)
        var body = grounded(x: 500, on: floor)
        run(&brain, &body, seconds: 90, ctx(floorOnly))
        #expect(brain.state == .sleep)
        brain.update(ctx(floorOnly, mode: .flee), body: &body)
        #expect(brain.state != .sleep)
    }

    @Test func seededBrainsAreDeterministic() {
        var a = PetBrain(seed: 42), b = PetBrain(seed: 42)
        var bodyA = grounded(x: 500, on: floor), bodyB = grounded(x: 500, on: floor)
        run(&a, &bodyA, seconds: 20, ctx(withShelf))
        run(&b, &bodyB, seconds: 20, ctx(withShelf))
        #expect(bodyA.position == bodyB.position)
        #expect(a.state == b.state)
    }
}
