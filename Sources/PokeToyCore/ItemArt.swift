import CoreGraphics
import Foundation

public enum ItemKind: String, CaseIterable, Sendable {
    case apple, oranBerry, pokeBall

    public var isTreat: Bool { self != .pokeBall }
}

/// Pixel art for items, drawn from text grids so no asset files are needed.
public enum ItemArt {
    public static let size = 12

    static let palette: [Character: (UInt8, UInt8, UInt8)] = [
        "K": (24, 20, 28), "R": (224, 48, 56), "r": (150, 24, 40), "W": (248, 248, 248),
        "H": (255, 255, 255), "G": (72, 168, 72), "B": (120, 80, 40), "b": (64, 120, 232),
        "d": (32, 64, 160),
    ]

    static let grids: [ItemKind: [String]] = [
        .apple: [
            ".....BG.....",
            ".....BGG....",
            "...KKBKKK...",
            "..KRRRRRRK..",
            ".KRHRRRRRRK.",
            ".KRHRRRRRRK.",
            ".KRRRRRRRrK.",
            ".KRRRRRRRrK.",
            ".KRRRRRRrrK.",
            "..KRRRrrrK..",
            "...KKrrKK...",
            ".....KK.....",
        ],
        .oranBerry: [
            ".....GG.....",
            "....GGBG....",
            "...KKKBKK...",
            "..KbbbbbbK..",
            ".KbHbbbbbbK.",
            ".KbHbbbbbbK.",
            ".KbbbbbbbdK.",
            ".KbbbbbbddK.",
            ".KbbbbbdddK.",
            "..KbbbdddK..",
            "...KKKKK....",
            "............",
        ],
        .pokeBall: [
            "....KKKK....",
            "..KKRRRRKK..",
            ".KRHRRRRRRK.",
            ".KRRRRRRRRK.",
            "KRRRRKKRRRRK",
            "KKKKKWWKKKKK",
            "KWWWKWWKWWWK",
            ".KWWWKKWWWK.",
            ".KWWWWWWWWK.",
            "..KKWWWWKK..",
            "....KKKK....",
            "............",
        ],
    ]

    private static let cache: [ItemKind: SpriteFrame] = Dictionary(
        uniqueKeysWithValues: ItemKind.allCases.map { ($0, render(grids[$0]!)) })

    /// The item's image and opacity mask.
    public static func frame(for kind: ItemKind) -> SpriteFrame {
        cache[kind]!
    }

    static func render(_ rows: [String]) -> SpriteFrame {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        var opaque = [Bool](repeating: false, count: size * size)
        for (y, row) in rows.prefix(size).enumerated() {
            for (x, symbol) in row.prefix(size).enumerated() {
                guard let (r, g, b) = palette[symbol] else { continue }
                let i = (y * size + x) * 4
                bytes[i] = r
                bytes[i + 1] = g
                bytes[i + 2] = b
                bytes[i + 3] = 255
                opaque[y * size + x] = true
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return SpriteFrame(image: image, mask: AlphaMask(width: size, height: size, opaque: opaque))
    }
}
