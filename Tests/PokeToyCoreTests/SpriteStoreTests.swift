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

    @Test func offlineUsesAnIncompleteCache() async throws {
        let cache = makeTempDirectory()
        let dir = cache.appendingPathComponent("sprite/0025")
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk"), TestAnim(name: "Idle"), TestAnim(name: "Eat")])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Eat-Anim.png"))
        #expect(!SpriteStore.isComplete(dir))
        #expect(SpriteStore.isUsable(dir))
        let store = SpriteStore(cacheDirectory: cache, remoteBase: URL(fileURLWithPath: "/nonexistent-remote"))
        let found = try await store.spriteDirectory(for: "0025")
        #expect(found.standardizedFileURL == dir.standardizedFileURL)
        #expect(try SpriteSet(directory: found).animation(.eat).info.name == "Idle")
    }

    @Test func offlineCacheWithoutIdleOrWalkIsNotUsed() async throws {
        let cache = makeTempDirectory()
        let dir = cache.appendingPathComponent("sprite/0025")
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk"), TestAnim(name: "Idle")])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Walk-Anim.png"))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Idle-Anim.png"))
        #expect(!SpriteStore.isUsable(dir))
        let store = SpriteStore(cacheDirectory: cache, remoteBase: URL(fileURLWithPath: "/nonexistent-remote"))
        await #expect(throws: (any Error).self) { try await store.spriteDirectory(for: "0025") }
    }

    @Test func cachedSpritePathsListUsableDirectories() async throws {
        let cache = makeTempDirectory()
        try writeSpriteDirectory(at: cache.appendingPathComponent("sprite/0025"), anims: anims)
        try writeSpriteDirectory(at: cache.appendingPathComponent("sprite/0025/0000/0001"), anims: anims)
        let broken = cache.appendingPathComponent("sprite/0099")
        try writeSpriteDirectory(at: broken, anims: [TestAnim(name: "Walk")])
        try FileManager.default.removeItem(at: broken.appendingPathComponent("Walk-Anim.png"))
        let bundle = makeTempDirectory()
        try writeSpriteDirectory(at: bundle.appendingPathComponent("0133"), anims: anims)
        let store = SpriteStore(cacheDirectory: cache, remoteBase: URL(fileURLWithPath: "/nonexistent-remote"),
                                bundledSprites: bundle)
        #expect(await store.cachedSpritePaths() == ["0025", "0025/0000/0001", "0133"])
    }

    @Test func timeoutVariantReturnsWhenFast() async throws {
        let bundle = makeTempDirectory()
        try writeSpriteDirectory(at: bundle.appendingPathComponent("0025"), anims: anims)
        let store = SpriteStore(cacheDirectory: makeTempDirectory(), remoteBase: URL(fileURLWithPath: "/nonexistent-remote"),
                                bundledSprites: bundle)
        let dir = try await store.spriteDirectory(for: "0025", timeout: 5)
        #expect(SpriteStore.isComplete(dir))
    }

    @Test func errorsReadWell() {
        #expect(SpriteStoreError.http(status: 404, path: "x").localizedDescription == "Not found on SpriteCollab.")
        #expect(SpriteStoreError.http(status: 500, path: "x").localizedDescription == "SpriteCollab answered with HTTP 500.")
        #expect(SpriteStoreError.timedOut.localizedDescription == "SpriteCollab took too long to answer.")
    }

    func portraitRemote(_ names: [String]) throws -> URL {
        let remote = makeTempDirectory()
        let dir = remote.appendingPathComponent("portrait/0025")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names {
            try writePNG(makeSheet(width: 40, height: 40, opaquePixels: [(20, 20)]), to: dir.appendingPathComponent("\(name).png"))
        }
        return remote
    }

    @Test func portraitsFollowTheFallbackChain() async throws {
        let store = SpriteStore(cacheDirectory: makeTempDirectory(), remoteBase: try portraitRemote(["Happy", "Normal"]))
        let joyous = await store.portrait(for: "0025", emotion: .joyous)
        #expect(joyous?.lastPathComponent == "Happy.png")
        let angry = await store.portrait(for: "0025", emotion: .angry)
        #expect(angry?.lastPathComponent == "Normal.png")
    }

    @Test func missingPortraitsAreRemembered() async throws {
        let cache = makeTempDirectory()
        let remote = try portraitRemote(["Happy"])
        let store = SpriteStore(cacheDirectory: cache, remoteBase: remote)
        #expect(await store.portrait(for: "0025", emotion: .joyous)?.lastPathComponent == "Happy.png")
        #expect(FileManager.default.fileExists(atPath: cache.appendingPathComponent("portrait/0025/.missing-Joyous").path))
        try FileManager.default.removeItem(at: remote)  // offline: the cached Happy still answers
        #expect(await store.portrait(for: "0025", emotion: .joyous)?.lastPathComponent == "Happy.png")
    }

    @Test func noPortraitMeansNil() async throws {
        let store = SpriteStore(cacheDirectory: makeTempDirectory(), remoteBase: try portraitRemote([]))
        #expect(await store.portrait(for: "0025", emotion: .sad) == nil)
    }

    @Test func portraitsBackOffAfterANetworkFailure() async {
        CountingFailingProtocol.requests = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingFailingProtocol.self]
        let store = SpriteStore(cacheDirectory: makeTempDirectory(), remoteBase: URL(string: "https://example.invalid/")!,
                                session: URLSession(configuration: configuration))
        #expect(await store.portrait(for: "0025", emotion: .happy) == nil)
        let afterFirst = CountingFailingProtocol.requests
        #expect(afterFirst >= 1)
        #expect(await store.portrait(for: "0025", emotion: .sad) == nil)
        #expect(CountingFailingProtocol.requests == afterFirst)
    }
}

/// Fails every request as if offline, counting how many were made.
final class CountingFailingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
