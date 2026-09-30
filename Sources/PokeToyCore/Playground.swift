import CoreGraphics
import Foundation

public enum PetRole: Equatable, Sendable {
    case own, wild
}

/// One simulated Pokémon: its behavior, body and animation state.
public struct PetActor: Identifiable, Sendable {
    public let id: UUID
    public let role: PetRole
    public let metrics: PetMetrics
    public internal(set) var brain: PetBrain
    public internal(set) var body: Body
    public internal(set) var animator = Animator()
    /// False while caught inside a Poké Ball: not drawn and not simulated.
    public internal(set) var visible = true
    public internal(set) var scale: CGFloat
    var poseToken = -1
    var lifetime: Double = .infinity
    var leaving = false
    /// Where a leaving wild Pokémon walks to: just past the outer edge of all screens, decided once.
    var exitX: CGFloat?
    var wasSleeping = false

    init(id: UUID, role: PetRole, metrics: PetMetrics, brain: PetBrain, body: Body, scale: CGFloat) {
        self.id = id
        self.role = role
        self.metrics = metrics
        self.brain = brain
        self.body = body
        self.scale = scale
    }

    public var pose: Pose { brain.pose }

    // Brain calls that also need the body. Going through the actor avoids overlapping
    // accesses to the `Playground.pets` array (brain and body of the same element at once).

    mutating func update(_ context: BrainContext) {
        brain.update(context, body: &body)
    }

    mutating func handle(_ event: PetEvent) {
        brain.handle(event, body: &body)
    }

    @discardableResult
    mutating func perform(_ script: Script) -> Bool {
        brain.perform(script, body: &body)
    }

    mutating func endScript() {
        brain.endScript(body: &body)
    }

    @discardableResult
    mutating func fallAsleep() -> Bool {
        brain.fallAsleep(body: &body)
    }

    @discardableResult
    mutating func hop(to x: CGFloat, on surface: Surface) -> Bool {
        brain.hop(to: x, on: surface, halfWidth: halfWidth, body: &body)
    }

    mutating func redirectWalk(to x: CGFloat) {
        brain.redirectWalk(to: x, body: &body)
    }

    @discardableResult
    mutating func jump(to surface: Surface, x: CGFloat) -> Bool {
        brain.jump(to: surface, x: x, halfWidth: halfWidth, body: &body)
    }

    var frameSize: CGSize {
        metrics.frameSizes[brain.pose.anim] ?? CGSize(width: 32, height: 40)
    }

    /// Roughly half the visible character's width on screen (frames have transparent padding).
    public var halfWidth: CGFloat { frameSize.width * scale * 0.3 }

    /// The character's approximate body on screen, used for pet-to-pet overlap.
    public var bodyRect: CGRect {
        CGRect(x: body.position.x - halfWidth, y: body.position.y,
               width: halfWidth * 2, height: frameSize.height * scale * 0.6)
    }

    /// The sprite frame shrunk by 20%, used for Poké Ball hits.
    public var hitRect: CGRect {
        let width = frameSize.width * scale, height = frameSize.height * scale
        return CGRect(x: body.position.x - width * 0.4, y: body.position.y, width: width * 0.8, height: height * 0.8)
    }
}

public enum MomentKind: Equatable, Sendable {
    case greet, tag, playFight
}

public enum PlaygroundEvent: Equatable, Sendable {
    case friendshipChanged
    case momentStarted(MomentKind)
    case treatEaten(petID: UUID)
    case wildSpawned(petID: UUID, path: String)
    case wildRemoved(petID: UUID)
    case ballHit(petID: UUID)
    case caught(petID: UUID)
    case brokeFree(petID: UUID)
    case roundEnded
}

/// A social moment in progress between two pets.
struct ActiveMoment: Equatable, Sendable {
    var kind: MomentKind
    /// Greet: either pet. Tag: the chaser. Play-fight: the attacker.
    var a: UUID
    /// Greet: the other pet. Tag: the runner. Play-fight: the defender.
    var b: UUID
    var elapsed: Double = 0
    /// Play-fight: 0 attacking, 1 flinching. Tag: 1 once the roles have swapped.
    var stage = 0
}

/// The whole simulation: pets, items, friendships and the catch game, advanced by `tick`.
public struct Playground: Sendable {
    public static let maxOwnPets = 12
    public static let maxTreats = 10

