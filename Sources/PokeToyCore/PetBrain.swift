import CoreGraphics

public enum CursorMode: String, Codable, CaseIterable, Sendable {
    case off, follow, flee
}

public enum PetEvent: Equatable, Sendable {
    /// Mouse went down on the pet (before it is known to be a click or a drag).
    case pressed
    /// The press ended without a click or drag (e.g. the mouse-up was never delivered).
    case released
    case click
    case dragBegan
    case dragEnded(velocity: CGVector)
    /// Hit by a thrown pet: launched with `velocity`, lands hard.
    case knocked(velocity: CGVector)
}

/// `.pet` is one of the user's pets; `.wild` is a catch-game Pokémon (faster, skittish, never sleeps).
public enum Personality: Equatable, Sendable {
    case pet, wild
}

public struct Pose: Equatable, Sendable {
    public var anim: PetAnim
    public var facing: Direction
    /// Hearts shown above the pet (0–2).
    public var hearts: Int
    /// Changes whenever the animation should restart from its first frame.
    public var token: Int

    public var showHeart: Bool { hearts > 0 }
}

/// A short directed action. `Playground` uses scripts for social moments, feeding and the catch game.
public struct Script: Equatable, Sendable {
    public enum End: Equatable, Sendable {
        case animationFinished
        case after(Double)
        /// Reached `moveTo` (immediately if there is none).
        case arrived
    }

    /// What the pet does when the script ends.
    public indirect enum Then: Equatable, Sendable {
        case idle
        case sleep
        case script(Script)
    }

    public var anim: PetAnim
    public var facing: Direction
    public var hearts: Int
    public var moveTo: CGFloat?
    public var speed: CGFloat
    public var end: End
    public var priority: Int
    public var then: Then

    public init(anim: PetAnim, facing: Direction = .down, hearts: Int = 0, moveTo: CGFloat? = nil,
                speed: CGFloat = PetBrain.walkSpeed, end: End, priority: Int, then: Then = .idle) {
        self.anim = anim
        self.facing = facing
        self.hearts = hearts
        self.moveTo = moveTo
        self.speed = speed
        self.end = end
        self.priority = priority
        self.then = then
    }
}

public struct BrainContext: Sendable {
    public var dt: Double
    public var world: World
    public var cursor: CGPoint
    public var cursorMode: CursorMode
    /// Half the pet's on-screen width, used to keep it on surfaces.
    public var halfWidth: CGFloat
    /// The current pose's non-looping animation has played to the end.
    public var animationFinished: Bool

    public init(dt: Double, world: World, cursor: CGPoint, cursorMode: CursorMode, halfWidth: CGFloat,
                animationFinished: Bool) {
        self.dt = dt
        self.world = world
        self.cursor = cursor
        self.cursorMode = cursorMode
        self.halfWidth = halfWidth
        self.animationFinished = animationFinished
    }
}

/// Decides what a pet does each tick. Movement is expressed through `Body.velocity`; `Physics` moves it.
public struct PetBrain: Sendable {
    public enum State: Equatable, Sendable {
        case idle(remaining: Double)
        case walk(targetX: CGFloat, speed: CGFloat)
        case sleep
        case waking
        case jump
        case fall(startY: CGFloat, thrown: Bool)
        case dragged
        case react
        case landing
        case held
        case scripted(Script, elapsed: Double)
    }

    public static let walkSpeed: CGFloat = 70
    public static let sleepAfter: Double = 60
    public static let napLength: ClosedRange<Double> = 30...120
    public static let fleeRadius: CGFloat = 150
    public static let wildFleeRadius: CGFloat = 220
    public static let hardLandingDrop: CGFloat = 150
    public static let maxJumpRise: CGFloat = 320
    public static let maxJumpReach: CGFloat = 360
    /// Chance that a wandering pet heads for the active window instead of a random spot.
    public static let activeWindowPreference = 0.6

