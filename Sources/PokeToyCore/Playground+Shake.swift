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
    /// Longer than two missed 5 Hz samples: the window was resting.
    static let shakeRest = 0.45

    /// Shaking a window (or yanking it very fast) throws the pets standing on it off; slower moves carry them,
    /// and they look the way it's going.
    mutating func shakeRules(world: World) {
        // Real time between window-list snapshots, so an app stall doesn't make a drag look fast.
        let now = world.timestamp ?? clock
        for (id, origin) in world.windowOrigins {
            var motion = windowMotion[id] ?? WindowMotion(origin: origin, changedAt: now)
            let delta = origin - motion.origin
            if abs(delta) >= 1 {
                if now - motion.changedAt > Self.shakeRest {
                    // It was resting: an earlier move doesn't count toward a shake.
                    motion.direction = 0
                    motion.turns = []
                }
                let speed = abs(delta) / CGFloat(max(now - motion.changedAt, 1.0 / 60))
                let direction: CGFloat = delta > 0 ? 1 : -1
                if motion.direction != 0, direction != motion.direction, abs(delta) >= Self.shakeMinMove {
                    motion.turns.append(now)
                }
                motion.turns.removeAll { now - $0 > Self.shakeWindow }
                motion.direction = direction
                motion.origin = origin
                motion.changedAt = now
                // Only a window the user is dragging shakes pets off (not tiling or zoom animations).
                if mouseDown, motion.turns.count >= Self.shakeTurns || speed > Self.flingSpeed {
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
        let riders = pets.indices.filter { pets[$0].visible && pets[$0].body.isGrounded && pets[$0].body.surfaceID == id }
        // One speed for everyone (enough for the one furthest from the edge), so they fly together without colliding.
        let speed = riders.map { i -> CGFloat in
            let x = pets[i].body.position.x
            let toEdge = world.surface(id: id, containingX: x).map { direction > 0 ? $0.maxX - x : x - $0.minX } ?? 0
            return (toEdge + pets[i].halfWidth + 20) / airtime
        }.max().map { max(250, $0) } ?? 250
        for i in riders {
            pets[i].handle(.knocked(velocity: CGVector(dx: speed * direction, dy: lift)))
            if pets[i].role == .own { feel(.surprised, i) }
        }
    }
}
