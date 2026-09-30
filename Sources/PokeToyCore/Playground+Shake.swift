import CoreGraphics
import Foundation

/// How a window has been moving sideways (from successive `World.windowOrigins`).
struct WindowMotion: Sendable {
    var origin: CGFloat
    var changedAt: Double
    var direction: CGFloat = 0
    var turns: [Double] = []
}

extension Playground {
    static let shakeTurns = 2
    static let shakeWindow = 0.8
    static let shakeMinMove: CGFloat = 30
    static let flingSpeed: CGFloat = 1800

    /// Shaking a window (or yanking it very fast) throws the pets standing on it off; slower moves carry them,
    /// and they look the way it's going.
    mutating func shakeRules(world: World) {
        for (id, origin) in world.windowOrigins {
            var motion = windowMotion[id] ?? WindowMotion(origin: origin, changedAt: clock)
            let delta = origin - motion.origin
            if abs(delta) >= 1 {
                let speed = abs(delta) / CGFloat(max(clock - motion.changedAt, 1.0 / 60))
                let direction: CGFloat = delta > 0 ? 1 : -1
                if motion.direction != 0, direction != motion.direction, abs(delta) >= Self.shakeMinMove {
                    motion.turns.append(clock)
                }
                motion.turns.removeAll { clock - $0 > Self.shakeWindow }
                motion.direction = direction
                motion.origin = origin
                motion.changedAt = clock
                if motion.turns.count >= Self.shakeTurns || speed > Self.flingSpeed {
                    motion.turns = []
                    shakeOff(window: id, direction: direction, world: world)
                } else {
                    for i in pets.indices where pets[i].visible && pets[i].body.surfaceID == id {
                        pets[i].brain.look(toward: direction)
                    }
                }
            }
            windowMotion[id] = motion
        }
        windowMotion = windowMotion.filter { world.windowOrigins[$0.key] != nil }
    }

    private mutating func shakeOff(window id: Int, direction: CGFloat, world: World) {
        let lift: CGFloat = 350
        let airtime = 2 * lift / Physics.gravity
        for i in pets.indices where pets[i].visible && pets[i].body.isGrounded && pets[i].body.surfaceID == id {
            // Fling it far enough sideways to clear the window's edge in the direction it was moving.
            let x = pets[i].body.position.x
            let toEdge = world.surface(id: id, containingX: x).map { direction > 0 ? $0.maxX - x : x - $0.minX } ?? 0
            let speed = max(250, (toEdge + pets[i].halfWidth + 20) / airtime)
            pets[i].handle(.knocked(velocity: CGVector(dx: speed * direction, dy: lift)))
            if pets[i].role == .own { feel(.surprised, i) }
        }
    }
}
