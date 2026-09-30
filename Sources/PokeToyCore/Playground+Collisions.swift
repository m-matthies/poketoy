import CoreGraphics
import Foundation

extension Playground {
    static let knockSpeed: CGFloat = 250

    /// Thrown pets knock over the pets they hit; pets walking into each other turn around.
    mutating func collisionRules(world: World) {
        let own = pets.indices.filter { pets[$0].role == .own && pets[$0].visible }

        for x in own {
            for y in own where y != x {
                guard case .fall(_, true) = pets[x].brain.state,
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
                pets[x].body.velocity.dx = -pets[x].body.velocity.dx * 0.5
                knockCooldowns[key] = 0.5
            }
        }

        for x in own.indices {
            for y in own.indices where y > x {
                let i = own[x], j = own[y]
                guard case .walk = pets[i].brain.state, case .walk = pets[j].brain.state,
                      let surface = pets[i].body.surfaceID, surface == pets[j].body.surfaceID,
                      pets[i].bodyRect.intersects(pets[j].bodyRect) else { continue }
                let toward = pets[j].body.position.x - pets[i].body.position.x
                guard pets[i].body.velocity.dx * toward > 0, pets[j].body.velocity.dx * -toward > 0 else { continue }
                for (me, other) in [(i, j), (j, i)] {
                    let away: CGFloat = pets[me].body.position.x < pets[other].body.position.x ? -1 : 1
                    let back = clampOnSurface(pets[me].body.position.x + away * 60, pet: me, world: world)
                    pets[me].perform(Script(anim: .walk, moveTo: back, end: .arrived, priority: 1))
                }
            }
        }
    }
}
