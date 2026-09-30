import CoreGraphics
import Foundation

extension Playground {
    /// Starts a round (ignored while one is running or with an empty roster). Social moments stop.
    public mutating func startGame(roster: [WildSpec], seed: UInt64) {
        guard game == nil, !roster.isEmpty else { return }
        for moment in moments {
            if let i = index(of: moment.a), let j = index(of: moment.b) { abort(i, j) }
        }
        moments.removeAll()
        treatTargets.removeAll()
        dropCarriedToy()
        fetchRacers.removeAll()
        game = CatchGame(roster: roster, seed: seed)
        lastResults = nil
    }

    public mutating func endGame() {
        game?.requestEnd()
    }

    /// Throws the current ball (Poké, Great or Ultra, by combo) from `position`. Only while playing,
    /// and at most `CatchGame.maxBallsInFlight` at once.
    @discardableResult
    public mutating func throwBall(from position: CGPoint, velocity: CGVector) -> Bool {
        guard let tier = game?.ballTier, game?.isPlaying == true, ballsInFlight < CatchGame.maxBallsInFlight else {
            return false
        }
        items.append(Item(kind: tier.itemKind, body: Body(position: position, velocity: velocity), state: .flying))
        return true
    }

    /// Throws one of the round's Razz Berries; a wild Pokémon it hits calms down for a while.
    @discardableResult
    public mutating func throwBerry(from position: CGPoint, velocity: CGVector) -> Bool {
        guard game?.isPlaying == true, ballsInFlight < CatchGame.maxBallsInFlight, game?.useBerry() == true else {
            return false
        }
        items.append(Item(kind: .razzBerry, body: Body(position: position, velocity: velocity), state: .flying))
        return true
    }

    mutating func gameRulesBeforePhysics(dt: Double, world: World) {
        if game != nil {
            if game!.advance(dt: dt) {
                finishRound()
            } else {
                if game!.isActive { keepOwnPetsSitting() }
                let wildCount = pets.filter { $0.role == .wild }.count
                if let pick = game!.spawn(dt: dt, wildCount: wildCount) { spawnWild(pick.spec, shiny: pick.shiny, world: world) }
            }
        }
        driveWild(dt: dt, world: world)
    }

    mutating func gameRulesAfterPhysics(dt: Double) {
        if game?.isPlaying == true {
            ballHits()
            berryHits()
        }
        advanceWobbles(dt: dt)
    }

    // MARK: - Pets during a round

    private mutating func keepOwnPetsSitting() {
        let sit = Script(anim: .sit, end: .after(3600), priority: 3)
        for i in pets.indices where pets[i].role == .own && pets[i].visible && (pets[i].brain.script?.priority ?? 0) < 3 {
            pets[i].perform(sit)
        }
    }

    private mutating func spawnWild(_ spec: WildSpec, shiny: Bool, world: World) {
        guard !world.screens.isEmpty else { return }
        let pick = game?.randomUnit() ?? 0
        let screen = world.screens[min(Int(pick * Double(world.screens.count)), world.screens.count - 1)]
        let fromLeft = (game?.randomUnit() ?? 0) < 0.5
        let x = fromLeft ? screen.frame.minX + 40 : screen.frame.maxX - 40
        var y = screen.visibleFrame.minY + 1
        var flight: Flight?
        if spec.canFly {
            // Glide at a random height between 150 pt above the floor and 70% of the screen.
            let low = screen.visibleFrame.minY + 150
            let high = max(low, screen.frame.minY + screen.frame.height * 0.7)
            y = low + CGFloat(game?.randomUnit() ?? 0.5) * (high - low)
            flight = Flight(baseY: y, direction: fromLeft ? 1 : -1)
        }
        let id = addPet(role: .wild, metrics: spec.metrics, at: CGPoint(x: x, y: y))
        pets[pets.count - 1].lifetime = game?.wildLifetime() ?? CatchGame.lifetime.lowerBound
        pets[pets.count - 1].flight = flight
        wildSpecs[id] = spec
        events.append(.wildSpawned(petID: id, path: spec.path))
        if shiny {
            wildShiny.insert(id)
            events.append(.wildShiny(petID: id))
        }
    }

