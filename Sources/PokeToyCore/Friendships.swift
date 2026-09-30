import Foundation

public enum FriendshipLevel: Int, Comparable, Sendable {
    case stranger = 0, friend = 1, bestFriend = 2

    public init(points: Int) {
        self = points >= 10 ? .bestFriend : points >= 3 ? .friend : .stranger
    }

    public static func < (lhs: FriendshipLevel, rhs: FriendshipLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Friendship points per unordered pair of pets.
public struct Friendships: Equatable, Sendable {
    public private(set) var points: [String: Int]

    /// Builds from saved points, dropping malformed keys and normalizing key order.
    public init(points: [String: Int] = [:]) {
        var clean: [String: Int] = [:]
        for (key, value) in points {
            let parts = key.split(separator: "+").map(String.init)
            guard parts.count == 2, value > 0,
                  let a = UUID(uuidString: parts[0]), let b = UUID(uuidString: parts[1]), a != b else { continue }
            clean[Self.key(a, b), default: 0] += value
        }
        self.points = clean
    }

    public static func key(_ a: UUID, _ b: UUID) -> String {
        let (first, second) = a.uuidString < b.uuidString ? (a, b) : (b, a)
        return "\(first.uuidString)+\(second.uuidString)"
    }

    public func score(_ a: UUID, _ b: UUID) -> Int {
        points[Self.key(a, b)] ?? 0
    }

    public func level(_ a: UUID, _ b: UUID) -> FriendshipLevel {
        FriendshipLevel(points: score(a, b))
    }

    public mutating func add(_ a: UUID, _ b: UUID, _ amount: Int = 1) {
        guard a != b else { return }
        points[Self.key(a, b), default: 0] += amount
    }

    public mutating func remove(_ id: UUID) {
        points = points.filter { !$0.key.contains(id.uuidString) }
    }

    /// The highest-scoring partner of `id` among `candidates` that is at best-friend level.
    public func bestFriend(of id: UUID, among candidates: [UUID]) -> UUID? {
        candidates
            .filter { $0 != id && level(id, $0) == .bestFriend }
            .max { score(id, $0) < score(id, $1) }
    }
}