    public internal(set) var pets: [PetActor] = []
    public internal(set) var items: [Item] = []
    public internal(set) var friendships: Friendships
    public internal(set) var game: CatchGame?
    public internal(set) var lastResults: CatchResults?
    public private(set) var scale: CGFloat

    var rng: SplitMix64
    var moments: [ActiveMoment] = []
    var pairCooldowns: [String: Double] = [:]
    var knockCooldowns: [String: Double] = [:]
    var followTimers: [UUID: Double] = [:]
    /// Pet → the treat it is heading for.
    var treatTargets: [UUID: UUID] = [:]
    var wildSpecs: [UUID: WildSpec] = [:]
    /// Wild Pokémon that just broke out of a ball and will dash away once they land.
    var fleeBoost: Set<UUID> = []
    var events: [PlaygroundEvent] = []

    public init(seed: UInt64, scale: CGFloat = 2, friendships: Friendships = Friendships()) {
        rng = SplitMix64(seed: seed)
        self.scale = scale
        self.friendships = friendships
    }

    // MARK: - Queries

    public func pet(_ id: UUID) -> PetActor? {
        pets.first { $0.id == id }
    }

    public var canDropTreat: Bool {
        game == nil && items.filter { $0.kind.isTreat }.count < Self.maxTreats
    }

    public var ballsInFlight: Int {
        items.filter { $0.state == .flying }.count
    }

    func index(of id: UUID) -> Int? {
        pets.firstIndex { $0.id == id }
    }

