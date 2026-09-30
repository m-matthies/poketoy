import CoreGraphics
import Foundation

/// Friends walking in a line behind a leader.
struct Parade: Equatable, Sendable {
    var leader: UUID
    /// Nearest to the leader first.
    var followers: [UUID]
    var direction: CGFloat
    var elapsed: Double = 0
}

extension Playground {
    static let paradeInterval = 45.0
    static let paradeChance = 0.4
    static let paradeLength = 12.0
    static let paradeGap: CGFloat = 6
    /// How long pets keep looking for a moment to start a parade once the roll succeeded.
    static let paradeLookout = 10.0

    mutating func paradeRules(dt: Double) {
        guard game == nil else {
            for p in parades.indices.reversed() { endParade(p, completed: false) }
            return
        }
        paradeTimer -= dt
        if paradeTimer <= 0 {
            paradeTimer = Self.paradeInterval
            if rng.unit() < Self.paradeChance { paradeWindow = Self.paradeLookout }
        }
        if paradeWindow > 0 {
            // Friends are often busy playing; keep looking for a moment when a group is free.
            paradeWindow -= dt
            let candidates = pets.indices.filter(isParadeReady)
            if !candidates.isEmpty,
               startParade(from: candidates[min(Int(rng.unit() * Double(candidates.count)), candidates.count - 1)]) {
                paradeWindow = 0
            }
        }

        for p in parades.indices.reversed() {
            parades[p].elapsed += dt
            let parade = parades[p]
            let members = ([parade.leader] + parade.followers).compactMap(index(of:))
            guard members.count == parade.followers.count + 1, !members.contains(where: interrupted),
                  members.dropFirst().allSatisfy({ pets[$0].brain.script?.priority == 2 }) else {
                endParade(p, completed: false)
                continue
            }
            if pets[members[0]].brain.script == nil || parade.elapsed >= Self.paradeLength {
                endParade(p, completed: true)
                continue
            }
            var ahead = members[0]
            for follower in members.dropFirst() {
                let spacing = pets[ahead].halfWidth + pets[follower].halfWidth + Self.paradeGap
                pets[follower].brain.updateScriptTarget(pets[ahead].body.position.x - parade.direction * spacing)
                ahead = follower
            }
        }
    }

    /// Starts a parade around pet `i` if at least two of its friends are free on the same surface.
    /// The friend at the end with more room ahead leads, so followers start out behind it.
    @discardableResult
    mutating func startParade(from i: Int) -> Bool {
        guard game == nil, !reduceMotion, isParadeReady(i), let surfaceID = pets[i].body.surfaceID,
              let surface = lastWorld.surface(id: surfaceID, containingX: pets[i].body.position.x) else { return false }
        let candidate = pets[i].id
        var group = [i] + pets.indices.filter { j in
            j != i && isParadeReady(j) && pets[j].body.surfaceID == surfaceID
                && friendships.level(candidate, pets[j].id) >= .friend
        }
        guard group.count >= 3 else { return false }
        group.sort { pets[$0].body.position.x < pets[$1].body.position.x }
        let roomRight = surface.maxX - pets[group[group.count - 1]].body.position.x
        let roomLeft = pets[group[0]].body.position.x - surface.minX
        let direction: CGFloat = roomRight >= roomLeft ? 1 : -1
        let leader = direction > 0 ? group[group.count - 1] : group[0]
        let followers = (direction > 0 ? Array(group.reversed()) : group).filter {
            $0 != leader && friendships.level(pets[leader].id, pets[$0].id) >= .friend
        }
        guard followers.count >= 2 else { return false }

        let end = clampOnSurface(direction > 0 ? surface.maxX : surface.minX, pet: leader, world: lastWorld)
        guard pets[leader].perform(Script(anim: .walk, moveTo: end, speed: PetBrain.walkSpeed * 0.8, end: .arrived,
                                          priority: 2)) else { return false }
        for follower in followers {
            pets[follower].perform(Script(anim: .walk, moveTo: pets[follower].body.position.x, speed: PetBrain.walkSpeed,
                                          end: .after(Self.paradeLength + 2), priority: 2))
        }
        parades.append(Parade(leader: pets[leader].id, followers: followers.map { pets[$0].id }, direction: direction))
        return true
    }

    private func isParadeReady(_ i: Int) -> Bool {
        let pet = pets[i]
        return pet.role == .own && pet.visible && pet.body.isGrounded && pet.brain.isFree && !inMoment(pet.id)
    }

    private mutating func endParade(_ p: Int, completed: Bool) {
        let parade = parades.remove(at: p)
        for id in [parade.leader] + parade.followers {
            if let i = index(of: id), pets[i].brain.script?.priority == 2 { pets[i].endScript() }
        }
        guard completed else { return }
        for follower in parade.followers { friendships.add(parade.leader, follower) }
        events.append(.friendshipChanged)
    }
}
