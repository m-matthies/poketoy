import CoreGraphics
import Testing
@testable import PokeToyCore

@Suite struct PetBrainScriptTests {
    let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                            visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))
    let floor = Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor)
    let shelf = Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)
    var world: World { World(screens: [screen], surfaces: [floor, shelf]) }
    var floorOnly: World { World(screens: [screen], surfaces: [floor]) }

    func ctx(_ world: World? = nil, finished: Bool = false, cursor: CGPoint = CGPoint(x: -5000, y: -5000),
             mode: CursorMode = .off) -> BrainContext {
        BrainContext(dt: 1.0 / 60, world: world ?? self.world, cursor: cursor, cursorMode: mode, halfWidth: 20,
                     animationFinished: finished)
    }

    func tick(_ brain: inout PetBrain, _ body: inout Body, _ context: BrainContext) {
        brain.update(context, body: &body)
        if brain.state != .dragged { Physics.step(&body, dt: 1.0 / 60, world: context.world) }
    }

    func run(_ brain: inout PetBrain, _ body: inout Body, seconds: Double, _ context: BrainContext) {
        for _ in 0..<Int((seconds * 60).rounded()) { tick(&brain, &body, context) }
    }

    func grounded(x: CGFloat) -> Body {
        Body(position: CGPoint(x: x, y: 50), surfaceID: -1)
    }

    func isIdle(_ brain: PetBrain) -> Bool {
        if case .idle = brain.state { return true }
        return false
    }

    @Test func performStartsAScriptWhenFree() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        let token = brain.pose.token
        let ok1 = brain.perform(Script(anim: .greet, facing: .left, hearts: 2, end: .animationFinished, priority: 2), body: &body)
        #expect(ok1)
        #expect(brain.script?.anim == .greet)
        #expect(brain.pose == Pose(anim: .greet, facing: .left, hearts: 2, token: token + 1))
        #expect(!brain.isFree)
    }

    @Test func performIsRejectedWhileBusyOrAirborne() {
        var dragged = PetBrain(seed: 1)
        var body = grounded(x: 500)
        dragged.handle(.dragBegan, body: &body)
        let ok2 = dragged.perform(Script(anim: .greet, end: .animationFinished, priority: 9), body: &body)
        #expect(!ok2)

        var airborneBrain = PetBrain(seed: 2)
        var airborne = Body(position: CGPoint(x: 500, y: 400))
        let ok3 = airborneBrain.perform(Script(anim: .greet, end: .animationFinished, priority: 1), body: &airborne)
        #expect(!ok3)

        var reacting = PetBrain(seed: 3)
        var body2 = grounded(x: 500)
        reacting.handle(.click, body: &body2)
        let ok4 = reacting.perform(Script(anim: .greet, end: .animationFinished, priority: 1), body: &body2)
        #expect(!ok4)
    }

    @Test func higherPriorityReplacesLower() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        let ok5 = brain.perform(Script(anim: .walk, moveTo: 900, end: .arrived, priority: 1), body: &body)
        #expect(ok5)
        let ok6 = brain.perform(Script(anim: .sad, end: .animationFinished, priority: 1), body: &body)
        #expect(!ok6)
        let ok7 = brain.perform(Script(anim: .sad, end: .animationFinished, priority: 2), body: &body)
        #expect(ok7)
        #expect(brain.script?.anim == .sad)
    }

    @Test func animationFinishedEndsTheScript() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .greet, hearts: 1, end: .animationFinished, priority: 2), body: &body)
        tick(&brain, &body, ctx())
        #expect(brain.script != nil)
        tick(&brain, &body, ctx(finished: true))
        #expect(isIdle(brain))
        #expect(brain.pose.hearts == 0)
    }

    @Test func timedScriptEnds() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .eat, end: .after(1), priority: 2), body: &body)
        run(&brain, &body, seconds: 0.9, ctx())
        #expect(brain.script?.anim == .eat)
        run(&brain, &body, seconds: 0.2, ctx())
        #expect(isIdle(brain))
    }

    @Test func movingScriptWalksAndArrives() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .walk, moveTo: 600, end: .arrived, priority: 1), body: &body)
        tick(&brain, &body, ctx())
        #expect(body.velocity.dx > 0)
        #expect(brain.pose.anim == .walk)
        #expect(brain.pose.facing == .right)
        run(&brain, &body, seconds: 2, ctx())
        #expect(abs(body.position.x - 600) <= 2)
        #expect(isIdle(brain) || brain.isFree)
    }

    @Test func nonWalkScriptKeepsItsFacing() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .sad, facing: .left, moveTo: 530, speed: 90, end: .after(2), priority: 2), body: &body)
        tick(&brain, &body, ctx())
        #expect(body.velocity.dx == 90)
        #expect(brain.pose.anim == .sad)
        #expect(brain.pose.facing == .left)
    }

    @Test func thenSleepFallsAsleepOnArrival() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .walk, moveTo: 520, end: .arrived, priority: 2, then: .sleep), body: &body)
        run(&brain, &body, seconds: 1, ctx())
        #expect(brain.isSleeping)
        #expect(brain.pose.anim == .sleep)
    }

    @Test func thenScriptChains() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        let thanks = Script(anim: .greet, hearts: 1, end: .animationFinished, priority: 2)
        brain.perform(Script(anim: .eat, end: .after(0.5), priority: 2, then: .script(thanks)), body: &body)
        run(&brain, &body, seconds: 0.6, ctx())
        #expect(brain.pose.anim == .greet)
        #expect(brain.pose.hearts == 1)
    }

    @Test func clickInterruptsAScript() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .sit, end: .after(100), priority: 3), body: &body)
        brain.handle(.click, body: &body)
        #expect(brain.state == .react)
    }

    @Test func updateScriptTargetRedirects() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .walk, moveTo: 900, end: .arrived, priority: 1), body: &body)
        brain.updateScriptTarget(100)
        tick(&brain, &body, ctx())
        #expect(body.velocity.dx < 0)
        #expect(brain.script?.moveTo == 100)
    }

    @Test func endScriptReturnsToIdle() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .sit, end: .after(100), priority: 3), body: &body)
        brain.endScript(body: &body)
        #expect(isIdle(brain))
    }

    @Test func knockedLaunchesAndLandsHard() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.handle(.knocked(velocity: CGVector(dx: 220, dy: 380)), body: &body)
        #expect(brain.state == .fall(startY: 50, thrown: true))
        #expect(brain.pose.anim == .dangle)
        #expect(!body.isGrounded)
        #expect(body.velocity == CGVector(dx: 220, dy: 380))
        run(&brain, &body, seconds: 1.5, ctx(floorOnly))
        #expect(brain.state == .landing)
    }

    @Test func knockedIsIgnoredWhileDragged() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.handle(.dragBegan, body: &body)
        brain.handle(.knocked(velocity: CGVector(dx: 220, dy: 380)), body: &body)
        #expect(brain.state == .dragged)
    }

    @Test func wildFleesWithoutACursorModeAndFaster() {
        var brain = PetBrain(seed: 4, personality: .wild)
        var body = grounded(x: 500)
        brain.update(ctx(floorOnly, cursor: CGPoint(x: 480, y: 60), mode: .off), body: &body)
        #expect(body.velocity.dx >= PetBrain.walkSpeed * 1.6 * 1.8 - 0.001)
    }

    @Test func wildNeverSleeps() {
        var brain = PetBrain(seed: 5, personality: .wild)
        var body = grounded(x: 500)
        for _ in 0..<(120 * 60) {
            tick(&brain, &body, ctx(floorOnly))
            #expect(brain.state != .sleep)
        }
    }

    @Test func sleepingPetWakesUpOnItsOwn() {
        var brain = PetBrain(seed: 6)
        var body = grounded(x: 500)
        let ok8 = brain.fallAsleep(body: &body)
        #expect(ok8)
        var woke = false
        for _ in 0..<(121 * 60) {
            tick(&brain, &body, ctx(floorOnly))
            if brain.state == .waking { woke = true; break }
        }
        #expect(woke)
        #expect(brain.pose.anim == .wake)
        tick(&brain, &body, ctx(floorOnly, finished: true))
        #expect(isIdle(brain))
        // Waking resets the interaction timer: it stays awake for at least half a minute.
        for _ in 0..<(30 * 60) {
            tick(&brain, &body, ctx(floorOnly))
            #expect(brain.state != .sleep)
        }
    }

    @Test func fallAsleepOnlyWhenFreeAndGrounded() {
        var brain = PetBrain(seed: 1)
        var airborne = Body(position: CGPoint(x: 500, y: 400))
        let ok9 = brain.fallAsleep(body: &airborne)
        #expect(!ok9)
        var busy = PetBrain(seed: 2)
        var body = grounded(x: 500)
        busy.perform(Script(anim: .sit, end: .after(10), priority: 3), body: &body)
        let ok10 = busy.fallAsleep(body: &body)
        #expect(!ok10)
    }

    @Test func publicJumpLandsOnTheTarget() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 450)
        let ok11 = brain.jump(to: shelf, x: 450, halfWidth: 20, body: &body)
        #expect(ok11)
        #expect(brain.state == .jump)
        run(&brain, &body, seconds: 1.5, ctx())
        #expect(body.surfaceID == 7)
    }
}
