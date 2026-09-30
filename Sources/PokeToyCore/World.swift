import CoreGraphics

/// A horizontal segment a pet can stand on (AppKit global coordinates).
public struct Surface: Equatable, Sendable {
    public enum Kind: Sendable { case floor, window }

    /// Window number for window tops; negative for screen floors.
    public let id: Int
    public let minX: CGFloat
    public let maxX: CGFloat
    public let y: CGFloat
    public let kind: Kind

    public init(id: Int, minX: CGFloat, maxX: CGFloat, y: CGFloat, kind: Kind) {
        self.id = id
        self.minX = minX
        self.maxX = maxX
        self.y = y
        self.kind = kind
    }

    public var width: CGFloat { maxX - minX }
    public var midX: CGFloat { (minX + maxX) / 2 }
    public func contains(x: CGFloat) -> Bool { x >= minX && x <= maxX }
    public func distance(toX x: CGFloat) -> CGFloat { contains(x: x) ? 0 : min(abs(x - minX), abs(x - maxX)) }
}

public struct ScreenInfo: Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// An on-screen window from `CGWindowListCopyWindowInfo`, bounds in CoreGraphics global coordinates (top-left origin).
public struct WindowInfo: Sendable {
    public let id: Int
    public let cgBounds: CGRect

    public init(id: Int, cgBounds: CGRect) {
        self.id = id
        self.cgBounds = cgBounds
    }
}

public struct World: Sendable {
    public let screens: [ScreenInfo]
    public let surfaces: [Surface]
    /// Left edge of each window (by window number), so pets can ride windows that move sideways.
    public let windowOrigins: [Int: CGFloat]
    /// The frontmost window of the frontmost app (pets prefer walking on it), if any.
    public let activeWindowID: Int?

    public init(screens: [ScreenInfo], surfaces: [Surface], windowOrigins: [Int: CGFloat] = [:],
                activeWindowID: Int? = nil) {
        self.screens = screens
        self.surfaces = surfaces
        self.windowOrigins = windowOrigins
        self.activeWindowID = activeWindowID
    }

    /// Builds surfaces from screens and windows ordered front to back.
    public static func build(screens: [ScreenInfo], windows: [WindowInfo], primaryScreenHeight: CGFloat,
                             activeWindowID: Int? = nil) -> World {
        var surfaces: [Surface] = []
        for (index, screen) in screens.enumerated() {
            surfaces.append(Surface(id: -(index * 2 + 1), minX: screen.frame.minX, maxX: screen.frame.maxX,
                                    y: screen.visibleFrame.minY, kind: .floor))
            if screen.visibleFrame.minY > screen.frame.minY {
                surfaces.append(Surface(id: -(index * 2 + 2), minX: screen.frame.minX, maxX: screen.frame.maxX,
                                        y: screen.frame.minY, kind: .floor))
            }
        }

        var inFront: [CGRect] = []
        var origins: [Int: CGFloat] = [:]
        for window in windows {
            origins[window.id] = window.cgBounds.minX
            let rect = CGRect(x: window.cgBounds.minX, y: primaryScreenHeight - window.cgBounds.maxY,
                              width: window.cgBounds.width, height: window.cgBounds.height)
            let top = rect.maxY
            var segments = [(rect.minX, rect.maxX)]
            for cover in inFront where cover.minY <= top && top <= cover.maxY {
                segments = subtract(segments, cover.minX, cover.maxX)
            }
            inFront.append(rect)

            for (a, b) in segments where b - a >= 40 {
                let mid = (a + b) / 2
                guard let screen = screens.first(where: {
                    $0.frame.minX <= mid && mid <= $0.frame.maxX && $0.frame.minY <= top && top <= $0.frame.maxY
                }) else { continue }
                guard top < screen.visibleFrame.maxY - 20, top > screen.visibleFrame.minY + 20 else { continue }
                surfaces.append(Surface(id: window.id, minX: max(a, screen.frame.minX), maxX: min(b, screen.frame.maxX),
                                        y: top, kind: .window))
            }
        }
        return World(screens: screens, surfaces: surfaces, windowOrigins: origins, activeWindowID: activeWindowID)
    }

    private static func subtract(_ segments: [(CGFloat, CGFloat)], _ lo: CGFloat, _ hi: CGFloat) -> [(CGFloat, CGFloat)] {
        segments.flatMap { (a, b) -> [(CGFloat, CGFloat)] in
            if hi <= a || lo >= b { return [(a, b)] }
            var pieces: [(CGFloat, CGFloat)] = []
            if lo > a { pieces.append((a, lo)) }
            if hi < b { pieces.append((hi, b)) }
            return pieces
        }
    }

    public func surface(id: Int, containingX x: CGFloat) -> Surface? {
        surfaces.first { $0.id == id && $0.contains(x: x) }
    }

    /// The highest surface under `x` whose height lies between `toY` and `fromY` (a falling body crossing it).
    public func landingSurface(x: CGFloat, fromY: CGFloat, toY: CGFloat) -> Surface? {
        surfaces.filter { $0.contains(x: x) && $0.y <= fromY && $0.y >= toY }.max { $0.y < $1.y }
    }

    /// Surfaces above `point` that a jump can reach.
    public func reachableSurfaces(from point: CGPoint, maxRise: CGFloat, maxReach: CGFloat, minWidth: CGFloat) -> [Surface] {
        surfaces.filter {
            $0.y > point.y + 20 && $0.y - point.y <= maxRise && $0.width >= minWidth && $0.distance(toX: point.x) <= maxReach
        }
    }

    public func isOnAnyScreen(_ point: CGPoint, margin: CGFloat) -> Bool {
        screens.contains { $0.frame.insetBy(dx: -margin, dy: -margin).contains(point) }
    }

    /// True if a body at `point` can still come back down onto a screen: horizontally within one
    /// (± margin) and not below it. A pet thrown high above the top is still recoverable.
    public func isRecoverable(_ point: CGPoint, margin: CGFloat) -> Bool {
        screens.contains {
            point.x >= $0.frame.minX - margin && point.x <= $0.frame.maxX + margin && point.y >= $0.frame.minY - margin
        }
    }

    /// True if `x` lies within some screen's horizontal span.
    public func isWithinScreens(x: CGFloat) -> Bool {
        screens.contains { x >= $0.frame.minX && x <= $0.frame.maxX }
    }

    /// A point near the top of the first screen, `fraction` of the way across.
    public func spawnPoint(fraction: CGFloat) -> CGPoint {
        guard let screen = screens.first else { return .zero }
        let visible = screen.visibleFrame
        return CGPoint(x: visible.minX + visible.width * fraction, y: visible.maxY - 10)
    }
}
