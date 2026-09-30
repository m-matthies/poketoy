import CoreGraphics
import Foundation

extension Playground {
    /// A game of fetch lasts a minute: then the ball fades away (a carrier drops it first).
    public static let fetchLength = 60.0
    static let pickUpDistance: CGFloat = 16

    public var canDropToy: Bool {
        game == nil && !items.contains { $0.kind == .toyBall }
    }

    /// Adds the fetch ball at `position` (it falls from there). Only one at a time, and not during a game.
    @discardableResult
    public mutating func dropToy(at position: CGPoint) -> UUID? {
        guard canDropToy else { return nil }
        let item = Item(kind: .toyBall, body: Body(position: position))
        items.append(item)
        return item.id
    }

    /// Free pets race for the ball; the first to reach it carries it back to below the cursor and drops it.
    mutating func fetchRules(world: World) {
        guard game == nil, let t = items.firstIndex(where: { $0.kind == .toyBall }) else {
            fetchRacers = []
            return
        }
        if case .fading = items[t].state {
            fetchRacers = []
            return
        }
        if items[t].playTime >= Self.fetchLength {
            if case .carried = items[t].state { dropCarriedToy(t) }
            items[t].state = .fading(remaining: 1)
            fetchRacers = []
            return
        }
        if case .carried(let carrierID) = items[t].state {
            bringBack(toy: t, carrier: carrierID, world: world)
            return
        }
        // Forget racers that gave up: dragged away, off after a treat, busy with something else.
        fetchRacers = fetchRacers.filter { id in
            guard let i = index(of: id), treatTargets[id] == nil else { return false }
            switch pets[i].brain.state {
            case .jump, .hop: return true
            default: return pets[i].brain.script?.priority == 1
            }
        }
        guard items[t].state == .free, items[t].body.isGrounded else { return }
        let toy = items[t]

        if let winner = pets.indices.first(where: { i in
            fetchRacers.contains(pets[i].id) && pets[i].body.isGrounded && pets[i].body.surfaceID == toy.body.surfaceID
                && abs(pets[i].body.position.x - toy.body.position.x) <= Self.pickUpDistance
        }) {
            pickUp(toy: t, by: winner, world: world)
            return
        }

        for i in pets.indices where isEligibleForToy(i) {
            let pet = pets[i]
            guard abs(pet.body.position.x - toy.body.position.x) <= Self.treatSightRange else { continue }
            if fetchRacers.contains(pet.id), pet.brain.script?.priority == 1 {
                pets[i].brain.updateScriptTarget(toy.body.position.x)
                continue
            }
            let started: Bool
            if pet.body.surfaceID == toy.body.surfaceID {
                started = pets[i].perform(Script(anim: .walk, moveTo: toy.body.position.x,
                                                 speed: PetBrain.walkSpeed * 1.3, end: .arrived, priority: 1))
            } else {
                switch route(for: i, to: toy, world: world) {
                case .leap(let surface)?: started = pets[i].jump(to: surface, x: toy.body.position.x)
                case .walkOff(let x)?:
                    started = pets[i].perform(Script(anim: .walk, moveTo: x, speed: PetBrain.walkSpeed * 1.3,
                                                     end: .arrived, priority: 1))
                default: started = false
                }
            }
            if started { fetchRacers.insert(pet.id) }
        }
    }

    private func isEligibleForToy(_ i: Int) -> Bool {
        let pet = pets[i]
        guard pet.role == .own, pet.visible, pet.body.isGrounded, !inMoment(pet.id),
              treatTargets[pet.id] == nil else { return false }
        return pet.brain.isFree || (pet.brain.script?.priority == 1 && fetchRacers.contains(pet.id))
    }

    private mutating func pickUp(toy t: Int, by winner: Int, world: World) {
        let winnerID = pets[winner].id
        items[t].state = .carried(petID: winnerID)
        items[t].age = 0
        for i in pets.indices where pets[i].id != winnerID && fetchRacers.contains(pets[i].id) {
            if pets[i].brain.script?.priority == 1 { pets[i].endScript() }
            if pets[i].perform(Script(anim: .sad, end: .animationFinished, priority: 2)) { feel(.sad, i) }
        }
        fetchRacers = []
        pets[winner].endScript()
        let goal = clampOnSurface(lastCursor.x, pet: winner, world: world)
        pets[winner].perform(Script(anim: .walk, moveTo: goal, speed: PetBrain.walkSpeed * 1.2, end: .after(30),
                                    priority: 2))
    }

    private mutating func bringBack(toy t: Int, carrier carrierID: UUID, world: World) {
        guard let c = index(of: carrierID), pets[c].visible, pets[c].body.isGrounded || isHopping(c), !interrupted(c) else {
            dropCarriedToy(t)
            return
        }
        let goal = clampOnSurface(lastCursor.x, pet: c, world: world)
        if abs(pets[c].body.position.x - goal) <= Self.pickUpDistance {
            // Delivered: let go of the ball and celebrate.
            items[t].state = .free
            items[t].body = Body(position: CGPoint(x: goal, y: pets[c].body.position.y + 10),
                                 velocity: CGVector(dx: 0, dy: 120))
            pets[c].endScript()
            pets[c].perform(Script(anim: .cheer, end: .animationFinished, priority: 2))
            feel(.joyous, c)
            events.append(.fetched(petID: carrierID))
        } else if pets[c].brain.script?.anim == .walk {
            pets[c].brain.updateScriptTarget(goal)
        } else {
            pets[c].perform(Script(anim: .walk, moveTo: goal, speed: PetBrain.walkSpeed * 1.2, end: .after(30),
                                   priority: 2))
        }
    }

    private func isHopping(_ i: Int) -> Bool {
        if case .hop = pets[i].brain.state { return true }
        return false
    }

    /// Lets go of the ball wherever its carrier is (also used when a catch game starts).
    mutating func dropCarriedToy() {
        guard let t = items.firstIndex(where: { $0.kind == .toyBall }), case .carried = items[t].state else { return }
        dropCarriedToy(t)
    }

    /// Lets go of the ball wherever the carrier is.
    private mutating func dropCarriedToy(_ t: Int) {
        items[t].state = .free
        items[t].body.surfaceID = nil
        items[t].body.velocity = CGVector(dx: 0, dy: 100)
    }

    /// Keeps a carried ball at its carrier's head.
    mutating func carryToy() {
        guard let t = items.firstIndex(where: { $0.kind == .toyBall }),
              case .carried(let carrierID) = items[t].state else { return }
        guard let c = index(of: carrierID) else {
            dropCarriedToy(t)
            return
        }
        let pet = pets[c]
        items[t].body = Body(position: CGPoint(x: pet.body.position.x,
                                               y: pet.body.position.y + pet.frameSize.height * pet.scale * 0.55))
    }
}