    public let personality: Personality
    public private(set) var state: State = .idle(remaining: 1)
    public private(set) var pose = Pose(anim: .idle, facing: .down, hearts: 0, token: 0)
    private var rng: SplitMix64
    private var sinceInteraction: Double = 0
    private var napRemaining: Double = 0

    public init(seed: UInt64, personality: Personality = .pet) {
        rng = SplitMix64(seed: seed)
        self.personality = personality
    }

    /// Idle or wandering, so free to be directed.
    public var isFree: Bool {
        switch state {
        case .idle, .walk: return true
        default: return false
        }
    }

    public var isSleeping: Bool { state == .sleep }

    public var script: Script? {
        if case .scripted(let script, _) = state { return script }
        return nil
    }

    private var speedFactor: CGFloat { personality == .wild ? 1.6 : 1 }

    // MARK: - Events

    public mutating func handle(_ event: PetEvent, body: inout Body) {
        sinceInteraction = 0
        switch event {
        case .pressed:
            guard state != .dragged else { return }
            body.velocity.dx = 0
            state = .held
        case .released:
            guard state == .held else { return }
            if body.isGrounded { enterIdle(&body) } else { state = .fall(startY: body.position.y, thrown: false) }
        case .click:
            guard state != .dragged else { return }
            guard body.isGrounded else {
                if state == .held { state = .fall(startY: body.position.y, thrown: false) }
                return
            }
            body.velocity.dx = 0
            state = .react
            setPose(.react, .down, hearts: 1, restart: true)
        case .dragBegan:
            state = .dragged
            body.surfaceID = nil
            body.velocity = .zero
            setPose(.dangle, .down, restart: true)
        case .dragEnded(let velocity):
            state = .fall(startY: body.position.y, thrown: true)
            body.velocity = velocity
        case .knocked(let velocity):
            guard state != .dragged, state != .held else { return }
            state = .fall(startY: body.position.y, thrown: true)
            body.surfaceID = nil
            body.velocity = velocity
            setPose(.dangle, .down, restart: true)
        }
    }

    // MARK: - Directed actions

    /// Starts `script` if the pet is grounded and free, asleep, or running a lower-priority script.
    @discardableResult
    public mutating func perform(_ script: Script, body: inout Body) -> Bool {
        guard body.isGrounded else { return false }
        switch state {
        case .idle, .walk, .sleep:
            break
        case .scripted(let current, _) where script.priority > current.priority:
            break
        default:
            return false
        }
        start(script, &body)
        return true
    }

    /// Changes where the running script walks to.
    public mutating func updateScriptTarget(_ x: CGFloat) {
        guard case .scripted(var script, let elapsed) = state else { return }
        script.moveTo = x
        state = .scripted(script, elapsed: elapsed)
    }

    public mutating func endScript(body: inout Body) {
        guard case .scripted = state else { return }
        enterIdle(&body)
    }

    @discardableResult
    public mutating func fallAsleep(body: inout Body) -> Bool {
        guard body.isGrounded, isFree else { return false }
        enterSleep(&body)
        return true
    }

    /// Jumps onto `surface` near `x` if the pet is free (or only pursuing something at priority 1).
    @discardableResult
    public mutating func jump(to surface: Surface, x: CGFloat, halfWidth: CGFloat, body: inout Body) -> Bool {
        guard body.isGrounded else { return false }
        switch state {
        case .idle, .walk:
            break
        case .scripted(let current, _) where current.priority <= 1:
            break
        default:
            return false
        }
        launch(to: surface, x: x, halfWidth: halfWidth, &body)
        return true
    }

    // MARK: - Update

