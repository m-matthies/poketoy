import CoreGraphics
import Foundation

extension Playground {
    static let tagLength = 5.0
    static let meetingGap: CGFloat = 60
    static let followInterval = 8.0

    mutating func socialRules(dt: Double, world: World) {
        guard game == nil else { return }
        advanceMoments(dt: dt, world: world)
        startEncounters(dt: dt)
        napTogether(world: world)
        followBestFriends(dt: dt, world: world)
    }

    // MARK: - Encounters

    private mutating func startEncounters(dt: Double) {
        let own = pets.indices.filter { pets[$0].role == .own && pets[$0].visible }
        for x in own.indices {
            for y in own.indices where y > x {
                let i = own[x], j = own[y]
                let a = pets[i], b = pets[j]
                guard a.brain.isFree, b.brain.isFree, let surface = a.body.surfaceID, surface == b.body.surfaceID,
                      abs(a.body.position.x - b.body.position.x) < Self.meetingGap + a.halfWidth + b.halfWidth,
                      !inMoment(a.id), !inMoment(b.id),
                      (pairCooldowns[Friendships.key(a.id, b.id)] ?? 0) <= 0 else { continue }
                guard rng.unit() < 1 - pow(0.5, dt) else { continue }  // on average 0.5 per second of contact
                startMoment(i, j)
            }
        }
    }

    static func momentWeights(_ level: FriendshipLevel) -> [(kind: MomentKind, weight: Double)] {
        switch level {
        case .stranger: return [(.greet, 60), (.tag, 15), (.playFight, 25)]
        case .friend: return [(.greet, 40), (.tag, 30), (.playFight, 30)]
        case .bestFriend: return [(.greet, 30), (.tag, 35), (.playFight, 35)]
        }
    }

    mutating func pickMoment(for level: FriendshipLevel) -> MomentKind {
        let weights = Self.momentWeights(level)
        var roll = rng.unit() * weights.reduce(0) { $0 + $1.weight }
        for entry in weights {
            if roll < entry.weight { return entry.kind }
            roll -= entry.weight
        }
        return weights[weights.count - 1].kind
    }

    /// Starts a moment between the free, grounded pets at indices `i` and `j`.
    mutating func startMoment(_ i: Int, _ j: Int, kind requested: MomentKind? = nil) {
        let level = friendships.level(pets[i].id, pets[j].id)
        let kind = requested ?? pickMoment(for: level)
        let (first, second) = rng.unit() < 0.5 ? (i, j) : (j, i)
        pairCooldowns[Friendships.key(pets[i].id, pets[j].id)] = level == .bestFriend ? 10 : 20
        switch kind {
        case .greet:
            for (me, other) in [(i, j), (j, i)] {
                pets[me].perform(Script(anim: .greet, facing: facing(from: me, to: other), hearts: level.rawValue,
                                        end: .animationFinished, priority: 2))
            }
            moments.append(ActiveMoment(kind: .greet, a: pets[i].id, b: pets[j].id))
        case .tag:
            let speed = PetBrain.walkSpeed * 1.4
            let length = Script.End.after(Self.tagLength + 1)
            pets[first].perform(Script(anim: .walk, moveTo: pets[second].body.position.x, speed: speed, end: length, priority: 2))
            pets[second].perform(Script(anim: .walk, moveTo: pets[second].body.position.x, speed: speed, end: length, priority: 2))
            moments.append(ActiveMoment(kind: .tag, a: pets[first].id, b: pets[second].id))
        case .playFight:
            pets[first].perform(Script(anim: .attack, facing: facing(from: first, to: second),
                                       end: .animationFinished, priority: 2))
            pets[second].perform(Script(anim: .idle, facing: facing(from: second, to: first), end: .after(10), priority: 2))
            moments.append(ActiveMoment(kind: .playFight, a: pets[first].id, b: pets[second].id))
        }
        events.append(.momentStarted(kind))
    }

    // MARK: - Moments in progress

