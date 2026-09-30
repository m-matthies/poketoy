import Foundation
import Testing
@testable import PokeToyCore

@Suite struct BundledSpriteTests {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Sprites/0025")

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