    public mutating func update(_ ctx: BrainContext, body: inout Body) {
        sinceInteraction += ctx.dt

        switch state {
        case .dragged:
            return
        case .held:
            body.velocity.dx = 0
            return
        case .fall(let startY, let thrown):
            guard body.isGrounded else { return }
            if thrown || startY - body.position.y > Self.hardLandingDrop {
                state = .landing
                setPose(.land, .down, restart: true)
            } else {
                enterIdle(&body)
            }
            return
        case .jump:
            if body.isGrounded { enterIdle(&body) }
            return
        default:
            break
        }

        guard body.isGrounded else {  // walked off an edge
            state = .fall(startY: body.position.y, thrown: false)
            setPose(.walk, .down)
            return
        }

        switch state {
        case .react, .landing, .waking:
            body.velocity.dx = 0
            if ctx.animationFinished { enterIdle(&body) }
        case .sleep:
            body.velocity.dx = 0
            if ctx.cursorMode != .off || personality == .wild {
                enterIdle(&body)
                return
            }
            napRemaining -= ctx.dt
            if napRemaining <= 0 {
                sinceInteraction = 0
                state = .waking
                setPose(.wake, .down, restart: true)
            }
        case .scripted(let script, let elapsed):
            runScript(script, elapsed: elapsed + ctx.dt, ctx, &body)
        case .idle(let remaining):
            body.velocity.dx = 0
            if applyCursor(ctx, &body) { return }
            if effectiveMode(ctx) == .follow { return }  // waits by the cursor instead of wandering
            let left = remaining - ctx.dt
            if left > 0 { state = .idle(remaining: left) } else { decideNext(ctx, &body) }
        case .walk(let targetX, let speed):
            if applyCursor(ctx, &body) { return }
            walk(toward: targetX, speed: speed, dt: ctx.dt, &body)
        default:
            break
        }
    }

    // MARK: - Scripts

    private mutating func start(_ script: Script, _ body: inout Body) {
        state = .scripted(script, elapsed: 0)
        body.velocity.dx = 0
        setPose(script.anim, script.facing, hearts: script.hearts, restart: true)
    }

    private mutating func runScript(_ script: Script, elapsed: Double, _ ctx: BrainContext, _ body: inout Body) {
        var arrived = true
        if let target = script.moveTo {
            let dx = target - body.position.x
            if abs(dx) <= max(2, script.speed * CGFloat(ctx.dt)) {
                body.velocity.dx = 0
                if script.anim == .walk { setPose(.idle, .down) }
            } else {
                arrived = false
                body.velocity.dx = dx > 0 ? script.speed : -script.speed
                let facing: Direction = script.anim == .walk ? (dx > 0 ? .right : .left) : script.facing
                setPose(script.anim, facing, hearts: script.hearts)
            }
        } else {
            body.velocity.dx = 0
        }

        let done: Bool
        switch script.end {
        case .animationFinished: done = ctx.animationFinished
        case .after(let seconds): done = elapsed >= seconds
        case .arrived: done = arrived
        }
        if done { finish(script, &body) } else { state = .scripted(script, elapsed: elapsed) }
    }

    private mutating func finish(_ script: Script, _ body: inout Body) {
        switch script.then {
        case .idle: enterIdle(&body)
        case .sleep: enterSleep(&body)
        case .script(let next): start(next, &body)
        }
    }

    // MARK: - Behaviors

    private func effectiveMode(_ ctx: BrainContext) -> CursorMode {
        personality == .wild ? .flee : ctx.cursorMode
    }

