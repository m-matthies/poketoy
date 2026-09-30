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

/// Pets are sleepy at night and lively in the morning.
public enum TimeOfDay: Equatable, Sendable {
    case morning, day, night

    public init(hour: Int) {
        switch hour {
        case 6..<10: self = .morning
        case 10..<22: self = .day
        default: self = .night
        }
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
    public var timeOfDay: TimeOfDay
    /// The system "Reduce motion" setting: calmer pets.
    public var reduceMotion: Bool
    /// A wild Pokémon calmed by a berry: slow, and not afraid of the cursor.
    public var calm: Bool
    /// Walking speed, × normal (the player's pet speed preference).
    public var pace: CGFloat
    /// Seconds left alone before a nap (a third at night); nil: no naps on their own.
    public var napAfter: Double?

    public init(dt: Double, world: World, cursor: CGPoint, cursorMode: CursorMode, halfWidth: CGFloat,
                animationFinished: Bool, timeOfDay: TimeOfDay = .day, reduceMotion: Bool = false, calm: Bool = false,
                pace: CGFloat = 1, napAfter: Double? = PetBrain.sleepAfter) {
        self.dt = dt
        self.world = world
        self.cursor = cursor
        self.cursorMode = cursorMode
        self.halfWidth = halfWidth
        self.animationFinished = animationFinished
        self.timeOfDay = timeOfDay
        self.reduceMotion = reduceMotion
        self.calm = calm
        self.pace = pace
        self.napAfter = napAfter
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
        /// Hopping over another pet; `resume` is what it was doing and continues on landing.
        indirect case hop(resume: State)
    }

    public static let walkSpeed: CGFloat = 70
    public static let sleepAfter: Double = 60
    public static let napLength: ClosedRange<Double> = 30...120
    public static let fleeRadius: CGFloat = 150
    public static let wildFleeRadius: CGFloat = 220
    public static let hardLandingDrop: CGFloat = 150
    public static let maxJumpRise: CGFloat = 320
    public static let maxJumpReach: CGFloat = 360
    /// No script that waits for an animation or an arrival runs longer than this.
    public static let scriptTimeout = 30.0
    /// Chance that a wandering pet heads for the active window instead of a random spot.
    public static let activeWindowPreference = 0.6
    /// Chance that a pet wandering on a screen's floor heads over to a neighbouring screen.
    public static let otherScreenChance = 0.15

    public let personality: Personality
    public private(set) var state: State = .idle(remaining: 1)
    public private(set) var pose = Pose(anim: .idle, facing: .down, hearts: 0, token: 0)
    private var rng: SplitMix64
    private var sinceInteraction: Double = 0
    private var napRemaining: Double = 0
    private var timeOfDay: TimeOfDay = .day
    private var calm = false
    private var pace: CGFloat = 1
    /// Seconds left showing hearts on a stroked sleeping pet.
    private var sleepHeartsLeft: Double = 0

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

    /// The running script, also while hopping over something mid-script.
    public var script: Script? {
        switch state {
        case .scripted(let script, _), .hop(resume: .scripted(let script, _)): return script
        default: return nil
        }
    }

    private var speedFactor: CGFloat { personality == .wild ? (calm ? 0.8 : 1.6) : 1 }

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

    /// The user stroked the pet: a sleeping pet sleeps on (a little longer) with hearts; an awake one beams.
    @discardableResult
    public mutating func petted(body: inout Body) -> Bool {
        sinceInteraction = 0
        if state == .sleep {
            napRemaining = max(napRemaining, 30)
            sleepHeartsLeft = 2
            setPose(.sleep, .down, hearts: 2)
            return true
        }
        return perform(Script(anim: .greet, hearts: 2, end: .after(1.5), priority: 2), body: &body)
    }

    /// Starts `script` whatever the pet is doing (except while held or dragged, or in the air).
    @discardableResult
    public mutating func interrupt(with script: Script, body: inout Body) -> Bool {
        guard body.isGrounded, state != .dragged, state != .held else { return false }
        start(script, &body)
        return true
    }

    /// A flying wild Pokémon glides: shown walking through the air, facing where it goes.
    public mutating func glide(toward dx: CGFloat) {
        guard case .idle = state else { return }
        setPose(.walk, dx >= 0 ? .right : .left)
    }

    /// An idle pet turns to look left or right (e.g. while its window is being moved).
    public mutating func look(toward dx: CGFloat) {
        guard case .idle = state, dx != 0 else { return }
        setPose(pose.anim, dx > 0 ? .right : .left)
    }

    /// Resets the "left alone" timer that leads to sleep.
    public mutating func noteInteraction() {
        sinceInteraction = 0
    }

    /// Hops over something in the way, landing at `x` on the same `surface`, then carries on
    /// with the walk or script it was doing.
    @discardableResult
    public mutating func hop(to x: CGFloat, on surface: Surface, halfWidth: CGFloat, body: inout Body) -> Bool {
        guard body.isGrounded else { return false }
        switch state {
        case .walk, .scripted: break
        default: return false
        }
        let resume = state
        launch(to: surface, x: x, halfWidth: halfWidth, overshoot: 60, &body)
        state = .hop(resume: resume)
        return true
    }

    /// Sends a wandering pet to `x` instead, stopping it this instant.
    public mutating func redirectWalk(to x: CGFloat, body: inout Body) {
        guard case .walk(_, let speed) = state else { return }
        state = .walk(targetX: x, speed: speed)
        body.velocity.dx = 0
    }

    public mutating func endScript(body: inout Body) {
        guard case .scripted = state else { return }
        enterIdle(&body)
    }

    @discardableResult
    public mutating func fallAsleep(body: inout Body, indefinitely: Bool = false) -> Bool {
        guard body.isGrounded, isFree else { return false }
        enterSleep(&body)
        if indefinitely { napRemaining = .infinity }
        return true
    }

    /// A pet that is already asleep keeps sleeping until woken.
    public mutating func sleepIndefinitely() {
        if state == .sleep { napRemaining = .infinity }
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
        timeOfDay = ctx.timeOfDay
        calm = ctx.calm
        pace = ctx.pace

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
        case .hop(let resume):
            if body.isGrounded { state = resume }
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
            if sleepHeartsLeft > 0 {
                sleepHeartsLeft -= ctx.dt
                if sleepHeartsLeft <= 0 { setPose(.sleep, .down) }
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
        let speed = script.speed * pace * (ctx.reduceMotion ? 0.7 : 1)
        if let target = script.moveTo {
            let dx = target - body.position.x
            if abs(dx) <= max(2, speed * CGFloat(ctx.dt)) {
                body.velocity.dx = 0
                if script.anim == .walk { setPose(.idle, .down) }
            } else {
                arrived = false
                body.velocity.dx = dx > 0 ? speed : -speed
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
        let overdue: Bool
        if case .after = script.end { overdue = false } else { overdue = elapsed > Self.scriptTimeout }
        if done || overdue { finish(script, &body) } else { state = .scripted(script, elapsed: elapsed) }
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
        personality == .wild ? (ctx.calm ? .off : .flee) : ctx.cursorMode
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
            if c.y > p.y + 80, !ctx.reduceMotion, let target = bestJump(toward: c, from: p, ctx) {
                launch(to: target, x: c.x, halfWidth: ctx.halfWidth, &body)
                return true
            }
            guard abs(c.x - p.x) > 30 else { return false }
            let dropDown = c.y < p.y - 80 && surface.kind == .window
            let target = dropDown ? c.x : clamp(c.x, on: surface, ctx.halfWidth)
            let speed = Self.walkSpeed * 1.4 * speedFactor * (ctx.reduceMotion ? 0.7 : 1)
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
            if abs(target - p.x) < 4, !ctx.reduceMotion, let escape = bestJump(awayFrom: ctx.cursor, from: p, ctx) {
                launch(to: escape, x: escape.midX, halfWidth: ctx.halfWidth, &body)
                return true
            }
            let speed = Self.walkSpeed * 1.8 * speedFactor * (ctx.reduceMotion ? 0.7 : 1)
            state = .walk(targetX: target, speed: speed)
            walk(toward: target, speed: speed, dt: ctx.dt, &body)
            return true
        }
    }

    private mutating func decideNext(_ ctx: BrainContext, _ body: inout Body) {
        if personality == .pet && ctx.cursorMode == .off, let napAfter = ctx.napAfter,
           sinceInteraction > (ctx.timeOfDay == .night ? napAfter / 3 : napAfter) {
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
        if personality == .pet, surface.kind == .floor, rng.unit() < Self.otherScreenChance,
           headForNeighbourScreen(from: surface, ctx, &body) {
            return
        }
        let roll = rng.unit()
        var jumpChance = personality == .wild ? 0.5 : (onActive ? 0.03 : 0.2)
        if ctx.timeOfDay == .morning { jumpChance += 0.1 }
        if ctx.reduceMotion { jumpChance = 0 }
        if roll < jumpChance {
            var options = reachable(from: body.position, ctx)
            // Wild Pokémon like hopping between window tops.
            if personality == .wild, options.contains(where: { $0.kind == .window }) {
                options = options.filter { $0.kind == .window }
            }
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
        var speed = Self.walkSpeed * speedFactor
        if ctx.timeOfDay == .morning { speed *= 1.2 }
        if ctx.reduceMotion { speed *= 0.7 }
        state = .walk(targetX: target, speed: speed)
        walk(toward: target, speed: speed, dt: ctx.dt, &body)
    }

    /// Moves toward the active window's top: jumps up to it (at any height) once within horizontal reach,
    /// walks underneath it if it is too far to the side, or walks off this window's nearer edge if it is below.
    /// Returns false if there is no way.
    private mutating func headFor(activeWindow active: Int, from surface: Surface, _ ctx: BrainContext,
                                  _ body: inout Body) -> Bool {
        let p = body.position
        let tops = ctx.world.surfaces.filter { $0.id == active && $0.width >= ctx.halfWidth * 2 }
        guard let nearest = tops.min(by: { $0.distance(toX: p.x) < $1.distance(toX: p.x) }) else { return false }
        // Any height will do for the active window: one big jump once it's within horizontal reach.
        let upToActive = ctx.world.reachableSurfaces(from: p, maxRise: .greatestFiniteMagnitude,
                                                     maxReach: Self.maxJumpReach, minWidth: ctx.halfWidth * 2)
        if let top = upToActive.filter({ $0.id == active })
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

    /// Wanders over to a screen whose floor touches this floor's end: walks off the end if that floor is
    /// level or lower, or jumps up to it if it's higher and within reach. Returns false if there's none.
    private mutating func headForNeighbourScreen(from floor: Surface, _ ctx: BrainContext, _ body: inout Body) -> Bool {
        let neighbours = ctx.world.surfaces.filter {
            $0.kind == .floor && (abs($0.minX - floor.maxX) <= 2 || abs($0.maxX - floor.minX) <= 2)
        }
        guard !neighbours.isEmpty else { return false }
        let pick = neighbours[min(Int(rng.unit() * Double(neighbours.count)), neighbours.count - 1)]
        // On that side of the border, the highest floor is the one a pet would stand on.
        let toRight = abs(pick.minX - floor.maxX) <= 2
        guard let target = neighbours.filter({ (abs($0.minX - floor.maxX) <= 2) == toRight }).max(by: { $0.y < $1.y })
        else { return false }
        let p = body.position
        if target.y <= floor.y + 2 {
            let exit = toRight ? floor.maxX + ctx.halfWidth * 2 : floor.minX - ctx.halfWidth * 2
            var speed = Self.walkSpeed
            if ctx.reduceMotion { speed *= 0.7 }
            state = .walk(targetX: exit, speed: speed)
            walk(toward: exit, speed: speed, dt: ctx.dt, &body)
            return true
        }
        guard !ctx.reduceMotion, target.y - p.y <= Self.maxJumpRise, target.distance(toX: p.x) <= Self.maxJumpReach
        else { return false }
        let landing = toRight ? target.minX + ctx.halfWidth * 3 : target.maxX - ctx.halfWidth * 3
        launch(to: target, x: landing, halfWidth: ctx.halfWidth, &body)
        return true
    }

    private mutating func walk(toward targetX: CGFloat, speed: CGFloat, dt: Double, _ body: inout Body) {
        let speed = speed * pace
        let dx = targetX - body.position.x
        if abs(dx) <= max(2, speed * CGFloat(dt)) {
            enterIdle(&body)
            return
        }
        body.velocity.dx = dx > 0 ? speed : -speed
        setPose(.walk, dx > 0 ? .right : .left)
    }

    private mutating func launch(to surface: Surface, x: CGFloat, halfWidth: CGFloat, overshoot: CGFloat = 40,
                                 _ body: inout Body) {
        let p = body.position
        let landingX = surface.width > halfWidth * 2
            ? min(max(x, surface.minX + halfWidth), surface.maxX - halfWidth)
            : surface.midX
        let g = Physics.gravity
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
        let naps = timeOfDay == .night ? 120.0...300.0 : Self.napLength
        napRemaining = naps.lowerBound + rng.unit() * (naps.upperBound - naps.lowerBound)
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
