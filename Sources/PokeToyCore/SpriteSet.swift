import CoreGraphics
import Foundation
import ImageIO

public enum SpriteSetError: Error {
    case missingAnimation(PetAnim)
}

/// Every `PetAnim` for one Pokémon, loaded from a directory holding `AnimData.xml` and `*-Anim.png` sheets.
public final class SpriteSet: @unchecked Sendable {
    private let animations: [PetAnim: SpriteAnimation]

    public init(directory: URL) throws {
        let data = try AnimData(xml: Data(contentsOf: directory.appendingPathComponent("AnimData.xml")))
        var sheets: [String: CGImage] = [:]
        var result: [PetAnim: SpriteAnimation] = [:]
        for kind in PetAnim.allCases {
            for name in kind.candidates {
                guard let info = data.anims[name] else { continue }
                let file = "\(info.sourceName)-Anim.png"
                if sheets[file] == nil, let image = Self.loadImage(directory.appendingPathComponent(file)) {
                    sheets[file] = image
                }
                guard let sheet = sheets[file], let animation = try? SpriteSheet.slice(sheet, info: info) else { continue }
                result[kind] = animation
                break
            }
            guard result[kind] != nil else { throw SpriteSetError.missingAnimation(kind) }
        }
        animations = result
    }

    public func animation(_ kind: PetAnim) -> SpriteAnimation {
        animations[kind]!  // init guarantees every kind is present
    }

    /// Sheet files (e.g. `Walk-Anim.png`) needed to build every `PetAnim` from this AnimData.
    public static func requiredFiles(for data: AnimData) -> Set<String> {
        Set(PetAnim.allCases.compactMap { data.resolve($0.candidates) }.map { "\($0.sourceName)-Anim.png" })
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
