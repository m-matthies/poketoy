import CoreGraphics

/// Per-animation frame timing and size for one Pokémon — what the simulation needs from its sprites.
public struct PetMetrics: Equatable, Sendable {
    public var durations: [PetAnim: [Int]]
    /// Frame size in sprite pixels.
    public var frameSizes: [PetAnim: CGSize]

    public init(durations: [PetAnim: [Int]], frameSizes: [PetAnim: CGSize]) {
        self.durations = durations
        self.frameSizes = frameSizes
    }

    public init(sprites: SpriteSet) {
        var durations: [PetAnim: [Int]] = [:]
        var sizes: [PetAnim: CGSize] = [:]
        for kind in PetAnim.allCases {
            let animation = sprites.animation(kind)
            durations[kind] = animation.durations
            sizes[kind] = CGSize(width: animation.info.frameWidth, height: animation.info.frameHeight)
        }
        self.init(durations: durations, frameSizes: sizes)
    }

    /// The same size and timing for every animation (tests and fallbacks).
    public static func uniform(width: CGFloat = 32, height: CGFloat = 40, durations: [Int] = [4, 4]) -> PetMetrics {
        PetMetrics(durations: Dictionary(uniqueKeysWithValues: PetAnim.allCases.map { ($0, durations) }),
                   frameSizes: Dictionary(uniqueKeysWithValues: PetAnim.allCases.map { ($0, CGSize(width: width, height: height)) }))
    }
}
