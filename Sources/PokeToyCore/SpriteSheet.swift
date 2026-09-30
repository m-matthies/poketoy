import CoreGraphics

/// Per-pixel opacity of one frame. Row 0 is the top row.
public struct AlphaMask: Sendable {
    public let width: Int
    public let height: Int
    let opaque: [Bool]

    public func isOpaque(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return opaque[y * width + x]
    }

    /// The lowest row (counted from the top) that contains an opaque pixel.
    public var lowestOpaqueRow: Int? {
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in 0..<width where opaque[y * width + x] { return y }
        }
        return nil
    }
}

public struct SpriteFrame: @unchecked Sendable {
    public let image: CGImage
    public let mask: AlphaMask
}

public struct SpriteAnimation: @unchecked Sendable {
    public let info: AnimInfo
    /// Durations (1/60 s ticks) for the frames actually present in the sheet.
    public let durations: [Int]
    /// `frames[row][index]`; either 8 rows (one per `Direction`) or 1 row shared by all directions.
    public let frames: [[SpriteFrame]]
    let footPaddings: [Int]

    public func frames(facing: Direction) -> [SpriteFrame] {
        frames[frames.count == 8 ? facing.rawValue : 0]
    }

    /// Transparent rows below the character's lowest pixel; used to put the feet on the ground.
    public func footPadding(facing: Direction) -> Int {
        footPaddings[footPaddings.count == 8 ? facing.rawValue : 0]
    }
}

public enum SpriteSheetError: Error {
    case tooSmall
}

public enum SpriteSheet {
    public static func slice(_ sheet: CGImage, info: AnimInfo) throws -> SpriteAnimation {
        let fw = info.frameWidth, fh = info.frameHeight
        let columns = sheet.width / fw
        let sheetRows = sheet.height / fh
        guard columns >= 1, sheetRows >= 1 else { throw SpriteSheetError.tooSmall }
        let rows = sheetRows >= 8 ? 8 : 1
        let count = min(columns, info.durations.count)
        let alpha = alphaChannel(of: sheet)

        var frames: [[SpriteFrame]] = []
        var paddings: [Int] = []
        for row in 0..<rows {
            var rowFrames: [SpriteFrame] = []
            var lowest: Int?
            for column in 0..<count {
                var opaque = [Bool](repeating: false, count: fw * fh)
                for y in 0..<fh {
                    let sheetRowStart = (row * fh + y) * sheet.width + column * fw
                    for x in 0..<fw { opaque[y * fw + x] = alpha[sheetRowStart + x] > 0 }
                }
                let mask = AlphaMask(width: fw, height: fh, opaque: opaque)
                if let low = mask.lowestOpaqueRow { lowest = max(lowest ?? low, low) }
                let rect = CGRect(x: column * fw, y: row * fh, width: fw, height: fh)
                guard let image = sheet.cropping(to: rect) else { throw SpriteSheetError.tooSmall }
                rowFrames.append(SpriteFrame(image: image, mask: mask))
            }
            frames.append(rowFrames)
            paddings.append(lowest.map { fh - 1 - $0 } ?? 0)
        }
        return SpriteAnimation(info: info, durations: Array(info.durations.prefix(count)),
                               frames: frames, footPaddings: paddings)
    }

    /// Alpha values of every pixel, row-major with row 0 at the top.
    static func alphaChannel(of image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
    }
}
