import CoreGraphics
import Testing
@testable import PokeToyCore

@Suite struct SpriteSheetTests {
    let info = AnimInfo(name: "Walk", frameWidth: 4, frameHeight: 4, durations: [2, 4], sourceName: "Walk")

    @Test func slicesEightDirections() throws {
        // Row 2 (Right), column 1: pixel (1, 2) inside that frame.
        let sheet = makeSheet(width: 8, height: 32, opaquePixels: [(4 + 1, 2 * 4 + 2)])
        let anim = try SpriteSheet.slice(sheet, info: info)
        #expect(anim.frames.count == 8)
        #expect(anim.frames.allSatisfy { $0.count == 2 })
        let frame = anim.frames(facing: .right)[1]
        #expect(frame.image.width == 4 && frame.image.height == 4)
        #expect(frame.mask.isOpaque(x: 1, y: 2))
        #expect(!frame.mask.isOpaque(x: 0, y: 0))
        #expect(!anim.frames(facing: .down)[1].mask.isOpaque(x: 1, y: 2))
    }

    @Test func singleRowSheetIsUsedForEveryDirection() throws {
        let sheet = makeSheet(width: 8, height: 4, opaquePixels: [(0, 3)])
        let anim = try SpriteSheet.slice(sheet, info: info)
        #expect(anim.frames.count == 1)
        #expect(anim.frames(facing: .left)[0].mask.isOpaque(x: 0, y: 3))
        #expect(anim.footPadding(facing: .upLeft) == 0)
    }

    @Test func truncatesToFramesActuallyPresent() throws {
        let long = AnimInfo(name: "Idle", frameWidth: 4, frameHeight: 4, durations: [1, 1, 1, 1], sourceName: "Idle")
        let anim = try SpriteSheet.slice(makeSheet(width: 8, height: 32, opaquePixels: []), info: long)
        #expect(anim.durations == [1, 1])
        #expect(anim.frames(facing: .down).count == 2)
    }

    @Test func footPaddingIsSpaceBelowLowestOpaquePixel() throws {
        // Down row: lowest opaque pixel at y = 1 in frame 0, y = 2 in frame 1 -> padding 4 - 1 - 2 = 1.
        let sheet = makeSheet(width: 8, height: 32, opaquePixels: [(0, 1), (4, 2)])
        let anim = try SpriteSheet.slice(sheet, info: info)
        #expect(anim.footPadding(facing: .down) == 1)
        #expect(anim.footPadding(facing: .up) == 0)  // fully transparent row
    }

    @Test func rejectsSheetSmallerThanOneFrame() {
        #expect(throws: SpriteSheetError.self) {
            try SpriteSheet.slice(makeSheet(width: 2, height: 2, opaquePixels: []), info: info)
        }
    }

    @Test func maskOutOfBoundsIsTransparent() throws {
        let anim = try SpriteSheet.slice(makeSheet(width: 8, height: 32, opaquePixels: [(0, 0)]), info: info)
        let mask = anim.frames(facing: .down)[0].mask
        #expect(mask.isOpaque(x: 0, y: 0))
        #expect(!mask.isOpaque(x: -1, y: 0))
        #expect(!mask.isOpaque(x: 4, y: 0))
        #expect(mask.lowestOpaqueRow == 0)
    }
}