    /// Ages wild Pokémon, sends them off-screen when their time is up (or the round is over),
    /// and gives a dash to ones that just broke free.
    private mutating func driveWild(dt: Double, world: World) {
        let roundActive = game?.isActive ?? false
        for i in pets.indices where pets[i].role == .wild && pets[i].visible {
            pets[i].lifetime -= dt
            if pets[i].lifetime <= 0 || !roundActive { pets[i].leaving = true }
            let id = pets[i].id
            if fleeBoost.contains(id), pets[i].brain.isFree {
                let away: CGFloat = rng.unit() < 0.5 ? -1 : 1
                pets[i].perform(Script(anim: .walk, moveTo: pets[i].body.position.x + away * 300,
                                       speed: PetBrain.walkSpeed * 1.6 * 2, end: .after(2), priority: 2))
                fleeBoost.remove(id)
            }
            let x = pets[i].body.position.x
            if pets[i].leaving && pets[i].exitX == nil, let lo = world.screens.map(\.frame.minX).min(),
               let hi = world.screens.map(\.frame.maxX).max() {
                // Head for the outer edge of all screens, so side-by-side displays can't bounce it back and forth.
                pets[i].exitX = x - lo < hi - x ? lo - 200 : hi + 200
            }
            if pets[i].flight != nil {
                glide(i, dt: dt, world: world)
                continue
            }
            guard pets[i].leaving, let exit = pets[i].exitX, (pets[i].brain.script?.priority ?? 0) < 3 else { continue }
            pets[i].perform(Script(anim: .walk, moveTo: exit, speed: PetBrain.walkSpeed * 1.6 * 1.5, end: .arrived, priority: 3))
        }
    }

    // MARK: - Balls

    /// A flying wild Pokémon glides sideways, bobbing, turning at screen edges until it leaves.
    private mutating func glide(_ i: Int, dt: Double, world: World) {
        guard var flight = pets[i].flight else { return }
        let x = pets[i].body.position.x
        if pets[i].leaving, let exit = pets[i].exitX {
            flight.direction = exit > x ? 1 : -1
        } else if let screen = world.screens.first(where: { $0.frame.minX <= x && x <= $0.frame.maxX }) {
            if x < screen.frame.minX + 40 { flight.direction = 1 }
            if x > screen.frame.maxX - 40 { flight.direction = -1 }
        }
        let calmed = (calmedUntil[pets[i].id] ?? 0) > clock
        let speed = PetBrain.walkSpeed * 1.6 * (calmed ? 0.5 : 1)
        flight.phase += dt * 2.5
        pets[i].body.surfaceID = nil
        pets[i].body.velocity = CGVector(dx: flight.direction * speed, dy: 0)
        pets[i].body.position = CGPoint(x: x + flight.direction * speed * CGFloat(dt),
                                        y: flight.baseY + CGFloat(sin(flight.phase)) * 40)
        pets[i].brain.look(toward: flight.direction)
        pets[i].flight = flight
    }

    private mutating func berryHits() {
        for b in items.indices where items[b].kind == .razzBerry && items[b].state == .flying {
            let center = CGPoint(x: items[b].body.position.x,
                                 y: items[b].body.position.y + CGFloat(ItemArt.size) * scale / 2)
            guard let w = pets.indices.first(where: {
                pets[$0].role == .wild && pets[$0].visible && pets[$0].hitRect.contains(center)
            }) else { continue }
            calmedUntil[pets[w].id] = clock + Self.calmTime
            items[b].state = .fading(remaining: 0.3)
            items[b].body.velocity = .zero
            feel(.happy, w)
        }
    }

    static let calmTime = 8.0

