import CoreGraphics
import Foundation

/// A Pokémon that can appear in a catch round.
public struct WildSpec: Equatable, Sendable {
    public let path: String
    public let displayName: String
    public let metrics: PetMetrics

    public init(path: String, displayName: String, metrics: PetMetrics) {
        self.path = path
        self.displayName = displayName
        self.metrics = metrics
    }
}

public struct CatchRecord: Equatable, Sendable {
    public let petID: UUID
    public let path: String
    public let displayName: String
    /// Where the ball was when the Pokémon was caught; kept Pokémon appear here.
    public let position: CGPoint

    public init(petID: UUID, path: String, displayName: String, position: CGPoint) {
        self.petID = petID
        self.path = path
        self.displayName = displayName
        self.position = position
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
    public static let defaultCatchChance = 0.6
    public static let hitPoints = 25
    public static let catchPoints = 100
    public static let spawnInterval: ClosedRange<Double> = 4...7
    public static let lifetime: ClosedRange<Double> = 12...20

    public let roster: [WildSpec]
    public private(set) var phase: Phase = .countdown(remaining: CatchGame.countdownLength)
    public private(set) var score = 0
    public private(set) var catches: [CatchRecord] = []
    var catchChance = CatchGame.defaultCatchChance
    private var rng: SplitMix64
    private var nextSpawnIn = 0.5
    private var endRequested = false

    public init(roster: [WildSpec], seed: UInt64) {
        self.roster = roster
        rng = SplitMix64(seed: seed)
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

    /// A wild Pokémon to spawn this step, if one is due and there is room.
    public mutating func spawn(dt: Double, wildCount: Int) -> WildSpec? {
        guard isPlaying, !roster.isEmpty else { return nil }
        nextSpawnIn -= dt
        guard nextSpawnIn <= 0, wildCount < Self.maxWild else { return nil }
        nextSpawnIn = random(in: Self.spawnInterval)
        return roster[min(Int(rng.unit() * Double(roster.count)), roster.count - 1)]
    }

    public mutating func wildLifetime() -> Double {
        random(in: Self.lifetime)
    }

    /// Decides at the moment of a hit whether the Pokémon will be caught and how often the ball wobbles first.
    public mutating func rollCatch() -> (caught: Bool, wobbles: Int) {
        let caught = rng.unit() < catchChance
        let wobbles = 1 + min(Int(rng.unit() * 3), 2)
        return (caught, wobbles)
    }

    public mutating func randomUnit() -> Double {
        rng.unit()
    }

    public mutating func recordHit() {
        score += Self.hitPoints
    }

    public mutating func recordCatch(_ record: CatchRecord) {
        score += Self.catchPoints
        catches.append(record)
    }

    /// How many of `catches` can still become pets without exceeding `cap`.
    public static func keepable(_ catches: [CatchRecord], ownPetCount: Int, cap: Int) -> Int {
        max(0, min(catches.count, cap - ownPetCount))
    }

    private mutating func random(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + rng.unit() * (range.upperBound - range.lowerBound)
    }
}
