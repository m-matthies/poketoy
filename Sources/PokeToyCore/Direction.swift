import CoreGraphics

/// The eight facing directions, in the row order used by PMD sprite sheets.
public enum Direction: Int, CaseIterable, Sendable {
    case down, downRight, right, upRight, up, upLeft, left, downLeft

    /// Picks the sheet row that best matches a movement vector (AppKit coordinates, +y is up).
    public static func from(dx: CGFloat, dy: CGFloat) -> Direction {
        if abs(dx) < 0.001 && abs(dy) < 0.001 { return .down }
        let octant = Int((atan2(dy, dx) / (.pi / 4)).rounded())  // -4...4, 0 = right, counter-clockwise
        switch (octant + 8) % 8 {
        case 0: return .right
        case 1: return .upRight
        case 2: return .up
        case 3: return .upLeft
        case 4: return .left
        case 5: return .downLeft
        case 6: return .down
        default: return .downRight
        }
    }
}
