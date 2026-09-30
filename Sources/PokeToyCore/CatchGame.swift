import CoreGraphics
import Foundation

/// A Pokémon that can appear in a catch round.
public struct WildSpec: Equatable, Sendable {
    public let path: String
    public let displayName: String
    public let metrics: PetMetrics
    public let isLegendary: Bool
    /// SpriteCollab path of its shiny sprites, if it has them (then 1 in 64 spawns are shiny).
    public let shinyPath: String?
    /// Flying types glide through the air instead of walking.
    public let canFly: Bool

    public init(path: String, displayName: String, metrics: PetMetrics, isLegendary: Bool = false,
                shinyPath: String? = nil, canFly: Bool = false) {
        self.path = path
        self.displayName = displayName
        self.metrics = metrics
        self.isLegendary = isLegendary
        self.shinyPath = shinyPath
        self.canFly = canFly
    }
}

/// Better balls come with combos.
public enum BallTier: Int, Sendable {
    case poke, great, ultra

    public var catchChance: Double {
        switch self {
        case .poke: return 0.6
        case .great: return 0.75
        case .ultra: return 0.9
        }
    }

    public var itemKind: ItemKind {
        switch self {
        case .poke: return .pokeBall
        case .great: return .greatBall
        case .ultra: return .ultraBall
        }
    }
}

public struct CatchRecord: Equatable, Sendable {
    public let petID: UUID
    public let path: String
    public let displayName: String
    /// Where the ball was when the Pokémon was caught; kept Pokémon appear here.
    public let position: CGPoint
    public let isShiny: Bool

    public init(petID: UUID, path: String, displayName: String, position: CGPoint, isShiny: Bool = false) {
        self.petID = petID
        self.path = path
        self.displayName = displayName
        self.position = position
        self.isShiny = isShiny
    }
}

public struct CatchResults: Equatable, Sendable {
    public let score: Int
    public let catches: [CatchRecord]

    public init(score: Int, catches: [CatchRecord]) {
        self.score = score
        self.catches = catches
    }
}

/// Timers, spawning, catch rolls and score for one timed catch round.
public struct CatchGame: Sendable {
    public enum Phase: Equatable, Sendable {
        case countdown(remaining: Double)
        case playing(remaining: Double)
        case finished
    }

    public static let countdownLength = 3.0
    public static let roundLength = 60.0
    public static let maxWild = 3
    public static let maxBallsInFlight = 8
    public static let defaultCatchChance = BallTier.poke.catchChance
    public static let legendaryChance = 0.05
    public static let shinyChance = 1.0 / 64
    public static let berriesPerRound = 3
    /// Regular Pokémon per round (plus one legendary): enough that a 60 s round rarely sees the same one twice.
    public static let rosterRegulars = 12
    public static let calmBonus = 0.15
    public static let firstThrowBonus = 50
    public static let hitPoints = 25
    public static let catchPoints = 100
    public static let spawnInterval: ClosedRange<Double> = 4...7
    public static let lifetime: ClosedRange<Double> = 12...20

    public let roster: [WildSpec]
    public private(set) var phase: Phase = .countdown(remaining: CatchGame.countdownLength)
    public private(set) var score = 0
    public private(set) var catches: [CatchRecord] = []
    /// Consecutive hits; a ball that hits nothing resets it.
    public private(set) var combo = 0
    public private(set) var berriesLeft = CatchGame.berriesPerRound
    /// Overrides every catch chance (tests).
    var catchChance: Double?
    var shinyOdds = CatchGame.shinyChance
    // Independent random streams, so an optional extra (a shiny sprite, a flying type) never shifts
    // the spawns or catch rolls of a seeded round.
    private var spawnRNG: SplitMix64
    private var placeRNG: SplitMix64
    private var rollRNG: SplitMix64
    private var nextSpawnIn = 0.5
    /// Regular Pokémon still to appear before the roster starts over, so a round rarely repeats one.
    private var bag: [String] = []
    private var lastSpawned: String?
    /// Species caught this round; they don't come back.
    private var caughtSpecies: Set<String> = []
    private var endRequested = false

    public init(roster: [WildSpec], seed: UInt64) {
        self.roster = roster.sorted { $0.path < $1.path }  // the same round whatever order the roster loaded in
        spawnRNG = SplitMix64(seed: seed)
        placeRNG = SplitMix64(seed: seed ^ 0x5EED_0F0F_1234_5678)
        rollRNG = SplitMix64(seed: seed &+ 0x0BAD_CAFE)
    }

    public var isPlaying: Bool {
        if case .playing = phase { return true }
        return false
    }

    /// Counting down or playing.
    public var isActive: Bool { phase != .finished }

    public mutating func requestEnd() {
        endRequested = true
    }

    /// Advances the timers. Returns true on the step the round finishes.
    @discardableResult
    public mutating func advance(dt: Double) -> Bool {
        switch phase {
        case .countdown(let remaining):
            if endRequested {
                phase = .finished
                return true
            }
            let left = remaining - dt
            phase = left > 0 ? .countdown(remaining: left) : .playing(remaining: Self.roundLength)
        case .playing(let remaining):
            let left = remaining - dt
            if endRequested || left <= 0 {
                phase = .finished
                return true
            }
            phase = .playing(remaining: left)
        case .finished:
            break
        }
        return false
    }

