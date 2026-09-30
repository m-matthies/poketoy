import CoreGraphics
import Foundation

extension Playground {
    static let eatDistance: CGFloat = 16
    static let treatSightRange: CGFloat = 800
    static let sharedTreatRadius: CGFloat = 150
    /// Treats nobody eats disappear after this long, so they can't clog the treat cap.
    public static let treatLifetime = 90.0

    /// Where Feed should drop a treat: above the cursor when a pet on the cursor's screen can see it,
    /// otherwise above the nearest pet; with no pets, above the cursor.
    public func feedingSpot(cursor: CGPoint, world: World) -> CGPoint {
        func screen(containing point: CGPoint) -> ScreenInfo? { world.screens.first { $0.frame.contains(point) } }
        func top(_ screen: ScreenInfo) -> CGFloat { screen.visibleFrame.maxY - 10 }
        let cursorScreen = screen(containing: cursor) ?? world.screens.first
        let own = pets.filter { $0.role == .own && $0.visible }
        let nearCursor = own.filter { pet in cursorScreen.map { $0.frame.contains(pet.body.position) } ?? false }
            .min { abs($0.body.position.x - cursor.x) < abs($1.body.position.x - cursor.x) }
        if let nearCursor, let cursorScreen, abs(nearCursor.body.position.x - cursor.x) <= Self.treatSightRange {
            return CGPoint(x: cursor.x, y: top(cursorScreen))
        }
        let nearest = nearCursor ?? own.min {
            hypot($0.body.position.x - cursor.x, $0.body.position.y - cursor.y)
                < hypot($1.body.position.x - cursor.x, $1.body.position.y - cursor.y)
        }
        if let nearest, let petScreen = screen(containing: nearest.body.position) {
            return CGPoint(x: nearest.body.position.x, y: top(petScreen))
        }
        guard let cursorScreen else { return cursor }
        return CGPoint(x: cursor.x, y: top(cursorScreen))
    }

    /// Free own pets head for grounded treats; the first to arrive eats, latecomers are sad.
    mutating func feedingRules(world: World) {
        guard game == nil else { return }
        treatTargets = treatTargets.filter { petID, treatID in
            items.contains { $0.id == treatID && $0.state == .free } && pets.contains { $0.id == petID }
        }
        for t in items.indices where items[t].kind.isTreat && items[t].state == .free {
            guard let surfaceID = items[t].body.surfaceID else { continue }
            let treat = items[t]
            if let eater = pets.indices.first(where: { i in
                pets[i].role == .own && treatTargets[pets[i].id] == treat.id && pets[i].body.surfaceID == surfaceID
                    && abs(pets[i].body.position.x - treat.body.position.x) <= Self.eatDistance
            }) {
                eat(treat: t, by: eater)
                return  // item indices changed; the rest waits for the next tick
            }
            for i in pets.indices where isEligibleForTreat(i, treat: treat.id) {
                let pet = pets[i]
                guard abs(pet.body.position.x - treat.body.position.x) <= Self.treatSightRange else { continue }
                if treatTargets[pet.id] == treat.id, pet.brain.script != nil {
                    pets[i].brain.updateScriptTarget(treat.body.position.x)
                } else if pet.body.surfaceID == surfaceID {
                    let walk = Script(anim: .walk, moveTo: treat.body.position.x, speed: PetBrain.walkSpeed * 1.2,
                                      end: .arrived, priority: 1)
                    if pets[i].perform(walk) { treatTargets[pet.id] = treat.id }
                } else if let surface = world.surface(id: surfaceID, containingX: treat.body.position.x),
                          world.reachableSurfaces(from: pet.body.position, maxRise: PetBrain.maxJumpRise,
                                                  maxReach: PetBrain.maxJumpReach, minWidth: 0).contains(surface) {
                    if pets[i].jump(to: surface, x: treat.body.position.x) { treatTargets[pet.id] = treat.id }
                }
            }
        }
    }

    private func isEligibleForTreat(_ i: Int, treat: UUID) -> Bool {
        let pet = pets[i]
        guard pet.role == .own, pet.visible, pet.body.isGrounded, !inMoment(pet.id) else { return false }
        if let target = treatTargets[pet.id], target != treat { return false }  // already after another treat
        if pet.brain.isFree { return true }
        if let script = pet.brain.script, script.priority == 1, treatTargets[pet.id] == treat { return true }
        return false
    }

    mutating func eat(treat t: Int, by eater: Int) {
        let treat = items.remove(at: t)
        let eaterID = pets[eater].id
        pets[eater].endScript()
        let thanks = Script(anim: .greet, hearts: 1, end: .animationFinished, priority: 2)
        pets[eater].perform(Script(anim: .eat, end: .after(2.5), priority: 2, then: .script(thanks)))
        for i in pets.indices where pets[i].id != eaterID && treatTargets[pets[i].id] == treat.id {
            let facing: Direction = pets[i].body.position.x < treat.body.position.x ? .right : .left
            pets[i].perform(Script(anim: .sad, facing: facing, end: .animationFinished, priority: 2))
        }
        treatTargets = treatTargets.filter { $0.value != treat.id }

        let nearby = pets.filter {
            $0.role == .own && $0.visible
                && hypot($0.body.position.x - treat.body.position.x, $0.body.position.y - treat.body.position.y)
                    <= Self.sharedTreatRadius
        }.map(\.id)
        if nearby.count > 1 {
            for a in 0..<nearby.count {
                for b in (a + 1)..<nearby.count { friendships.add(nearby[a], nearby[b]) }
            }
            events.append(.friendshipChanged)
        }
        events.append(.treatEaten(petID: eaterID))
    }
}
