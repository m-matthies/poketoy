import CoreGraphics
import Foundation

/// The Poké Ball animations, as a pure timeline: returning a pet to its ball, and letting it out.
public enum BallAnimation {
    public enum Kind: Sendable {
        /// A ball pops up beside the pet; the pet turns red and shrinks into it; the ball wobbles, clicks, fades.
        case recall
        /// A ball drops in and bounces, bursts open in a white flash; the pet grows out glowing white; the ball fades.
        case release
    }

    /// What to draw at a moment of the animation.
    public struct Frame: Equatable, Sendable {
        /// The pet's size, 0…1.
        public var petScale: CGFloat = 1
        /// How far the pet has moved from its spot into the ball, 0…1.
        public var toBall: CGFloat = 0
        /// How strongly the pet is tinted (red when returning, white when coming out), 0…1.
        public var tint: CGFloat = 0
        public var tintIsRed = false
        public var ballScale: CGFloat = 1
        public var ballAlpha: CGFloat = 1
        /// Tilt of the wobbling ball, in radians.
        public var ballAngle: CGFloat = 0
        /// Height above its resting spot of a ball still falling in, in points.
        public var ballDrop: CGFloat = 0
        /// The white burst of a ball opening, 0…1 (0: none).
        public var burst: CGFloat = 0
    }

    public static func duration(_ kind: Kind) -> Double {
        kind == .recall ? 1.1 : 1.0
    }

    public static func frame(_ kind: Kind, at t: Double) -> Frame {
        kind == .recall ? recall(t) : release(t)
    }

    private static func recall(_ t: Double) -> Frame {
        var f = Frame()
        f.tintIsRed = true
        f.ballScale = ease(progress(t, 0, 0.15))  // pops up
        let suck = ease(progress(t, 0.15, 0.55))
        f.tint = min(1, CGFloat(progress(t, 0.05, 0.3)))
        f.petScale = 1 - suck
        f.toBall = suck
        let wobble = progress(t, 0.55, 0.9)
        if wobble > 0 && wobble < 1 { f.ballAngle = CGFloat(sin(wobble * .pi * 4)) * 0.35 * CGFloat(1 - wobble * 0.5) }
        f.ballAlpha = 1 - CGFloat(progress(t, 0.9, 1.1))
        return f
    }

    private static func release(_ t: Double) -> Frame {
        var f = Frame()
        let fall = progress(t, 0, 0.25)
        f.ballDrop = 120 * CGFloat(1 - fall * fall)  // falls in, speeding up
        let bounce = progress(t, 0.25, 0.3)
        if fall >= 1 { f.ballDrop = bounce < 1 ? 12 * CGFloat(sin(bounce * .pi)) : 0 }  // a little bounce
        let open = progress(t, 0.3, 0.55)
        f.burst = open > 0 && open < 1 ? CGFloat(open) : 0
        let grow = ease(progress(t, 0.35, 0.75))
        f.petScale = grow
        f.tint = t < 0.35 ? 1 : 1 - CGFloat(progress(t, 0.6, 0.9))
        f.ballAlpha = 1 - CGFloat(progress(t, 0.75, 1.0))
        return f
    }

    /// Where `t` is between `from` and `to`, 0…1.
    private static func progress(_ t: Double, _ from: Double, _ to: Double) -> Double {
        min(1, max(0, (t - from) / (to - from)))
    }

    private static func ease(_ x: Double) -> CGFloat {
        CGFloat(x * x * (3 - 2 * x))
    }
}