    func itemIndex(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    func inMoment(_ id: UUID) -> Bool {
        moments.contains { $0.a == id || $0.b == id }
    }

    // MARK: - Pets

    @discardableResult
    public mutating func addPet(id: UUID = UUID(), role: PetRole = .own, metrics: PetMetrics, at position: CGPoint) -> UUID {
        let brain = PetBrain(seed: rng.next(), personality: role == .own ? .pet : .wild)
        pets.append(PetActor(id: id, role: role, metrics: metrics, brain: brain, body: Body(position: position), scale: scale))
        return id
    }

    public mutating func removePet(_ id: UUID) {
        for moment in moments where moment.a == id || moment.b == id {
            let partner = moment.a == id ? moment.b : moment.a
            if let p = index(of: partner) { pets[p].endScript() }
        }
        moments.removeAll { $0.a == id || $0.b == id }
        let wasOwn = pet(id)?.role == .own
        pets.removeAll { $0.id == id }
        treatTargets[id] = nil
        followTimers[id] = nil
        wildSpecs[id] = nil
        fleeBoost.remove(id)
        if wasOwn {
            friendships.remove(id)
            events.append(.friendshipChanged)
        }
    }

    public mutating func setScale(_ scale: CGFloat) {
        self.scale = scale
        for i in pets.indices { pets[i].scale = scale }
    }

    public mutating func handle(_ event: PetEvent, pet id: UUID) {
        guard let i = index(of: id), pets[i].visible else { return }
        pets[i].handle(event)
    }

    public mutating func movePet(_ id: UUID, to position: CGPoint) {
        guard let i = index(of: id) else { return }
        pets[i].body.position = position
    }

    // MARK: - Items

    /// Adds a treat at `position` (it falls from there). Returns nil at the cap, during a game, or for a non-treat.
    @discardableResult
    public mutating func dropTreat(_ kind: ItemKind, at position: CGPoint) -> UUID? {
        guard kind.isTreat, canDropTreat else { return nil }
        let item = Item(kind: kind, body: Body(position: position))
        items.append(item)
        return item.id
    }

    public mutating func handle(_ event: ItemEvent, item id: UUID) {
        guard let i = itemIndex(of: id), items[i].kind.isTreat else { return }
        switch event {
        case .pressed:
            items[i].state = .held
            items[i].body.velocity = .zero
            items[i].age = 0
        case .released:
            guard items[i].state == .held else { return }
            items[i].state = .free
        case .dragBegan:
            items[i].state = .held
            items[i].body.surfaceID = nil
            items[i].body.velocity = .zero
        case .dragEnded(let velocity):
            items[i].state = .free
            items[i].body.surfaceID = nil
            items[i].body.velocity = velocity
        }
    }

    public mutating func moveItem(_ id: UUID, to position: CGPoint) {
        guard let i = itemIndex(of: id) else { return }
        items[i].body.position = position
    }

    // MARK: - Tick

    public mutating func tick(dt: Double, world: World, cursor: CGPoint, cursorMode: CursorMode) -> [PlaygroundEvent] {
        events = []
        Self.decay(&pairCooldowns, dt)
        Self.decay(&knockCooldowns, dt)
        for i in pets.indices where pets[i].visible {
            updateBrain(i, dt: dt, world: world, cursor: cursor, cursorMode: cursorMode)
        }
        rulesBeforePhysics(dt: dt, world: world)
        for i in pets.indices where pets[i].visible && pets[i].brain.state != .dragged {
            Physics.step(&pets[i].body, dt: CGFloat(dt), world: world)
        }
        stepItems(dt: dt, world: world)
        rulesAfterPhysics(dt: dt, world: world)
        for i in pets.indices { advanceAnimation(i, dt: dt) }
        recover(world: world)
        return events
    }

    /// Rules that direct pets before they move (catch game, social moments, feeding).
    mutating func rulesBeforePhysics(dt: Double, world: World) {
        gameRulesBeforePhysics(dt: dt, world: world)
        socialRules(dt: dt, world: world)
        feedingRules(world: world)
        passingRules(dt: dt, world: world)
    }

    /// Rules that react to where things ended up (collisions, Poké Ball hits).
    mutating func rulesAfterPhysics(dt: Double, world: World) {
        collisionRules(world: world)
        gameRulesAfterPhysics(dt: dt)
    }

    private mutating func updateBrain(_ i: Int, dt: Double, world: World, cursor: CGPoint, cursorMode: CursorMode) {
        let pet = pets[i]
        let finished = pet.animator.finished && pet.animator.kind == pet.brain.pose.anim
            && pet.poseToken == pet.brain.pose.token
        let context = BrainContext(dt: dt, world: world, cursor: cursor,
                                   cursorMode: pet.role == .own ? cursorMode : .off,
                                   halfWidth: pet.halfWidth, animationFinished: finished)
        pets[i].update(context)
    }

    private mutating func advanceAnimation(_ i: Int, dt: Double) {
        let pose = pets[i].brain.pose
        pets[i].animator.play(pose.anim)
        if pose.token != pets[i].poseToken {
            pets[i].animator.restart()
            pets[i].poseToken = pose.token
        }
        pets[i].animator.advance(dt: dt, durations: pets[i].metrics.durations[pose.anim] ?? [1])
    }

    private mutating func stepItems(dt: Double, world: World) {
        for i in items.indices {
            switch items[i].state {
            case .held:
                continue
            case .fading(let remaining):
                items[i].state = .fading(remaining: remaining - dt)
            default:
                break
            }
            if items[i].kind.isTreat, items[i].state == .free, items[i].body.isGrounded { items[i].age += dt }
            let landed = Physics.step(&items[i].body, dt: CGFloat(dt), world: world)
            if landed && items[i].state == .flying {
                items[i].state = .fading(remaining: 1.5)  // a ball that hit nothing
            }
        }
        items.removeAll {
            if case .fading(let remaining) = $0.state { return remaining <= 0 }
            return $0.kind.isTreat && $0.age > Self.treatLifetime  // spoiled
        }
    }

    private mutating func recover(world: World) {
        guard !world.screens.isEmpty else { return }
        for i in pets.indices where pets[i].role == .own && pets[i].visible && pets[i].brain.state != .dragged
            && !world.isRecoverable(pets[i].body.position, margin: 200) {
            pets[i].body = Body(position: world.spawnPoint(fraction: 0.5))  // lost off-screen: drop back in
            pets[i].handle(.dragEnded(velocity: .zero))
        }
        let gone = pets.filter {
            $0.role == .wild && $0.visible
                && (!world.isWithinScreens(x: $0.body.position.x) || !world.isRecoverable($0.body.position, margin: 200))
        }.map(\.id)
        for id in gone {
            removePet(id)
            events.append(.wildRemoved(petID: id))
        }
        items.removeAll { item in
            if case .wobbling = item.state { return false }
            return item.state != .held && !world.isRecoverable(item.body.position, margin: 200)
        }
    }

    static func decay(_ timers: inout [String: Double], _ dt: Double) {
        timers = timers.compactMapValues { $0 - dt > 0 ? $0 - dt : nil }
    }
}
