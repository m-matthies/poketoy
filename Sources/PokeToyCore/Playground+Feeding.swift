import CoreGraphics
import Foundation

/// How a pet gets to its treat.
enum TreatRoute {
    case walk
    case leap(Surface)
    case walkOff(CGFloat)
}

extension Playground {
    static let eatDistance: CGFloat = 16
    static let treatSightRange: CGFloat = 800
    static let sharedTreatRadius: CGFloat = 150
    /// Treats nobody eats disappear after this long, so they can't clog the treat cap.
    public static let treatLifetime = 90.0

    /// A random spot along the top of a screen for a treat to drop from. Screens with pets on them are
    /// preferred (so someone can reach it); with no pets, any screen. Nil when there are no screens.
    public mutating func randomFeedingSpot(world: World) -> CGPoint? {
        let own = pets.filter { $0.role == .own && $0.visible }
        let withPets = world.screens.filter { screen in own.contains { screen.frame.contains($0.body.position) } }
        let candidates = withPets.isEmpty ? world.screens : withPets
        guard !candidates.isEmpty else { return nil }
        let screen = candidates[min(Int(rng.unit() * Double(candidates.count)), candidates.count - 1)]
        let margin: CGFloat = 40
        let x = screen.visibleFrame.minX + margin + CGFloat(rng.unit()) * max(0, screen.visibleFrame.width - 2 * margin)
        return CGPoint(x: x, y: screen.visibleFrame.maxY - 10)
    }

    /// Pets and treats are paired closest-first (one pet per treat) and each pet heads for its treat;
    /// the pet that reaches it eats it, and pets nearby who could have gone for it look sad.
    mutating func feedingRules(world: World) {
        guard game == nil else { return }
        let treats = items.indices.filter {
            items[$0].kind.isTreat && items[$0].state == .free && items[$0].body.isGrounded
        }
        treatTargets = treatTargets.filter { petID, treatID in
            treats.contains { items[$0].id == treatID } && pets.contains { $0.id == petID }
        }

        for (petID, treatID) in treatTargets {
            guard let i = index(of: petID), let t = itemIndex(of: treatID), pets[i].body.isGrounded,
                  pets[i].body.surfaceID == items[t].body.surfaceID,
                  abs(pets[i].body.position.x - items[t].body.position.x) <= Self.eatDistance else { continue }
            eat(treat: t, by: i)
            return  // item indices changed; the rest waits for the next tick
        }

        // Closest pet–treat pairs first, so every pet heads for its nearest free treat and no two chase the same one.
        var pairs: [(pet: Int, treat: Int, distance: CGFloat, route: TreatRoute)] = []
        for i in pets.indices where isEligibleForTreat(i) {
            let pet = pets[i]
            for t in treats {
                let treat = items[t]
                let dx = abs(pet.body.position.x - treat.body.position.x)
                guard dx <= Self.treatSightRange, let surfaceID = treat.body.surfaceID else { continue }
                let distance = hypot(dx, pet.body.position.y - treat.body.position.y)
                if pet.body.surfaceID == surfaceID {
                    pairs.append((i, t, distance, .walk))
                } else if let route = route(for: i, to: treat, world: world) {
                    pairs.append((i, t, distance, route))
                }
            }
        }
        pairs.sort { $0.distance < $1.distance }

        var assignment: [UUID: UUID] = [:]
        var busyPets = Set<Int>(), takenTreats = Set<Int>()
        for pair in pairs where !busyPets.contains(pair.pet) && !takenTreats.contains(pair.treat) {
            busyPets.insert(pair.pet)
            takenTreats.insert(pair.treat)
            let i = pair.pet, treat = items[pair.treat], petID = pets[i].id
            assignment[petID] = treat.id
            if treatTargets[petID] == treat.id, pets[i].brain.script != nil {
                pets[i].brain.updateScriptTarget(treat.body.position.x)
                continue
            }
            if pets[i].brain.script?.priority == 1 { pets[i].endScript() }  // switch to this treat
            switch pair.route {
            case .walk:
                pets[i].perform(Script(anim: .walk, moveTo: treat.body.position.x, speed: PetBrain.walkSpeed * 1.2,
                                       end: .arrived, priority: 1))
            case .leap(let surface):
                pets[i].jump(to: surface, x: treat.body.position.x)
            case .walkOff(let x):
                pets[i].perform(Script(anim: .walk, moveTo: x, speed: PetBrain.walkSpeed * 1.2, end: .arrived, priority: 1))
            }
        }
        // Pets whose treat went to someone closer stop chasing it.
        for (petID, _) in treatTargets where assignment[petID] == nil {
            if let i = index(of: petID), pets[i].brain.script?.priority == 1, pets[i].brain.script?.anim == .walk {
                pets[i].endScript()
            }
        }
        treatTargets = assignment
    }

    /// How pet `i` gets to a treat lying on another surface: a leap of any height up to it, or walking off
    /// its own surface's edge toward it (dropping down, or stepping across to the next screen).
    func route(for i: Int, to treat: Item, world: World) -> TreatRoute? {
        let pet = pets[i]
        guard let treatSurfaceID = treat.body.surfaceID,
              let target = world.surface(id: treatSurfaceID, containingX: treat.body.position.x) else { return nil }
        if target.y > pet.body.position.y + 20 {
            let reachable = world.reachableSurfaces(from: pet.body.position, maxRise: .greatestFiniteMagnitude,
                                                    maxReach: Self.treatSightRange, minWidth: 0)
            return reachable.contains(target) ? .leap(target) : nil
        }
        guard let id = pet.body.surfaceID, let current = world.surface(id: id, containingX: pet.body.position.x) else {
            return nil
        }
        let edge = treat.body.position.x < pet.body.position.x
            ? current.minX - pet.halfWidth * 2
            : current.maxX + pet.halfWidth * 2
        return .walkOff(edge)
    }

    private func isEligibleForTreat(_ i: Int) -> Bool {
        let pet = pets[i]
        guard pet.role == .own, pet.visible, pet.body.isGrounded, !inMoment(pet.id) else { return false }
        return pet.brain.isFree || pet.brain.script?.priority == 1
    }

    mutating func eat(treat t: Int, by eater: Int) {
        let treat = items.remove(at: t)
        let eaterID = pets[eater].id
        pets[eater].endScript()
        let thanks = Script(anim: .greet, hearts: 1, end: .animationFinished, priority: 2)
        pets[eater].perform(Script(anim: .eat, end: .after(2.5), priority: 2, then: .script(thanks)))
        // Pets nearby that could have gone for it (and aren't after another treat) are sad.
        for i in pets.indices where pets[i].id != eaterID && isEligibleForTreat(i)
            && (treatTargets[pets[i].id] ?? treat.id) == treat.id
            && abs(pets[i].body.position.x - treat.body.position.x) <= Self.treatSightRange {
            let facing: Direction = pets[i].body.position.x < treat.body.position.x ? .right : .left
            if pets[i].perform(Script(anim: .sad, facing: facing, end: .animationFinished, priority: 2)) { feel(.sad, i) }
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
        feel(.joyous, eater)
    }
}
