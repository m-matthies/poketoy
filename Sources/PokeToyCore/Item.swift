import CoreGraphics
import Foundation

public enum ItemEvent: Equatable, Sendable {
    case pressed
    /// Let go without dragging.
    case released
    case dragBegan
    case dragEnded(velocity: CGVector)
}

/// A treat or Poké Ball in the world. Items use the same `Physics` as pets.
public struct Item: Identifiable, Sendable {
    public enum State: Equatable, Sendable {
        case free
        /// Pressed or dragged by the user; physics is paused.
        case held
        /// A thrown Poké Ball that hasn't hit anything yet.
        case flying
        /// A Poké Ball holding a wild Pokémon; `caught` was decided when it hit.
        case wobbling(petID: UUID, wobblesLeft: Int, caught: Bool, timer: Double)
        case fading(remaining: Double)
        /// The fetch ball in a pet's mouth.
        case carried(petID: UUID)
    }

    public static let wobbleDuration = 0.6

    public let id: UUID
    public let kind: ItemKind
    public internal(set) var body: Body
    public internal(set) var state: State
    /// Seconds a treat has been lying around untouched.
    public internal(set) var age: Double = 0

    public init(id: UUID = UUID(), kind: ItemKind, body: Body, state: State = .free) {
        self.id = id
        self.kind = kind
        self.body = body
        self.state = state
    }

    /// Tilt for drawing a wobbling ball, in radians.
    public var wobbleAngle: CGFloat {
        guard case .wobbling(_, _, _, let timer) = state, body.isGrounded else { return 0 }
        return sin(CGFloat(timer / Self.wobbleDuration) * .pi * 2) * 0.35
    }
}
