import Foundation
import Testing
@testable import PokeToyCore

@Suite struct SpriteStoreTests {
    let anims = [TestAnim(name: "Walk"), TestAnim(name: "Idle"), TestAnim(name: "Hop", copyOf: "Walk")]

    /// A fake SpriteCollab checkout served through file:// URLs.
    func makeRemote() throws -> URL {
        let remote = makeTempDirectory()
        try writeSpriteDirectory(at: remote.appendingPathComponent("sprite/0025"), anims: anims)
        try writeSpriteDirectory(at: remote.appendingPathComponent("sprite/0025/0000/0001"), anims: anims)
        let tracker = #"{"0025": {"name": "Pikachu", "sprite_complete": 2, "subgroups": {}}}"#
        try Data(tracker.utf8).write(to: remote.appendingPathComponent("tracker.json"))
        return remote
    }

    @Test func downloadsAndCachesSprites() async throws {
        let remote = try makeRemote()
        let cache = makeTempDirectory()
        let store = SpriteStore(cacheDirectory: cache, remoteBase: remote)
        let dir = try await store.spriteDirectory(for: "0025/0000/0001")
        #expect(dir.path.hasPrefix(cache.path))
        #expect(SpriteStore.isComplete(dir))
        #expect(try SpriteSet(directory: dir).animation(.react).info.name == "Hop")

        try FileManager.default.removeItem(at: remote)  // now offline
        let again = try await store.spriteDirectory(for: "0025/0000/0001")
        #expect(again == dir)
    }

    @Test func prefersBundledSpritesOverNetwork() async throws {
        let bundle = makeTempDirectory()
        try writeSpriteDirectory(at: bundle.appendingPathComponent("0025"), anims: anims)
        let store = SpriteStore(cacheDirectory: makeTempDirectory(),
                                remoteBase: URL(fileURLWithPath: "/nonexistent-remote"), bundledSprites: bundle)
        let dir = try await store.spriteDirectory(for: "0025")
        #expect(dir.standardizedFileURL == bundle.appendingPathComponent("0025").standardizedFileURL)
    }

    @Test func failsWhenNothingIsAvailable() async {
        let store = SpriteStore(cacheDirectory: makeTempDirectory(), remoteBase: URL(fileURLWithPath: "/nonexistent-remote"))
        await #expect(throws: (any Error).self) { try await store.spriteDirectory(for: "0001") }
    }

    @Test func repairsPartialCache() async throws {
        let remote = try makeRemote()
        let cache = makeTempDirectory()
        let store = SpriteStore(cacheDirectory: cache, remoteBase: remote)
        let dir = try await store.spriteDirectory(for: "0025")

        // Interrupted download: sheets present, AnimData.xml missing.
        try FileManager.default.removeItem(at: dir.appendingPathComponent("AnimData.xml"))
        #expect(!SpriteStore.isComplete(dir))
        _ = try await store.spriteDirectory(for: "0025")
        #expect(SpriteStore.isComplete(dir))

        // AnimData.xml present but a sheet missing.
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Idle-Anim.png"))
        #expect(!SpriteStore.isComplete(dir))
        _ = try await store.spriteDirectory(for: "0025")
        #expect(SpriteStore.isComplete(dir))
    }

    @Test func catalogIsCachedAndUsedWhenOffline() async throws {
        let remote = try makeRemote()
        let cache = makeTempDirectory()
        let store = SpriteStore(cacheDirectory: cache, remoteBase: remote)
        #expect(try await store.catalog() == [CatalogEntry(path: "0025", displayName: "Pikachu", isComplete: true)])
        #expect(FileManager.default.fileExists(atPath: cache.appendingPathComponent("tracker.json").path))

        try FileManager.default.removeItem(at: remote)
        #expect(try await store.catalog(forceRefresh: true).count == 1)
    }

    @Test func catalogFailsWithoutNetworkOrCache() async {
        let store = SpriteStore(cacheDirectory: makeTempDirectory(), remoteBase: URL(fileURLWithPath: "/nonexistent-remote"))
        await #expect(throws: (any Error).self) { try await store.catalog() }
    }
}