    /// A wild Pokémon to spawn this step, if one is due and there is room: legendaries about 5% of the time,
    /// and 1 in 64 is shiny when it has shiny sprites. Every regular appears once before any comes back, never
    /// twice in a row, and caught species don't return (unless everything has been caught).
    public mutating func spawn(dt: Double, wildCount: Int) -> (spec: WildSpec, shiny: Bool)? {
        guard isPlaying, !roster.isEmpty else { return nil }
        nextSpawnIn -= dt
        guard nextSpawnIn <= 0, wildCount < Self.maxWild else { return nil }
        nextSpawnIn = Self.random(in: Self.spawnInterval, &spawnRNG)
        // Always the same three rolls per spawn, whatever the roster offers.
        let legendRoll = spawnRNG.unit(), pickRoll = spawnRNG.unit(), shinyRoll = spawnRNG.unit()
        let legendaries = roster.filter { $0.isLegendary && !isCaught($0.path) }
        let regulars = roster.filter { !$0.isLegendary }
        bag.removeAll(where: isCaught)
        if bag.isEmpty {
            let fresh = regulars.filter { !isCaught($0.path) }.map(\.path)
            bag = fresh.isEmpty && legendaries.isEmpty ? regulars.map(\.path) : fresh
        }
        let spec: WildSpec
        if !legendaries.isEmpty && (bag.isEmpty || legendRoll < Self.legendaryChance) {
            spec = legendaries[Self.index(pickRoll, legendaries.count)]
        } else if !bag.isEmpty {
            var i = Self.index(pickRoll, bag.count)
            if bag.count > 1 && bag[i] == lastSpawned { i = (i + 1) % bag.count }  // just refilled: not the same again
            let path = bag.remove(at: i)
            spec = regulars.first { $0.path == path }!
        } else {
            spec = roster[Self.index(pickRoll, roster.count)]  // only caught legendaries: let them come back
        }
        lastSpawned = spec.path
        let shiny = spec.shinyPath != nil && shinyRoll < shinyOdds
        return (spec, shiny)
    }

    /// The ball the player throws next.
    public var ballTier: BallTier {
        combo >= 5 ? .ultra : combo >= 3 ? .great : .poke
    }

    /// Points multiplier for the current combo: +25% per consecutive hit after the first, at most ×2.
    public var comboMultiplier: Double {
        combo < 1 ? 1 : min(2, 1 + 0.25 * Double(combo - 1))
    }

    /// A ball landed without hitting anything.
    public mutating func registerMiss() {
        combo = 0
    }

    /// Takes one of the round's Razz Berries; false when none are left.
    public mutating func useBerry() -> Bool {
        guard berriesLeft > 0 else { return false }
        berriesLeft -= 1
        return true
    }

    public func catchChance(tier: BallTier, calmed: Bool) -> Double {
        catchChance ?? min(1, tier.catchChance + (calmed ? Self.calmBonus : 0))
    }

    public mutating func wildLifetime() -> Double {
        Self.random(in: Self.lifetime, &placeRNG)
    }

    /// Decides at the moment of a hit whether the Pokémon will be caught and how often the ball wobbles first.
    public mutating func rollCatch(tier: BallTier = .poke, calmed: Bool = false) -> (caught: Bool, wobbles: Int) {
        let caught = rollRNG.unit() < catchChance(tier: tier, calmed: calmed)
        let wobbles = 1 + min(Int(rollRNG.unit() * 3), 2)
        return (caught, wobbles)
    }

    /// For placing wild Pokémon (screen, side, height).
    public mutating func randomUnit() -> Double {
        placeRNG.unit()
    }

    public mutating func recordHit(isLegendary: Bool = false, isShiny: Bool = false) {
        combo += 1
        score += points(Self.hitPoints, isLegendary: isLegendary, isShiny: isShiny)
    }

    /// `multiplier` is the combo multiplier when the ball hit (the combo may have changed while it wobbled).
    public mutating func recordCatch(_ record: CatchRecord, isLegendary: Bool = false, firstThrow: Bool = false,
                                     multiplier: Double? = nil) {
        score += points(Self.catchPoints, isLegendary: isLegendary, isShiny: record.isShiny, multiplier: multiplier)
        if firstThrow { score += Self.firstThrowBonus }
        catches.append(record)
        if let species = Pokedex.key(forPath: record.path) { caughtSpecies.insert(species) }
    }

    /// Base points × 3 for legendaries × 2 for shinies × the combo multiplier.
    private func points(_ base: Int, isLegendary: Bool, isShiny: Bool, multiplier: Double? = nil) -> Int {
        let rarity = (isLegendary ? 3.0 : 1.0) * (isShiny ? 2.0 : 1.0)
        return Int((Double(base) * rarity * (multiplier ?? comboMultiplier)).rounded())
    }

    /// How many of `catches` can still become pets without exceeding `cap`.
    public static func keepable(_ catches: [CatchRecord], ownPetCount: Int, cap: Int) -> Int {
        max(0, min(catches.count, cap - ownPetCount))
    }

    private func isCaught(_ path: String) -> Bool {
        Pokedex.key(forPath: path).map(caughtSpecies.contains) ?? false
    }

    private static func index(_ roll: Double, _ count: Int) -> Int {
        min(Int(roll * Double(count)), count - 1)
    }

    private static func random(in range: ClosedRange<Double>, _ rng: inout SplitMix64) -> Double {
        range.lowerBound + rng.unit() * (range.upperBound - range.lowerBound)
    }
}
