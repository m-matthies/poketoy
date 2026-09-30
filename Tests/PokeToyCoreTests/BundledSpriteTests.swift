import Foundation
import Testing
@testable import PokeToyCore

@Suite struct BundledSpriteTests {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Sprites/0025")

    @Test(arguments: Starters.all.map(\.path)) func everyStarterIsBundled(path: String) throws {
        let resources = directory.deletingLastPathComponent().deletingLastPathComponent()
        let sprites = resources.appendingPathComponent("Sprites/\(path)")
        #expect(SpriteStore.isComplete(sprites))
        #expect((try? SpriteSet(directory: sprites)) != nil)
        let normal = resources.appendingPathComponent("Portraits/\(path)/Normal.png")
        #expect(FileManager.default.fileExists(atPath: normal.path))
    }

    @Test func bundledPikachuIsComplete() throws {
        #expect(SpriteStore.isComplete(directory))
        let set = try SpriteSet(directory: directory)
        #expect(set.animation(.walk).info.name == "Walk")
        #expect(set.animation(.sleep).info.name == "Sleep")
        #expect(set.animation(.react).info.name == "Hop")
        #expect(set.animation(.dangle).info.name == "Hurt")
        #expect(set.animation(.eat).info.name == "Eat")
        #expect(set.animation(.greet).info.name == "Nod")
        #expect(set.animation(.attack).info.name == "Attack")
        #expect(set.animation(.sad).info.name == "Cringe")
        #expect(set.animation(.sit).info.name == "Sit")
        #expect(set.animation(.wake).info.name == "Wake")
        #expect(set.animation(.walk).frames.count == 8)
        #expect(set.animation(.sleep).frames.count == 1)
        for kind in PetAnim.allCases {
            let animation = set.animation(kind)
            // Most sheets have one row per direction; some (e.g. Sleep) have a single shared row.
            #expect(animation.frames.count == 8 || animation.frames.count == 1, "\(kind) has \(animation.frames.count) rows")
            #expect(!animation.frames(facing: .right).isEmpty)
        }
    }
}

@Suite struct BundledCollectionTests {
    let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources")

    var bundled: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: resources.appendingPathComponent("Sprites").path)) ?? [])
            .filter { $0.allSatisfy(\.isNumber) }.sorted()
    }

    @Test func theCompleteCollectionIsBundled() throws {
        #expect(bundled.count >= 200)
        for path in bundled {
            #expect(SpriteStore.isComplete(resources.appendingPathComponent("Sprites/\(path)")), "\(path)")
            let normal = resources.appendingPathComponent("Portraits/\(path)/Normal.png")
            #expect(FileManager.default.fileExists(atPath: normal.path), "\(path) has no Normal portrait")
        }
    }

    @Test func everyBundledPokemonHasANameAndCredits() throws {
        let names = try SpriteStore.bundledNames(in: resources.appendingPathComponent("Sprites"))
        let credits = try String(contentsOf: resources.appendingPathComponent("CREDITS.md"), encoding: .utf8)
        #expect(credits.contains("CC BY-NC 4.0") && credits.contains("PMDCollab SpriteCollab"))
        #expect(!credits.contains("<@"))  // no Discord ids
        for path in bundled {
            #expect(names[path] != nil, "\(path) has no name")
            #expect(credits.contains("| \(path) |"), "\(path) isn't credited")
        }
    }
}

@Suite struct BundledCatalogTests {
    let anims = [TestAnim(name: "Walk"), TestAnim(name: "Idle")]

    func bundle() throws -> URL {
        let bundle = makeTempDirectory()
        try writeSpriteDirectory(at: bundle.appendingPathComponent("0004"), anims: anims)
        try Data(#"{"0004": "Charmander"}"#.utf8).write(to: bundle.appendingPathComponent("names.json"))
        return bundle
    }

    @Test func offlineWithoutACatalogTheBundledPokemonAreTheCatalog() async throws {
        let store = SpriteStore(cacheDirectory: makeTempDirectory(), remoteBase: URL(fileURLWithPath: "/nonexistent-remote"),
                                bundledSprites: try bundle())
        let catalog = try await store.catalog()
        #expect(catalog == [CatalogEntry(path: "0004", displayName: "Charmander", isComplete: true)])
    }

    @Test func bundledSpritesDontCountAsDownloads() async throws {
        let cache = makeTempDirectory()
        try writeSpriteDirectory(at: cache.appendingPathComponent("sprite/0133"), anims: anims)
        let store = SpriteStore(cacheDirectory: cache, remoteBase: URL(fileURLWithPath: "/nonexistent-remote"),
                                bundledSprites: try bundle())
        #expect(await store.cachedSpritePaths() == ["0004", "0133"])
        #expect(await store.downloadedSpritePaths() == ["0133"])
    }

    @Test func pokedexSeenSpeciesAreRemembered() throws {
        var settings = Settings.default
        settings.seen = ["0016", "0133"]
        let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(again.seen == ["0016", "0133"])
        #expect(try JSONDecoder().decode(Settings.self, from: Data(#"{"scale": 2}"#.utf8)).seen.isEmpty)
    }
}
