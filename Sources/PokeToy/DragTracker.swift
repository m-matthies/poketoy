import AppKit

/// Turns a press-and-drag on a floating panel into an offset and a release velocity.
struct DragTracker {
    private var offset = CGVector.zero
    private var samples: [(time: CFTimeInterval, point: CGPoint)] = []

    mutating func begin(at point: CGPoint, objectPosition: CGPoint) {
        offset = CGVector(dx: objectPosition.x - point.x, dy: objectPosition.y - point.y)
        samples = [(CACurrentMediaTime(), point)]
    }

    /// Records the mouse at `point` and returns where the dragged object should be.
    mutating func move(to point: CGPoint) -> CGPoint {
        let now = CACurrentMediaTime()
        samples.append((now, point))
        samples.removeAll { $0.time < now - 0.1 }
        return CGPoint(x: point.x + offset.dx, y: point.y + offset.dy)
    }

    /// The mouse velocity over the last 0.1 s, limited to `cap` points per second.
    func releaseVelocity(cap: CGFloat) -> CGVector {
        let now = CACurrentMediaTime()
        let recent = samples.filter { $0.time >= now - 0.1 }
        guard let first = recent.first, let last = recent.last, last.time - first.time > 0.01 else { return .zero }
        let elapsed = CGFloat(last.time - first.time)
        var velocity = CGVector(dx: (last.point.x - first.point.x) / elapsed, dy: (last.point.y - first.point.y) / elapsed)
        let speed = hypot(velocity.dx, velocity.dy)
        if speed > cap {
            velocity.dx *= cap / speed
            velocity.dy *= cap / speed
        }
        return velocity
    }
}