    /// Returns true if the cursor mode decided the movement for this tick.
    private mutating func applyCursor(_ ctx: BrainContext, _ body: inout Body) -> Bool {
        let p = body.position
        guard let id = body.surfaceID, let surface = ctx.world.surface(id: id, containingX: p.x) else { return false }
        switch effectiveMode(ctx) {
        case .off:
            return false

        case .follow:
            let c = ctx.cursor
            if c.y > p.y + 80, let target = bestJump(toward: c, from: p, ctx) {
                launch(to: target, x: c.x, halfWidth: ctx.halfWidth, &body)
                return true
            }
            guard abs(c.x - p.x) > 30 else { return false }
            let dropDown = c.y < p.y - 80 && surface.kind == .window
            let target = dropDown ? c.x : clamp(c.x, on: surface, ctx.halfWidth)
            let speed = Self.walkSpeed * 1.4 * speedFactor
            state = .walk(targetX: target, speed: speed)
            walk(toward: target, speed: speed, dt: ctx.dt, &body)
            return true

        case .flee:
            let radius = personality == .wild ? Self.wildFleeRadius : Self.fleeRadius
            let center = CGPoint(x: p.x, y: p.y + ctx.halfWidth)
            guard hypot(ctx.cursor.x - center.x, ctx.cursor.y - center.y) < radius else { return false }
            let away: CGFloat = ctx.cursor.x > p.x ? -1 : 1
            var target = p.x + away * 200
            if surface.kind == .floor { target = clamp(target, on: surface, ctx.halfWidth) }
            if abs(target - p.x) < 4, let escape = bestJump(awayFrom: ctx.cursor, from: p, ctx) {
                launch(to: escape, x: escape.midX, halfWidth: ctx.halfWidth, &body)
                return true
            }
            let speed = Self.walkSpeed * 1.8 * speedFactor
            state = .walk(targetX: target, speed: speed)
            walk(toward: target, speed: speed, dt: ctx.dt, &body)
            return true
        }
    }

    private mutating func decideNext(_ ctx: BrainContext, _ body: inout Body) {
        if personality == .pet && ctx.cursorMode == .off && sinceInteraction > Self.sleepAfter {
            enterSleep(&body)
            return
        }
        guard let id = body.surfaceID, let surface = ctx.world.surface(id: id, containingX: body.position.x) else {
            enterIdle(&body)
            return
        }
        let active = personality == .pet ? ctx.world.activeWindowID : nil
        let onActive = active != nil && surface.id == active
        if let active, !onActive, rng.unit() < Self.activeWindowPreference,
           headFor(activeWindow: active, from: surface, ctx, &body) {
            return
        }
        let roll = rng.unit()
        let jumpChance = personality == .wild ? 0.35 : (onActive ? 0.03 : 0.2)
        if roll < jumpChance {
            let options = reachable(from: body.position, ctx)
            if !options.isEmpty {
                let pick = options[min(Int(rng.unit() * Double(options.count)), options.count - 1)]
                launch(to: pick, x: pick.minX + CGFloat(rng.unit()) * pick.width, halfWidth: ctx.halfWidth, &body)
                return
            }
        }
        let target: CGFloat
        if surface.kind == .window && roll > 0.85 && !onActive {
            // Stroll off the edge of the window.
            target = rng.unit() < 0.5 ? surface.minX - ctx.halfWidth * 2 : surface.maxX + ctx.halfWidth * 2
        } else {
            let lo = surface.minX + ctx.halfWidth, hi = surface.maxX - ctx.halfWidth
            guard hi > lo else { enterIdle(&body); return }
            target = lo + CGFloat(rng.unit()) * (hi - lo)
        }
        let speed = Self.walkSpeed * speedFactor
        state = .walk(targetX: target, speed: speed)
        walk(toward: target, speed: speed, dt: ctx.dt, &body)
    }

    /// Moves toward the active window's top: jumps if it is reachable, walks underneath it if it is above
    /// but too far, or walks off this window's nearer edge if it is below. Returns false if there is no way.
    private mutating func headFor(activeWindow active: Int, from surface: Surface, _ ctx: BrainContext,
                                  _ body: inout Body) -> Bool {
        let p = body.position
        let tops = ctx.world.surfaces.filter { $0.id == active && $0.width >= ctx.halfWidth * 2 }
        guard let nearest = tops.min(by: { $0.distance(toX: p.x) < $1.distance(toX: p.x) }) else { return false }
        if let top = reachable(from: p, ctx).filter({ $0.id == active })
            .min(by: { $0.distance(toX: p.x) < $1.distance(toX: p.x) }) {
            launch(to: top, x: top.minX + CGFloat(rng.unit()) * top.width, halfWidth: ctx.halfWidth, &body)
            return true
        }
        let speed = Self.walkSpeed * speedFactor
        if nearest.y > p.y {
            let under = clamp(min(max(p.x, nearest.minX + ctx.halfWidth), nearest.maxX - ctx.halfWidth),
                              on: surface, ctx.halfWidth)
            guard abs(under - p.x) > 4 else { return false }
            state = .walk(targetX: under, speed: speed)
            walk(toward: under, speed: speed, dt: ctx.dt, &body)
            return true
        }
        guard surface.kind == .window else { return false }
        let target = nearest.midX < p.x ? surface.minX - ctx.halfWidth * 2 : surface.maxX + ctx.halfWidth * 2
        state = .walk(targetX: target, speed: speed)
        walk(toward: target, speed: speed, dt: ctx.dt, &body)
        return true
    }

