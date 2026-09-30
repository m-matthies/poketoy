import Foundation
import Testing
@testable import PokeToyCore

@Suite struct SpriteSetTests {
    @Test func loadsPreferredAnimations() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [
            TestAnim(name: "Walk"), TestAnim(name: "Idle", durations: [3, 3, 3]),
            TestAnim(name: "Sleep"), TestAnim(name: "Hop"), TestAnim(name: "Hurt"),
        ])
        let set = try SpriteSet(directory: dir)
        #expect(set.animation(.idle).info.name == "Idle")
        #expect(set.animation(.idle).durations == [3, 3, 3])
        #expect(set.animation(.walk).info.name == "Walk")
        #expect(set.animation(.sleep).info.name == "Sleep")
        #expect(set.animation(.react).info.name == "Hop")
        #expect(set.animation(.dangle).info.name == "Hurt")
        #expect(set.animation(.land).info.name == "Hurt")
        #expect(set.animation(.walk).frames.count == 8)
    }

    @Test func loadsSocialAnimations() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [
            TestAnim(name: "Walk"), TestAnim(name: "Idle"), TestAnim(name: "Eat"), TestAnim(name: "Nod"),
            TestAnim(name: "Attack"), TestAnim(name: "Cringe"), TestAnim(name: "Sit"), TestAnim(name: "Wake"),
            TestAnim(name: "Hop"),
        ])
        let set = try SpriteSet(directory: dir)
        #expect(set.animation(.eat).info.name == "Eat")
        #expect(set.animation(.greet).info.name == "Nod")
        #expect(set.animation(.attack).info.name == "Attack")
        #expect(set.animation(.sad).info.name == "Cringe")
        #expect(set.animation(.sit).info.name == "Sit")
        #expect(set.animation(.cheer).info.name == "Hop")
        #expect(set.animation(.wake).info.name == "Wake")
    }

    @Test func fallsBackWhenAnimationsAreMissing() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk")])
        let set = try SpriteSet(directory: dir)
        for kind in PetAnim.allCases {
            #expect(set.animation(kind).info.name == "Walk")
        }
    }

    @Test func skipsCandidateWhoseSheetIsMissing() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk"), TestAnim(name: "Idle")])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Idle-Anim.png"))
        let set = try SpriteSet(directory: dir)
        #expect(set.animation(.idle).info.name == "Walk")
    }

    @Test func followsCopyOfToTheSourceSheet() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk"), TestAnim(name: "Hop", copyOf: "Walk")])
        let set = try SpriteSet(directory: dir)
        #expect(set.animation(.react).info.name == "Hop")
        #expect(set.animation(.react).info.sourceName == "Walk")
    }

    @Test func failsWithoutIdleOrWalk() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Attack")])
        #expect(throws: SpriteSetError.self) { try SpriteSet(directory: dir) }
    }

    @Test func requiredFilesCoverEveryPetAnim() throws {
        let xml = animDataXML([
            TestAnim(name: "Walk"), TestAnim(name: "Idle"), TestAnim(name: "Hop", copyOf: "Walk"),
            TestAnim(name: "Attack"),
        ])
        let data = try AnimData(xml: Data(xml.utf8))
        #expect(SpriteSet.requiredFiles(for: data) == ["Walk-Anim.png", "Idle-Anim.png", "Attack-Anim.png"])
    }
}
