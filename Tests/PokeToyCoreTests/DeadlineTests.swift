import Foundation
import Testing
@testable import PokeToyCore

@Suite struct DeadlineTests {
    @Test func returnsTheResultWhenFast() async throws {
        let value = try await withDeadline(seconds: 5) { 42 }
        #expect(value == 42)
    }

    @Test func throwsWhenTooSlow() async {
        let start = Date()
        await #expect(throws: SpriteStoreError.timedOut) {
            try await withDeadline(seconds: 0.1) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
        #expect(Date().timeIntervalSince(start) < 2)
    }
}