    private mutating func walk(toward targetX: CGFloat, speed: CGFloat, dt: Double, _ body: inout Body) {
        let dx = targetX - body.position.x
        if abs(dx) <= max(2, speed * CGFloat(dt)) {
            enterIdle(&body)
            return
        }
        body.velocity.dx = dx > 0 ? speed : -speed
        setPose(.walk, dx > 0 ? .right : .left)
    }

    private mutating func launch(to surface: Surface, x: CGFloat, halfWidth: CGFloat, _ body: inout Body) {
        let p = body.position
        let landingX = surface.width > halfWidth * 2
            ? min(max(x, surface.minX + halfWidth), surface.maxX - halfWidth)
            : surface.midX
        let g = Physics.gravity
        let overshoot: CGFloat = 40
        let vy = (2 * g * (surface.y - p.y + overshoot)).squareRoot()
        let flightTime = vy / g + (2 * overshoot / g).squareRoot()
        body.velocity = CGVector(dx: (landingX - p.x) / flightTime, dy: vy)
        body.surfaceID = nil
        state = .jump
        setPose(.walk, Direction.from(dx: landingX - p.x, dy: surface.y - p.y))
    }

    private mutating func enterIdle(_ body: inout Body) {
        body.velocity.dx = 0
        state = .idle(remaining: 2 + rng.unit() * 4)
        setPose(.idle, .down)
    }

    private mutating func enterSleep(_ body: inout Body) {
        body.velocity.dx = 0
        napRemaining = Self.napLength.lowerBound + rng.unit() * (Self.napLength.upperBound - Self.napLength.lowerBound)
        state = .sleep
        setPose(.sleep, .down)
    }

    private mutating func setPose(_ anim: PetAnim, _ facing: Direction, hearts: Int = 0, restart: Bool = false) {
        pose = Pose(anim: anim, facing: facing, hearts: hearts, token: restart ? pose.token + 1 : pose.token)
    }

    // MARK: - Helpers

    private func reachable(from p: CGPoint, _ ctx: BrainContext) -> [Surface] {
        ctx.world.reachableSurfaces(from: p, maxRise: Self.maxJumpRise, maxReach: Self.maxJumpReach,
                                    minWidth: ctx.halfWidth * 2)
    }

    private func bestJump(toward cursor: CGPoint, from p: CGPoint, _ ctx: BrainContext) -> Surface? {
        reachable(from: p, ctx)
            .filter { $0.y <= cursor.y + 40 }
            .min { $0.distance(toX: cursor.x) < $1.distance(toX: cursor.x) }
    }

    private func bestJump(awayFrom cursor: CGPoint, from p: CGPoint, _ ctx: BrainContext) -> Surface? {
        reachable(from: p, ctx).max { abs($0.midX - cursor.x) < abs($1.midX - cursor.x) }
    }

    private func clamp(_ x: CGFloat, on surface: Surface, _ halfWidth: CGFloat) -> CGFloat {
        let lo = surface.minX + halfWidth, hi = surface.maxX - halfWidth
        return hi > lo ? min(max(x, lo), hi) : surface.midX
    }
}
