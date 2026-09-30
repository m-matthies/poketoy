import CoreGraphics
import Foundation

extension Playground {
    static let knockSpeed: CGFloat = 250

    /// Thrown pets knock over the pets they hit. (Walkers meeting each other: see `passingRules`.)
    mutating func collisionRules(world: World) {
        let own = pets.indices.filter { pets[$0].role == .own && pets[$0].visible }

        for x in own {
            for y in own where y != x {
                guard thrownByUser.contains(pets[x].id), case .fall(_, true) = pets[x].brain.state,
                      hypot(pets[x].body.velocity.dx, pets[x].body.velocity.dy) > Self.knockSpeed else { continue }
                let targetState = pets[y].brain.state
                guard targetState != .dragged, targetState != .held else { continue }
                let key = Friendships.key(pets[x].id, pets[y].id)
                guard (knockCooldowns[key] ?? 0) <= 0, pets[x].bodyRect.intersects(pets[y].bodyRect) else { continue }
                // Push along the throw; only a near-vertical drop pushes away by position.
                let vx = pets[x].body.velocity.dx
                let direction: CGFloat = abs(vx) > 50 ? (vx > 0 ? 1 : -1)
                    : (pets[y].body.position.x >= pets[x].body.position.x ? 1 : -1)
                pets[y].handle(.knocked(velocity: CGVector(dx: 220 * direction, dy: 380)))
                feel(.pain, y)
                pets[x].body.velocity.dx = -pets[x].body.velocity.dx * 0.5
                knockCooldowns[key] = 0.5
            }
        }

    }
}