    private mutating func advanceMoments(dt: Double, world: World) {
        var done: [Int] = []
        for m in moments.indices {
            moments[m].elapsed += dt
            let moment = moments[m]
            guard let i = index(of: moment.a), let j = index(of: moment.b) else {
                done.append(m)
                continue
            }
            let aBusy = pets[i].brain.script?.priority == 2
            let bBusy = pets[j].brain.script?.priority == 2
            switch moment.kind {
            case .greet:
                if interrupted(i) || interrupted(j) {
                    abort(i, j)
                    done.append(m)
                } else if !aBusy && !bBusy {
                    complete(i, j)
                    done.append(m)
                }

            case .tag:
                guard aBusy && bBusy else {
                    abort(i, j)
                    done.append(m)
                    continue
                }
                if moment.elapsed >= Self.tagLength {
                    pets[i].endScript()
                    pets[j].endScript()
                    complete(i, j)
                    done.append(m)
                    continue
                }
                var (chaser, runner) = (i, j)
                let reach = pets[i].halfWidth + pets[j].halfWidth + 10  // they can't overlap, so "caught" is touching
                if moment.stage == 0, abs(pets[i].body.position.x - pets[j].body.position.x) < reach {
                    (chaser, runner) = (j, i)  // tagged: swap roles once
                    moments[m].a = moment.b
                    moments[m].b = moment.a
                    moments[m].stage = 1
                }
                pets[chaser].brain.updateScriptTarget(pets[runner].body.position.x)
                pets[runner].brain.updateScriptTarget(runAwayTarget(runner, from: chaser, world: world))

            case .playFight:
                if moment.stage == 0 {
                    guard bBusy, !interrupted(i) else {
                        abort(i, j)
                        done.append(m)
                        continue
                    }
                    if !aBusy {  // the attack animation finished: the defender flinches and hops back
                        let away: CGFloat = pets[j].body.position.x >= pets[i].body.position.x ? 1 : -1
                        let back = clampOnSurface(pets[j].body.position.x + away * 30, pet: j, world: world)
                        pets[j].endScript()
                        pets[j].perform(Script(anim: .sad, facing: facing(from: j, to: i), moveTo: back, speed: 90,
                                               end: .animationFinished, priority: 2))
                        moments[m].stage = 1
                    }
                } else if interrupted(j) {
                    abort(i, j)
                    done.append(m)
                } else if !bBusy {
                    complete(i, j)
                    done.append(m)
                }
            }
        }
        for m in done.reversed() { moments.remove(at: m) }
    }

    func interrupted(_ i: Int) -> Bool {
        switch pets[i].brain.state {
        case .react, .dragged, .held, .fall, .landing, .jump: return true
        default: return false
        }
    }

    /// Ends a moment early: partners still in it go back to idle and no friendship is gained.
    mutating func abort(_ i: Int, _ j: Int) {
        for k in [i, j] where pets[k].brain.script?.priority == 2 { pets[k].endScript() }
    }

    private mutating func complete(_ i: Int, _ j: Int) {
        friendships.add(pets[i].id, pets[j].id)
        events.append(.friendshipChanged)
    }

    // MARK: - Napping and following

    private mutating func napTogether(world: World) {
        for s in pets.indices where pets[s].role == .own && pets[s].visible {
            let sleeping = pets[s].brain.isSleeping
            defer { pets[s].wasSleeping = sleeping }
            guard sleeping, !pets[s].wasSleeping, let surface = pets[s].body.surfaceID else { continue }
            for f in pets.indices where f != s && pets[f].role == .own && pets[f].visible && pets[f].brain.isFree
                && pets[f].body.surfaceID == surface && !inMoment(pets[f].id) {
                let level = friendships.level(pets[s].id, pets[f].id)
                guard level == .bestFriend || (level == .friend && rng.unit() < 0.5) else { continue }
                let side: CGFloat = pets[f].body.position.x < pets[s].body.position.x ? -1 : 1
                let spot = clampOnSurface(pets[s].body.position.x + side * (pets[s].halfWidth + pets[f].halfWidth + 4),
                                          pet: f, world: world)
                pets[f].perform(Script(anim: .walk, moveTo: spot, end: .arrived, priority: 2, then: .sleep))
            }
        }
    }

    private mutating func followBestFriends(dt: Double, world: World) {
        let ownIDs = pets.filter { $0.role == .own && $0.visible }.map(\.id)
        for i in pets.indices where pets[i].role == .own && pets[i].visible && pets[i].brain.isFree && !inMoment(pets[i].id) {
            let id = pets[i].id
            let timer = (followTimers[id] ?? Self.followInterval) - dt
            guard timer <= 0 else {
                followTimers[id] = timer
                continue
            }
            followTimers[id] = Self.followInterval
            guard let friendID = friendships.bestFriend(of: id, among: ownIDs), let j = index(of: friendID),
                  pets[j].body.surfaceID == pets[i].body.surfaceID,
                  abs(pets[j].body.position.x - pets[i].body.position.x) > 80, rng.unit() < 0.5 else { continue }
            let side: CGFloat = pets[i].body.position.x < pets[j].body.position.x ? -1 : 1
            let spot = clampOnSurface(pets[j].body.position.x + side * (pets[i].halfWidth + pets[j].halfWidth + 10),
                                      pet: i, world: world)
            pets[i].perform(Script(anim: .walk, moveTo: spot, end: .arrived, priority: 1))
        }
    }

    // MARK: - Helpers

    func facing(from i: Int, to j: Int) -> Direction {
        pets[j].body.position.x >= pets[i].body.position.x ? .right : .left
    }

    /// `x` kept on the surface pet `k` stands on (so it doesn't walk off an edge).
    func clampOnSurface(_ x: CGFloat, pet k: Int, world: World) -> CGFloat {
        let pet = pets[k]
        guard let id = pet.body.surfaceID, let surface = world.surface(id: id, containingX: pet.body.position.x) else { return x }
        let lo = surface.minX + pet.halfWidth, hi = surface.maxX - pet.halfWidth
        return hi > lo ? min(max(x, lo), hi) : surface.midX
    }

    private func runAwayTarget(_ runner: Int, from chaser: Int, world: World) -> CGFloat {
        let away: CGFloat = pets[runner].body.position.x >= pets[chaser].body.position.x ? 1 : -1
        return clampOnSurface(pets[runner].body.position.x + away * 120, pet: runner, world: world)
    }
}
