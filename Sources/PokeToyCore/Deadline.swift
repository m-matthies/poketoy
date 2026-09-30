/// Runs `operation`, giving up with `SpriteStoreError.timedOut` after `seconds`.
public func withDeadline<T: Sendable>(seconds: Double,
                                      _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw SpriteStoreError.timedOut
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw SpriteStoreError.timedOut }
        return first
    }
}
