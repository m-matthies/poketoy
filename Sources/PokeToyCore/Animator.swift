/// Tracks which frame of the current animation is showing.
public struct Animator: Sendable {
    public private(set) var kind: PetAnim = .idle
    public private(set) var frameIndex = 0
    /// True once a non-looping animation has shown its last frame for its full duration.
    public private(set) var finished = false
    private var elapsed: Double = 0  // 1/60 s ticks spent on the current frame

    public init() {}

    /// Switches to `kind`, restarting only if it differs from the current animation.
    public mutating func play(_ kind: PetAnim) {
        guard kind != self.kind else { return }
        self.kind = kind
        restart()
    }

    public mutating func restart() {
        frameIndex = 0
        elapsed = 0
        finished = false
    }

    public mutating func advance(dt: Double, durations: [Int]) {
        guard !durations.isEmpty, !finished else { return }
        frameIndex = min(frameIndex, durations.count - 1)
        elapsed += dt * 60
        while true {
            let length = Double(max(durations[frameIndex], 1))
            guard elapsed >= length else { return }
            elapsed -= length
            if frameIndex + 1 < durations.count {
                frameIndex += 1
            } else if kind.loops {
                frameIndex = 0
            } else {
                finished = true
                return
            }
        }
    }
}