    private mutating func ballHits() {
        for b in items.indices where items[b].kind.isBall && items[b].state == .flying {
            let center = CGPoint(x: items[b].body.position.x,
                                 y: items[b].body.position.y + CGFloat(ItemArt.size) * scale / 2)
            guard let w = pets.indices.first(where: {
                pets[$0].role == .wild && pets[$0].visible && pets[$0].hitRect.contains(center)
            }) else { continue }
            let wildID = pets[w].id
            let tier: BallTier = items[b].kind == .ultraBall ? .ultra : items[b].kind == .greatBall ? .great : .poke
            let outcome = game?.rollCatch(tier: tier, calmed: (calmedUntil[wildID] ?? 0) > clock)
                ?? (caught: false, wobbles: 1)
            game?.recordHit(isLegendary: wildSpecs[wildID]?.isLegendary ?? false, isShiny: wildShiny.contains(wildID))
            // Never let the ball start below the wild's feet, or it could fall past the floor.
            items[b].body.position.y = max(items[b].body.position.y, pets[w].body.position.y)
            pets[w].visible = false
            pets[w].body.velocity = .zero
            items[b].body.velocity = .zero
            items[b].state = .wobbling(petID: pets[w].id, wobblesLeft: outcome.wobbles, caught: outcome.caught,
                                       timer: Item.wobbleDuration)
            events.append(.ballHit(petID: pets[w].id))
        }
    }

    private mutating func advanceWobbles(dt: Double) {
        var outcomes: [(ball: UUID, pet: UUID, caught: Bool)] = []
        for b in items.indices {
            guard case .wobbling(let petID, let left, let caught, let timer) = items[b].state,
                  items[b].body.isGrounded else { continue }
            let remaining = timer - dt
            if remaining > 0 {
                items[b].state = .wobbling(petID: petID, wobblesLeft: left, caught: caught, timer: remaining)
            } else if left > 1 {
                items[b].state = .wobbling(petID: petID, wobblesLeft: left - 1, caught: caught, timer: Item.wobbleDuration)
            } else {
                outcomes.append((items[b].id, petID, caught))
            }
        }
        for outcome in outcomes { resolveCapture(ball: outcome.ball, pet: outcome.pet, caught: outcome.caught) }
    }

    private mutating func resolveCapture(ball ballID: UUID, pet petID: UUID, caught: Bool) {
        guard let b = itemIndex(of: ballID) else { return }
        let position = items[b].body.position
        guard let w = index(of: petID) else {
            items.remove(at: b)
            return
        }
        if caught {
            if let spec = wildSpecs[petID] {
                let shiny = wildShiny.contains(petID)
                let record = CatchRecord(petID: petID, path: shiny ? (spec.shinyPath ?? spec.path) : spec.path,
                                         displayName: spec.displayName, position: position, isShiny: shiny)
                game?.recordCatch(record, isLegendary: spec.isLegendary, firstThrow: !brokeFreeOnce.contains(petID))
            }
            removePet(petID)
            items[b].state = .fading(remaining: 0.8)
            events.append(.caught(petID: petID))
            events.append(.wildRemoved(petID: petID))
            for i in pets.indices where pets[i].role == .own && pets[i].visible {
                pets[i].perform(Script(anim: .cheer, end: .animationFinished, priority: 4))
            }
        } else {
            pets[w].visible = true
            pets[w].flight = nil  // out of the ball it drops to the ground, flyer or not
            brokeFreeOnce.insert(petID)
            pets[w].body = Body(position: CGPoint(x: position.x, y: position.y + 4))
            pets[w].handle(.knocked(velocity: CGVector(dx: 0, dy: 250)))  // pops out of the ball
            fleeBoost.insert(petID)
            items.remove(at: b)
            events.append(.brokeFree(petID: petID))
        }
    }

    // MARK: - End of round

    private mutating func finishRound() {
        let pending: [(ball: UUID, pet: UUID, caught: Bool)] = items.compactMap { item in
            if case .wobbling(let petID, _, let caught, _) = item.state { return (item.id, petID, caught) }
            return nil
        }
        for capture in pending { resolveCapture(ball: capture.ball, pet: capture.pet, caught: capture.caught) }
        for i in items.indices where items[i].state == .flying { items[i].state = .fading(remaining: 0.5) }
        for i in pets.indices where pets[i].role == .wild { pets[i].leaving = true }
        for i in pets.indices where pets[i].role == .own {
            if pets[i].brain.script?.priority == 3 { pets[i].endScript() }  // stop sitting; let cheers finish
            pets[i].brain.noteInteraction()  // watching the round counts as company: no nap straight after
        }
        if let game { lastResults = CatchResults(score: game.score, catches: game.catches) }
        game = nil
        events.append(.roundEnded)
    }
}

/// How a flying wild Pokémon glides.
struct Flight: Sendable {
    var baseY: CGFloat
    var direction: CGFloat
    var phase: Double = 0
}
