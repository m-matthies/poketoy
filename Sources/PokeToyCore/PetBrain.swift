import CoreGraphics

public enum CursorMode: String, Codable, CaseIterable, Sendable {
    case off, follow, flee
}

public enum PetEvent: Equatable, Sendable {
    case click
    case dragBegan
    case dragEnded(velocity: CGVector)
}

public struct Pose: Equatable, Sendable {
    public var anim: PetAnim
    public var facing: Direction
    public var showHeart: Bool
    /// Changes whenever the animation should restart from its first frame.
    public var token: Int
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
        case jump
        case fall(startY: CGFloat, thrown: Bool)
        case dragged
        case react
        case landing
    }

    public static let walkSpeed: CGFloat = 70
    public static let sleepAfter: Double = 60
    public static let fleeRadius: CGFloat = 150
    public static let hardLandingDrop: CGFloat = 150
    public static let maxJumpRise: CGFloat = 320
    public static let maxJumpReach: CGFloat = 360

    public private(set) var state: State = .idle(remaining: 1)
    public private(set) var pose = Pose(anim: .idle, facing: .down, showHeart: false, token: 0)
    private var rng: SplitMix64
    private var sinceInteraction: Double = 0

    public init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
    }

    public mutating func handle(_ event: PetEvent, body: inout Body) {
        sinceInteraction = 0
        switch event {
        case .click:
            guard body.isGrounded, state != .dragged else { return }
            body.velocity.dx = 0
            state = .react
            setPose(.react, .down, heart: true, restart: true)
        case .dragBegan:
            state = .dragged
            body.surfaceID = nil
            body.velocity = .zero
            setPose(.dangle, .down, restart: true)
        case .dragEnded(let velocity):
            state = .fall(startY: body.position.y, thrown: true)
            body.velocity = velocity
        }
    }

    public mutating func update(_ ctx: BrainContext, body: inout Body) {
        sinceInteraction += ctx.dt

        switch state {
        case .dragged:
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
        case .react, .landing:
            body.velocity.dx = 0
            if ctx.animationFinished { enterIdle(&body) }
        case .sleep:
            body.velocity.dx = 0
            if ctx.cursorMode != .off { enterIdle(&body) }
        case .idle(let remaining):
            body.velocity.dx = 0
            if applyCursor(ctx, &body) { return }
            if ctx.cursorMode == .follow { return }  // waits by the cursor instead of wandering
            let left = remaining - ctx.dt
            if left > 0 { state = .idle(remaining: left) } else { decideNext(ctx, &body) }
        case .walk(let targetX, let speed):
            if applyCursor(ctx, &body) { return }
            walk(toward: targetX, speed: speed, dt: ctx.dt, &body)
        default:
            break
        }
    }

    // MARK: - Behaviors

    /// Returns true if the cursor mode decided the movement for this tick.
    private mutating func applyCursor(_ ctx: BrainContext, _ body: inout Body) -> Bool {
        let p = body.position
        guard let id = body.surfaceID, let surface = ctx.world.surface(id: id, containingX: p.x) else { return false }
        switch ctx.cursorMode {
        case .off:
            return false

        case .follow:
            let c = ctx.cursor
            if c.y > p.y + 80, let target = bestJump(toward: c, from: p, ctx) {
                jump(to: target, x: c.x, ctx, &body)
                return true
            }
            guard abs(c.x - p.x) > 30 else { return false }
            let dropDown = c.y < p.y - 80 && surface.kind == .window
            let target = dropDown ? c.x : clamp(c.x, on: surface, ctx.halfWidth)
            let speed = Self.walkSpeed * 1.4
            state = .walk(targetX: target, speed: speed)
            walk(toward: target, speed: speed, dt: ctx.dt, &body)
            return true

        case .flee:
            let center = CGPoint(x: p.x, y: p.y + ctx.halfWidth)
            guard hypot(ctx.cursor.x - center.x, ctx.cursor.y - center.y) < Self.fleeRadius else { return false }
            let away: CGFloat = ctx.cursor.x > p.x ? -1 : 1
            var target = p.x + away * 200
            if surface.kind == .floor { target = clamp(target, on: surface, ctx.halfWidth) }
            if abs(target - p.x) < 4, let escape = bestJump(awayFrom: ctx.cursor, from: p, ctx) {
                jump(to: escape, x: escape.midX, ctx, &body)
                return true
            }
            let speed = Self.walkSpeed * 1.8
            state = .walk(targetX: target, speed: speed)
            walk(toward: target, speed: speed, dt: ctx.dt, &body)
            return true
        }
    }

    private mutating func decideNext(_ ctx: BrainContext, _ body: inout Body) {
        if ctx.cursorMode == .off && sinceInteraction > Self.sleepAfter {
            state = .sleep
            setPose(.sleep, .down)
            return
        }
        guard let id = body.surfaceID, let surface = ctx.world.surface(id: id, containingX: body.position.x) else {
            enterIdle(&body)
            return
        }
        let roll = rng.unit()
        if roll < 0.2 {
            let options = reachable(from: body.position, ctx)
            if !options.isEmpty {
                let pick = options[min(Int(rng.unit() * Double(options.count)), options.count - 1)]
                jump(to: pick, x: pick.minX + CGFloat(rng.unit()) * pick.width, ctx, &body)
                return
            }
        }
        let target: CGFloat
        if surface.kind == .window && roll > 0.85 {
            // Stroll off the edge of the window.
            target = rng.unit() < 0.5 ? surface.minX - ctx.halfWidth * 2 : surface.maxX + ctx.halfWidth * 2
        } else {
            let lo = surface.minX + ctx.halfWidth, hi = surface.maxX - ctx.halfWidth
            guard hi > lo else { enterIdle(&body); return }
            target = lo + CGFloat(rng.unit()) * (hi - lo)
        }
        state = .walk(targetX: target, speed: Self.walkSpeed)
        walk(toward: target, speed: Self.walkSpeed, dt: ctx.dt, &body)
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

    private mutating func jump(to surface: Surface, x: CGFloat, _ ctx: BrainContext, _ body: inout Body) {
        let p = body.position
        let landingX = surface.width > ctx.halfWidth * 2
            ? min(max(x, surface.minX + ctx.halfWidth), surface.maxX - ctx.halfWidth)
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

    private mutating func setPose(_ anim: PetAnim, _ facing: Direction, heart: Bool = false, restart: Bool = false) {
        pose = Pose(anim: anim, facing: facing, showHeart: heart, token: restart ? pose.token + 1 : pose.token)
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
