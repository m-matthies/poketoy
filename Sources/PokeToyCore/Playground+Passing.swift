import CoreGraphics
import Foundation

extension Playground {
    static let playfulChance = 0.3
    static let turnBackDistance: CGFloat = 60

    /// Pets never walk through each other. A walker that reaches another pet of the same role standing ahead
    /// on its surface hops over it, turns back, or (own pets, now and then) starts playing with it.
    mutating func passingRules(dt: Double, world: World) {
        for i in pets.indices {
            let walker = pets[i]
            let vx = walker.body.velocity.dx
            guard walker.visible, vx != 0, let surfaceID = walker.body.surfaceID, walkGoal(of: i) != nil else { continue }
            let direction: CGFloat = vx > 0 ? 1 : -1
            let ahead = pets.indices.filter { j in
                j != i && pets[j].visible && pets[j].role == walker.role && pets[j].body.surfaceID == surfaceID
                    && pets[j].brain.state != .dragged
                    && (pets[j].body.position.x - walker.body.position.x) * direction > 0
                    && abs(pets[j].body.position.x - walker.body.position.x) - walker.halfWidth - pets[j].halfWidth
                        < abs(vx) * CGFloat(dt) + 2
            }
            guard let j = ahead.min(by: {
                abs(pets[$0].body.position.x - walker.body.position.x) < abs(pets[$1].body.position.x - walker.body.position.x)
            }) else { continue }
            resolveBlock(walker: i, blocker: j, direction: direction, world: world)
        }
    }

    /// Where a walking pet is heading: its wander target or its script's destination.
    private func walkGoal(of i: Int) -> CGFloat? {
        if case .walk(let target, _) = pets[i].brain.state { return target }
        if case .scripted(let script, _) = pets[i].brain.state { return script.moveTo }
        return nil
    }

    private mutating func resolveBlock(walker i: Int, blocker j: Int, direction: CGFloat, world: World) {
        let scripted = pets[i].brain.script != nil
        if pets[i].role == .own, game == nil, !scripted, pets[j].brain.isFree,
           !inMoment(pets[i].id), !inMoment(pets[j].id), rng.unit() < Self.playfulChance {
            startMoment(i, j, kind: rng.unit() < 0.5 ? .tag : .playFight)  // turn the bump into play
            return
        }

        let blockerX = pets[j].body.position.x
        let goalIsPast = walkGoal(of: i).map { ($0 - blockerX) * direction > 0 } ?? false
        let landing = blockerX + direction * (pets[i].halfWidth + pets[j].halfWidth + 6)
        let surface = pets[i].body.surfaceID.flatMap { world.surface(id: $0, containingX: pets[i].body.position.x) }
        if goalIsPast, let surface,
           landing >= surface.minX + pets[i].halfWidth, landing <= surface.maxX - pets[i].halfWidth,
           scripted || rng.unit() < 0.5 {
            pets[i].hop(to: landing, on: surface)
            return
        }

        if scripted {
            pets[i].brain.updateScriptTarget(pets[i].body.position.x)  // stop here; the walk counts as arrived
            pets[i].body.velocity.dx = 0
        } else {
            let back = clampOnSurface(pets[i].body.position.x - direction * Self.turnBackDistance, pet: i, world: world)
            pets[i].redirectWalk(to: back)
        }
    }
}
