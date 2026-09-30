# PokeToy Play Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add pet-to-pet interaction with friendships and collisions, treat feeding, a timed Poké Ball catch game, a "complete sprites only" picker filter, pets that wake up on their own, and pets that prefer walking on the active window.

**Architecture:** The per-pet simulation moves from the AppKit `PetController` into a new PokeToyCore `Playground` value type that owns every pet (`PetActor`), item (`Item`), friendship score and the running `CatchGame`, and exposes one `tick`. `PetBrain` gains generic *scripts* (directed actions with priorities) that the playground's feeding, social, collision and game rules use. The app target becomes a thin renderer: pet/treat panels, a full-screen game overlay with HUD, and a results window.

**Tech Stack:** Swift 6.4 toolchain in Swift 5 language mode, SwiftPM, AppKit, CoreGraphics, Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-30-poketoy-play-design.md` (builds on `docs/superpowers/specs/2026-09-30-poketoy-design.md`)

## Global Constraints

- macOS 14+, SwiftPM only, Swift 5 language mode; run tests with `./scripts/test.sh` (wraps `swift test`, which flakes without it), build the app with `./scripts/build-app.sh`.
- Coordinates are AppKit global (bottom-left origin, +y up); a pet's/item's position is the bottom-center of its feet/base.
- Caps: 12 own pets (`Playground.maxOwnPets`), 3 wild Pokémon at once, 10 treats (`Playground.maxTreats`), 8 Poké Balls in flight.
- Script priorities: 1 = treat pursuit, best-friend following, bumps; 2 = social moments, eating, sadness; 3 = catch-game sitting and wild leaving; 4 = cheering.
- Friendship levels: stranger 0–2, friend 3–9, best friend ≥ 10 points; stored as `[String: Int]` keyed `"<uuidA>+<uuidB>"` with the UUID strings sorted.
- Catch game: 3 s countdown, 60 s round, spawn every 4–7 s, wild lifetime 12–20 s, catch chance 0.6, 1–3 wobbles of 0.6 s, hit +25, catch +100.
- "Complete" sprites = SpriteCollab `sprite_complete == 2`.
- Naps last 30–120 s; waking resets the time-since-interaction.
- Wild Pokémon never collide with own pets, never sleep, and always flee the cursor within 220 pt.
- Own pets head for the active window's top with probability 0.6 per wander decision; on it they rarely leave.

## Review Focus

1. **A pet removed, clicked or dragged in the middle of a social moment** — its partner must drop back to idle and no friendship is awarded; nothing stays stuck in a script. Pinned by `SocialTests.interruptedGreetGivesNoFriendship` and `SocialTests.removingAPartnerEndsTheMoment` (Task 9).
2. **A treat landing somewhere no pet can reach** (a high window top) — pets must not keep jumping at it or freeze; the treat just stays. Pinned by `FeedingTests.unreachableTreatIsIgnored` (Task 8).
3. **The round ending while a ball is still wobbling** — the pre-rolled result is applied, the catch is listed, and no invisible wild Pokémon is left behind. Pinned by `GameTests.endingMidWobbleResolvesTheCatch` (Task 11).
4. **Several pets racing for one treat** — exactly one eats it; the others are sad and nobody eats twice. Pinned by `FeedingTests.closestPetWinsOthersAreSad` (Task 8).
5. **Starting the game offline** — the roster falls back to cached/bundled Pokémon so it is never empty. Pinned by `SpriteStoreTests.offlineUsesAnIncompleteCache` and `SpriteStoreTests.cachedSpritePathsListUsableDirectories` (Task 12); the app-level fallback is checked by hand in Task 14.

---

## File Structure

```
Sources/PokeToyCore/
  PetAnim.swift            (modify) + eat, greet, attack, sad, sit, cheer, wake
  PetBrain.swift           (replace) scripts, personality, knocked, auto-wake, public jump/fallAsleep;
                           Task 13 edits decideNext for the active window
  World.swift              (modify, Task 13) activeWindowID
  ItemArt.swift            (new) ItemKind + pixel-art grids -> SpriteFrame
  Item.swift               (new) Item, ItemEvent
  Friendships.swift        (new) FriendshipLevel, Friendships
  Settings.swift           (modify) friendships, bestCatchScore
  Catalog.swift            (modify) isComplete, completeOnly filter
  PetMetrics.swift         (new) per-anim durations/frame sizes
  CatchGame.swift          (new) WildSpec, CatchRecord, CatchResults, CatchGame rules
  Playground.swift         (new) PetRole, PetActor, PlaygroundEvent, MomentKind, Playground core + tick
  Playground+Feeding.swift (new)
  Playground+Social.swift  (new)
  Playground+Collisions.swift (new)
  Playground+Game.swift    (new)
  SpriteStore.swift        (modify) offline fallback, cachedSpritePaths, timeout, LocalizedError
Sources/PokeToy/
  WorldMonitor.swift       (modify, Task 13) finds the active window
  DragTracker.swift        (new) drag offset + release velocity
  PetWindow.swift          (replace) hearts count
  PetController.swift      (replace) renders a PetActor, forwards input
  ItemController.swift     (new) treat panel
  AppModel.swift           (replace in Task 13, again in Task 14)
  MenuBuilder.swift        (replace in Task 13, again in Task 14)
  PickerWindowController.swift (replace) "Show all Pokémon"
  GameController.swift, GameOverlayWindow.swift, ResultsWindowController.swift (new, Task 14)
Resources/Sprites/0025/    + Eat, Nod, Attack, Cringe, Sit, Wake sheets
Tests/PokeToyCoreTests/
  TestSupport.swift (append), SpriteSetTests.swift (replace), AnimatorTests.swift (append test),
  BundledSpriteTests.swift (replace), PetBrainTests.swift (edit 2 tests), PetBrainScriptTests.swift,
  ItemTests.swift, FriendshipsTests.swift, SettingsTests.swift (append), CatalogTests.swift (replace),
  SpriteStoreTests.swift (edit + append), CatchGameTests.swift, PlaygroundTests.swift,
  FeedingTests.swift, SocialTests.swift, CollisionTests.swift, GameTests.swift,
  PetBrainActiveWindowTests.swift, WorldTests.swift (append)
```

---

### Task 1: New pet animations and bundled sheets

**Files:**
- Modify: `Sources/PokeToyCore/PetAnim.swift` (replace)
- Modify: `Tests/PokeToyCoreTests/SpriteSetTests.swift` (replace), `Tests/PokeToyCoreTests/AnimatorTests.swift` (append one test), `Tests/PokeToyCoreTests/BundledSpriteTests.swift` (replace)
- Create: `Resources/Sprites/0025/{Eat,Nod,Attack,Cringe,Sit,Wake}-Anim.png` (downloaded)

**Interfaces:**
- Produces: `PetAnim` cases `idle, walk, sleep, react, dangle, land, eat, greet, attack, sad, sit, cheer, wake`; non-looping: `react, land, greet, attack, sad, cheer, wake`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/PokeToyCoreTests/SpriteSetTests.swift -->
```swift
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct SpriteSetTests {
    @Test func loadsPreferredAnimations() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [
            TestAnim(name: "Walk"), TestAnim(name: "Idle", durations: [3, 3, 3]),
            TestAnim(name: "Sleep"), TestAnim(name: "Hop"), TestAnim(name: "Hurt"),
        ])
        let set = try SpriteSet(directory: dir)
        #expect(set.animation(.idle).info.name == "Idle")
        #expect(set.animation(.idle).durations == [3, 3, 3])
        #expect(set.animation(.walk).info.name == "Walk")
        #expect(set.animation(.sleep).info.name == "Sleep")
        #expect(set.animation(.react).info.name == "Hop")
        #expect(set.animation(.dangle).info.name == "Hurt")
        #expect(set.animation(.land).info.name == "Hurt")
        #expect(set.animation(.walk).frames.count == 8)
    }

    @Test func loadsSocialAnimations() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [
            TestAnim(name: "Walk"), TestAnim(name: "Idle"), TestAnim(name: "Eat"), TestAnim(name: "Nod"),
            TestAnim(name: "Attack"), TestAnim(name: "Cringe"), TestAnim(name: "Sit"), TestAnim(name: "Wake"),
            TestAnim(name: "Hop"),
        ])
        let set = try SpriteSet(directory: dir)
        #expect(set.animation(.eat).info.name == "Eat")
        #expect(set.animation(.greet).info.name == "Nod")
        #expect(set.animation(.attack).info.name == "Attack")
        #expect(set.animation(.sad).info.name == "Cringe")
        #expect(set.animation(.sit).info.name == "Sit")
        #expect(set.animation(.cheer).info.name == "Hop")
        #expect(set.animation(.wake).info.name == "Wake")
    }

    @Test func fallsBackWhenAnimationsAreMissing() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk")])
        let set = try SpriteSet(directory: dir)
        for kind in PetAnim.allCases {
            #expect(set.animation(kind).info.name == "Walk")
        }
    }

    @Test func skipsCandidateWhoseSheetIsMissing() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk"), TestAnim(name: "Idle")])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Idle-Anim.png"))
        let set = try SpriteSet(directory: dir)
        #expect(set.animation(.idle).info.name == "Walk")
    }

    @Test func followsCopyOfToTheSourceSheet() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk"), TestAnim(name: "Hop", copyOf: "Walk")])
        let set = try SpriteSet(directory: dir)
        #expect(set.animation(.react).info.name == "Hop")
        #expect(set.animation(.react).info.sourceName == "Walk")
    }

    @Test func failsWithoutIdleOrWalk() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Attack")])
        #expect(throws: SpriteSetError.self) { try SpriteSet(directory: dir) }
    }

    @Test func requiredFilesCoverEveryPetAnim() throws {
        let xml = animDataXML([
            TestAnim(name: "Walk"), TestAnim(name: "Idle"), TestAnim(name: "Hop", copyOf: "Walk"),
            TestAnim(name: "Attack"),
        ])
        let data = try AnimData(xml: Data(xml.utf8))
        #expect(SpriteSet.requiredFiles(for: data) == ["Walk-Anim.png", "Idle-Anim.png", "Attack-Anim.png"])
    }
}
```

Append this test inside `AnimatorTests` (before its closing brace):

<!-- append-in-suite: Tests/PokeToyCoreTests/AnimatorTests.swift -->
```swift
    @Test func socialOneShotsFinishAndActivitiesLoop() {
        for kind in [PetAnim.greet, .attack, .sad, .cheer, .wake] {
            var animator = Animator()
            animator.play(kind)
            animator.advance(dt: 1, durations: [2, 4])
            #expect(animator.finished, "\(kind) should play once")
        }
        for kind in [PetAnim.eat, .sit] {
            var animator = Animator()
            animator.play(kind)
            animator.advance(dt: 1, durations: [2, 4])
            #expect(!animator.finished, "\(kind) should loop")
        }
    }
```

<!-- file: Tests/PokeToyCoreTests/BundledSpriteTests.swift -->
```swift
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct BundledSpriteTests {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Sprites/0025")

    @Test func bundledPikachuIsComplete() throws {
        #expect(SpriteStore.isComplete(directory))
        let set = try SpriteSet(directory: directory)
        #expect(set.animation(.walk).info.name == "Walk")
        #expect(set.animation(.sleep).info.name == "Sleep")
        #expect(set.animation(.react).info.name == "Hop")
        #expect(set.animation(.dangle).info.name == "Hurt")
        #expect(set.animation(.eat).info.name == "Eat")
        #expect(set.animation(.greet).info.name == "Nod")
        #expect(set.animation(.attack).info.name == "Attack")
        #expect(set.animation(.sad).info.name == "Cringe")
        #expect(set.animation(.sit).info.name == "Sit")
        #expect(set.animation(.wake).info.name == "Wake")
        #expect(set.animation(.walk).frames.count == 8)
        #expect(set.animation(.sleep).frames.count == 1)
        for kind in PetAnim.allCases {
            let animation = set.animation(kind)
            // Most sheets have one row per direction; some (e.g. Sleep) have a single shared row.
            #expect(animation.frames.count == 8 || animation.frames.count == 1, "\(kind) has \(animation.frames.count) rows")
            #expect(!animation.frames(facing: .right).isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh`
Expected: build FAILS with "type 'PetAnim' has no member 'eat'" (and similar for the other new kinds).

- [ ] **Step 3: Implement the new kinds and download the bundled sheets**

<!-- file: Sources/PokeToyCore/PetAnim.swift -->
```swift
/// What the pet is visibly doing. Each kind maps to PMD animation names in order of preference.
public enum PetAnim: CaseIterable, Sendable {
    case idle, walk, sleep, react, dangle, land, eat, greet, attack, sad, sit, cheer, wake

    public var candidates: [String] {
        switch self {
        case .idle: return ["Idle", "Walk"]
        case .walk: return ["Walk", "Idle"]
        case .sleep: return ["Sleep", "EventSleep", "Laying", "Idle", "Walk"]
        case .react: return ["Hop", "Pose", "Idle", "Walk"]
        case .dangle: return ["Hurt", "Idle", "Walk"]
        case .land: return ["Hurt", "Idle", "Walk"]
        case .eat: return ["Eat", "Nod", "Idle", "Walk"]
        case .greet: return ["Nod", "Pose", "Hop", "Idle", "Walk"]
        case .attack: return ["Attack", "Swing", "Hop", "Walk"]
        case .sad: return ["Cringe", "Pain", "Hurt", "Idle", "Walk"]
        case .sit: return ["Sit", "Idle", "Walk"]
        case .cheer: return ["Hop", "Pose", "Idle", "Walk"]
        case .wake: return ["Wake", "Idle", "Walk"]
        }
    }

    /// Non-looping animations play once and then report `Animator.finished`.
    public var loops: Bool {
        switch self {
        case .react, .land, .greet, .attack, .sad, .cheer, .wake: return false
        default: return true
        }
    }
}
```

```bash
BASE=https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master
for f in Eat Nod Attack Cringe Sit Wake; do
  curl -fsSL -o "Resources/Sprites/0025/$f-Anim.png" "$BASE/sprite/0025/$f-Anim.png"
done
ls Resources/Sprites/0025
```
Expected: 13 files (AnimData.xml plus 12 sheets).

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/PetAnim.swift Tests/PokeToyCoreTests Resources/Sprites/0025
git commit -m "feat: eat, greet, attack, sad, sit, cheer and wake animations"
```

---

### Task 2: PetBrain scripts, wild personality, knock-backs and waking up

**Files:**
- Modify: `Sources/PokeToyCore/PetBrain.swift` (replace)
- Modify: `Tests/PokeToyCoreTests/PetBrainTests.swift` (replace two tests, add one helper)
- Test: `Tests/PokeToyCoreTests/PetBrainScriptTests.swift`

**Interfaces:**
- Consumes: `PetAnim` (Task 1), `Body`, `Physics`, `World`, `Surface`, `SplitMix64` (existing).
- Produces:
  - `PetEvent` gains `.knocked(velocity: CGVector)`.
  - `enum Personality { pet, wild }`; `PetBrain(seed:personality:)`, `personality`.
  - `Pose { anim, facing, hearts: Int, token; showHeart }` (replaces `showHeart: Bool` storage).
  - `struct Script { anim; facing; hearts; moveTo: CGFloat?; speed; end: End; priority: Int; then: Then }`, `Script.End { animationFinished, after(Double), arrived }`, `Script.Then { idle, sleep, script(Script) }`.
  - `PetBrain.State` gains `waking`, `scripted(Script, elapsed: Double)`.
  - `PetBrain`: `isFree`, `isSleeping`, `script`, `perform(_:body:) -> Bool`, `updateScriptTarget(_:)`, `endScript(body:)`, `fallAsleep(body:) -> Bool`, `jump(to:x:halfWidth:body:) -> Bool`; constants `napLength = 30...120`, `wildFleeRadius = 220`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/PokeToyCoreTests/PetBrainScriptTests.swift -->
```swift
import CoreGraphics
import Testing
@testable import PokeToyCore

@Suite struct PetBrainScriptTests {
    let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                            visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))
    let floor = Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor)
    let shelf = Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)
    var world: World { World(screens: [screen], surfaces: [floor, shelf]) }
    var floorOnly: World { World(screens: [screen], surfaces: [floor]) }

    func ctx(_ world: World? = nil, finished: Bool = false, cursor: CGPoint = CGPoint(x: -5000, y: -5000),
             mode: CursorMode = .off) -> BrainContext {
        BrainContext(dt: 1.0 / 60, world: world ?? self.world, cursor: cursor, cursorMode: mode, halfWidth: 20,
                     animationFinished: finished)
    }

    func tick(_ brain: inout PetBrain, _ body: inout Body, _ context: BrainContext) {
        brain.update(context, body: &body)
        if brain.state != .dragged { Physics.step(&body, dt: 1.0 / 60, world: context.world) }
    }

    func run(_ brain: inout PetBrain, _ body: inout Body, seconds: Double, _ context: BrainContext) {
        for _ in 0..<Int((seconds * 60).rounded()) { tick(&brain, &body, context) }
    }

    func grounded(x: CGFloat) -> Body {
        Body(position: CGPoint(x: x, y: 50), surfaceID: -1)
    }

    func isIdle(_ brain: PetBrain) -> Bool {
        if case .idle = brain.state { return true }
        return false
    }

    @Test func performStartsAScriptWhenFree() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        let token = brain.pose.token
        #expect(brain.perform(Script(anim: .greet, facing: .left, hearts: 2, end: .animationFinished, priority: 2), body: &body))
        #expect(brain.script?.anim == .greet)
        #expect(brain.pose == Pose(anim: .greet, facing: .left, hearts: 2, token: token + 1))
        #expect(!brain.isFree)
    }

    @Test func performIsRejectedWhileBusyOrAirborne() {
        var dragged = PetBrain(seed: 1)
        var body = grounded(x: 500)
        dragged.handle(.dragBegan, body: &body)
        #expect(!dragged.perform(Script(anim: .greet, end: .animationFinished, priority: 9), body: &body))

        var airborneBrain = PetBrain(seed: 2)
        var airborne = Body(position: CGPoint(x: 500, y: 400))
        #expect(!airborneBrain.perform(Script(anim: .greet, end: .animationFinished, priority: 1), body: &airborne))

        var reacting = PetBrain(seed: 3)
        var body2 = grounded(x: 500)
        reacting.handle(.click, body: &body2)
        #expect(!reacting.perform(Script(anim: .greet, end: .animationFinished, priority: 1), body: &body2))
    }

    @Test func higherPriorityReplacesLower() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        #expect(brain.perform(Script(anim: .walk, moveTo: 900, end: .arrived, priority: 1), body: &body))
        #expect(!brain.perform(Script(anim: .sad, end: .animationFinished, priority: 1), body: &body))
        #expect(brain.perform(Script(anim: .sad, end: .animationFinished, priority: 2), body: &body))
        #expect(brain.script?.anim == .sad)
    }

    @Test func animationFinishedEndsTheScript() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .greet, hearts: 1, end: .animationFinished, priority: 2), body: &body)
        tick(&brain, &body, ctx())
        #expect(brain.script != nil)
        tick(&brain, &body, ctx(finished: true))
        #expect(isIdle(brain))
        #expect(brain.pose.hearts == 0)
    }

    @Test func timedScriptEnds() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .eat, end: .after(1), priority: 2), body: &body)
        run(&brain, &body, seconds: 0.9, ctx())
        #expect(brain.script?.anim == .eat)
        run(&brain, &body, seconds: 0.2, ctx())
        #expect(isIdle(brain))
    }

    @Test func movingScriptWalksAndArrives() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .walk, moveTo: 600, end: .arrived, priority: 1), body: &body)
        tick(&brain, &body, ctx())
        #expect(body.velocity.dx > 0)
        #expect(brain.pose.anim == .walk)
        #expect(brain.pose.facing == .right)
        run(&brain, &body, seconds: 2, ctx())
        #expect(abs(body.position.x - 600) <= 2)
        #expect(isIdle(brain) || brain.isFree)
    }

    @Test func nonWalkScriptKeepsItsFacing() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .sad, facing: .left, moveTo: 530, speed: 90, end: .after(2), priority: 2), body: &body)
        tick(&brain, &body, ctx())
        #expect(body.velocity.dx == 90)
        #expect(brain.pose.anim == .sad)
        #expect(brain.pose.facing == .left)
    }

    @Test func thenSleepFallsAsleepOnArrival() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .walk, moveTo: 520, end: .arrived, priority: 2, then: .sleep), body: &body)
        run(&brain, &body, seconds: 1, ctx())
        #expect(brain.isSleeping)
        #expect(brain.pose.anim == .sleep)
    }

    @Test func thenScriptChains() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        let thanks = Script(anim: .greet, hearts: 1, end: .animationFinished, priority: 2)
        brain.perform(Script(anim: .eat, end: .after(0.5), priority: 2, then: .script(thanks)), body: &body)
        run(&brain, &body, seconds: 0.6, ctx())
        #expect(brain.pose.anim == .greet)
        #expect(brain.pose.hearts == 1)
    }

    @Test func clickInterruptsAScript() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .sit, end: .after(100), priority: 3), body: &body)
        brain.handle(.click, body: &body)
        #expect(brain.state == .react)
    }

    @Test func updateScriptTargetRedirects() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .walk, moveTo: 900, end: .arrived, priority: 1), body: &body)
        brain.updateScriptTarget(100)
        tick(&brain, &body, ctx())
        #expect(body.velocity.dx < 0)
        #expect(brain.script?.moveTo == 100)
    }

    @Test func endScriptReturnsToIdle() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.perform(Script(anim: .sit, end: .after(100), priority: 3), body: &body)
        brain.endScript(body: &body)
        #expect(isIdle(brain))
    }

    @Test func knockedLaunchesAndLandsHard() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.handle(.knocked(velocity: CGVector(dx: 220, dy: 380)), body: &body)
        #expect(brain.state == .fall(startY: 50, thrown: true))
        #expect(brain.pose.anim == .dangle)
        #expect(!body.isGrounded)
        #expect(body.velocity == CGVector(dx: 220, dy: 380))
        run(&brain, &body, seconds: 1.5, ctx(floorOnly))
        #expect(brain.state == .landing)
    }

    @Test func knockedIsIgnoredWhileDragged() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 500)
        brain.handle(.dragBegan, body: &body)
        brain.handle(.knocked(velocity: CGVector(dx: 220, dy: 380)), body: &body)
        #expect(brain.state == .dragged)
    }

    @Test func wildFleesWithoutACursorModeAndFaster() {
        var brain = PetBrain(seed: 4, personality: .wild)
        var body = grounded(x: 500)
        brain.update(ctx(floorOnly, cursor: CGPoint(x: 480, y: 60), mode: .off), body: &body)
        #expect(body.velocity.dx >= PetBrain.walkSpeed * 1.6 * 1.8 - 0.001)
    }

    @Test func wildNeverSleeps() {
        var brain = PetBrain(seed: 5, personality: .wild)
        var body = grounded(x: 500)
        for _ in 0..<(120 * 60) {
            tick(&brain, &body, ctx(floorOnly))
            #expect(brain.state != .sleep)
        }
    }

    @Test func sleepingPetWakesUpOnItsOwn() {
        var brain = PetBrain(seed: 6)
        var body = grounded(x: 500)
        #expect(brain.fallAsleep(body: &body))
        var woke = false
        for _ in 0..<(121 * 60) {
            tick(&brain, &body, ctx(floorOnly))
            if brain.state == .waking { woke = true; break }
        }
        #expect(woke)
        #expect(brain.pose.anim == .wake)
        tick(&brain, &body, ctx(floorOnly, finished: true))
        #expect(isIdle(brain))
        // Waking resets the interaction timer: it stays awake for at least half a minute.
        for _ in 0..<(30 * 60) {
            tick(&brain, &body, ctx(floorOnly))
            #expect(brain.state != .sleep)
        }
    }

    @Test func fallAsleepOnlyWhenFreeAndGrounded() {
        var brain = PetBrain(seed: 1)
        var airborne = Body(position: CGPoint(x: 500, y: 400))
        #expect(!brain.fallAsleep(body: &airborne))
        var busy = PetBrain(seed: 2)
        var body = grounded(x: 500)
        busy.perform(Script(anim: .sit, end: .after(10), priority: 3), body: &body)
        #expect(!busy.fallAsleep(body: &body))
    }

    @Test func publicJumpLandsOnTheTarget() {
        var brain = PetBrain(seed: 1)
        var body = grounded(x: 450)
        #expect(brain.jump(to: shelf, x: 450, halfWidth: 20, body: &body))
        #expect(brain.state == .jump)
        run(&brain, &body, seconds: 1.5, ctx())
        #expect(body.surfaceID == 7)
    }
}
```

In `Tests/PokeToyCoreTests/PetBrainTests.swift`, pets may now wake from a nap before a fixed deadline, so the two sleep tests stop at the moment of falling asleep instead. Add this helper after `grounded(x:on:)`:

<!-- snippet: PetBrainTests helper -->
```swift
    /// Runs until the brain falls asleep (at most `seconds`); returns whether it did.
    func runUntilAsleep(_ brain: inout PetBrain, _ body: inout Body, seconds: Double, _ context: BrainContext) -> Bool {
        for _ in 0..<Int(seconds * 60) {
            brain.update(context, body: &body)
            Physics.step(&body, dt: 1.0 / 60, world: context.world)
            if brain.state == .sleep { return true }
        }
        return false
    }
```

and replace the tests `fallsAsleepWhenLeftAloneAndWakesOnClick` and `switchingCursorModeWakesSleeper` with:

<!-- snippet: PetBrainTests sleep tests -->
```swift
    @Test func fallsAsleepWhenLeftAloneAndWakesOnClick() {
        var brain = PetBrain(seed: 2)
        var body = grounded(x: 500, on: floor)
        #expect(runUntilAsleep(&brain, &body, seconds: 120, ctx(floorOnly)))
        #expect(brain.pose.anim == .sleep)
        brain.handle(.click, body: &body)
        #expect(brain.state == .react)
    }

    @Test func switchingCursorModeWakesSleeper() {
        var brain = PetBrain(seed: 2)
        var body = grounded(x: 500, on: floor)
        #expect(runUntilAsleep(&brain, &body, seconds: 120, ctx(floorOnly)))
        brain.update(ctx(floorOnly, mode: .flee), body: &body)
        #expect(brain.state != .sleep)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter "PetBrainScriptTests|PetBrainTests"`
Expected: build FAILS with "cannot find 'Script' in scope" / "extra argument 'personality' in call".

- [ ] **Step 3: Implement the new PetBrain**

<!-- file: Sources/PokeToyCore/PetBrain.swift -->
```swift
import CoreGraphics

public enum CursorMode: String, Codable, CaseIterable, Sendable {
    case off, follow, flee
}

public enum PetEvent: Equatable, Sendable {
    /// Mouse went down on the pet (before it is known to be a click or a drag).
    case pressed
    /// The press ended without a click or drag (e.g. the mouse-up was never delivered).
    case released
    case click
    case dragBegan
    case dragEnded(velocity: CGVector)
    /// Hit by a thrown pet: launched with `velocity`, lands hard.
    case knocked(velocity: CGVector)
}

/// `.pet` is one of the user's pets; `.wild` is a catch-game Pokémon (faster, skittish, never sleeps).
public enum Personality: Equatable, Sendable {
    case pet, wild
}

public struct Pose: Equatable, Sendable {
    public var anim: PetAnim
    public var facing: Direction
    /// Hearts shown above the pet (0–2).
    public var hearts: Int
    /// Changes whenever the animation should restart from its first frame.
    public var token: Int

    public var showHeart: Bool { hearts > 0 }
}

/// A short directed action. `Playground` uses scripts for social moments, feeding and the catch game.
public struct Script: Equatable, Sendable {
    public enum End: Equatable, Sendable {
        case animationFinished
        case after(Double)
        /// Reached `moveTo` (immediately if there is none).
        case arrived
    }

    /// What the pet does when the script ends.
    public indirect enum Then: Equatable, Sendable {
        case idle
        case sleep
        case script(Script)
    }

    public var anim: PetAnim
    public var facing: Direction
    public var hearts: Int
    public var moveTo: CGFloat?
    public var speed: CGFloat
    public var end: End
    public var priority: Int
    public var then: Then

    public init(anim: PetAnim, facing: Direction = .down, hearts: Int = 0, moveTo: CGFloat? = nil,
                speed: CGFloat = PetBrain.walkSpeed, end: End, priority: Int, then: Then = .idle) {
        self.anim = anim
        self.facing = facing
        self.hearts = hearts
        self.moveTo = moveTo
        self.speed = speed
        self.end = end
        self.priority = priority
        self.then = then
    }
}

public struct BrainContext: Sendable {
    public var dt: Double
    public var world: World
    public var cursor: CGPoint
    public var cursorMode: CursorMode
    /// Half the pet's on-screen width, used to keep it on surfaces.
    public var halfWidth: CGFloat
    /// The current pose's non-looping animation has played to the end.
    public var animationFinished: Bool

    public init(dt: Double, world: World, cursor: CGPoint, cursorMode: CursorMode, halfWidth: CGFloat,
                animationFinished: Bool) {
        self.dt = dt
        self.world = world
        self.cursor = cursor
        self.cursorMode = cursorMode
        self.halfWidth = halfWidth
        self.animationFinished = animationFinished
    }
}

/// Decides what a pet does each tick. Movement is expressed through `Body.velocity`; `Physics` moves it.
public struct PetBrain: Sendable {
    public enum State: Equatable, Sendable {
        case idle(remaining: Double)
        case walk(targetX: CGFloat, speed: CGFloat)
        case sleep
        case waking
        case jump
        case fall(startY: CGFloat, thrown: Bool)
        case dragged
        case react
        case landing
        case held
        case scripted(Script, elapsed: Double)
    }

    public static let walkSpeed: CGFloat = 70
    public static let sleepAfter: Double = 60
    public static let napLength: ClosedRange<Double> = 30...120
    public static let fleeRadius: CGFloat = 150
    public static let wildFleeRadius: CGFloat = 220
    public static let hardLandingDrop: CGFloat = 150
    public static let maxJumpRise: CGFloat = 320
    public static let maxJumpReach: CGFloat = 360

    public let personality: Personality
    public private(set) var state: State = .idle(remaining: 1)
    public private(set) var pose = Pose(anim: .idle, facing: .down, hearts: 0, token: 0)
    private var rng: SplitMix64
    private var sinceInteraction: Double = 0
    private var napRemaining: Double = 0

    public init(seed: UInt64, personality: Personality = .pet) {
        rng = SplitMix64(seed: seed)
        self.personality = personality
    }

    /// Idle or wandering, so free to be directed.
    public var isFree: Bool {
        switch state {
        case .idle, .walk: return true
        default: return false
        }
    }

    public var isSleeping: Bool { state == .sleep }

    public var script: Script? {
        if case .scripted(let script, _) = state { return script }
        return nil
    }

    private var speedFactor: CGFloat { personality == .wild ? 1.6 : 1 }

    // MARK: - Events

    public mutating func handle(_ event: PetEvent, body: inout Body) {
        sinceInteraction = 0
        switch event {
        case .pressed:
            guard state != .dragged else { return }
            body.velocity.dx = 0
            state = .held
        case .released:
            guard state == .held else { return }
            if body.isGrounded { enterIdle(&body) } else { state = .fall(startY: body.position.y, thrown: false) }
        case .click:
            guard state != .dragged else { return }
            guard body.isGrounded else {
                if state == .held { state = .fall(startY: body.position.y, thrown: false) }
                return
            }
            body.velocity.dx = 0
            state = .react
            setPose(.react, .down, hearts: 1, restart: true)
        case .dragBegan:
            state = .dragged
            body.surfaceID = nil
            body.velocity = .zero
            setPose(.dangle, .down, restart: true)
        case .dragEnded(let velocity):
            state = .fall(startY: body.position.y, thrown: true)
            body.velocity = velocity
        case .knocked(let velocity):
            guard state != .dragged, state != .held else { return }
            state = .fall(startY: body.position.y, thrown: true)
            body.surfaceID = nil
            body.velocity = velocity
            setPose(.dangle, .down, restart: true)
        }
    }

    // MARK: - Directed actions

    /// Starts `script` if the pet is grounded and free, asleep, or running a lower-priority script.
    @discardableResult
    public mutating func perform(_ script: Script, body: inout Body) -> Bool {
        guard body.isGrounded else { return false }
        switch state {
        case .idle, .walk, .sleep:
            break
        case .scripted(let current, _) where script.priority > current.priority:
            break
        default:
            return false
        }
        start(script, &body)
        return true
    }

    /// Changes where the running script walks to.
    public mutating func updateScriptTarget(_ x: CGFloat) {
        guard case .scripted(var script, let elapsed) = state else { return }
        script.moveTo = x
        state = .scripted(script, elapsed: elapsed)
    }

    public mutating func endScript(body: inout Body) {
        guard case .scripted = state else { return }
        enterIdle(&body)
    }

    @discardableResult
    public mutating func fallAsleep(body: inout Body) -> Bool {
        guard body.isGrounded, isFree else { return false }
        enterSleep(&body)
        return true
    }

    /// Jumps onto `surface` near `x` if the pet is free (or only pursuing something at priority 1).
    @discardableResult
    public mutating func jump(to surface: Surface, x: CGFloat, halfWidth: CGFloat, body: inout Body) -> Bool {
        guard body.isGrounded else { return false }
        switch state {
        case .idle, .walk:
            break
        case .scripted(let current, _) where current.priority <= 1:
            break
        default:
            return false
        }
        launch(to: surface, x: x, halfWidth: halfWidth, &body)
        return true
    }

    // MARK: - Update

    public mutating func update(_ ctx: BrainContext, body: inout Body) {
        sinceInteraction += ctx.dt

        switch state {
        case .dragged:
            return
        case .held:
            body.velocity.dx = 0
            return
        case .fall(let startY, let thrown):
            guard body.isGrounded else { return }
            if thrown || startY - body.position.y > Self.hardLandingDrop {
                state = .landing
                setPose(.land, .down, restart: true)
            } else {
                enterIdle(&body)
            }
            return
        case .jump:
            if body.isGrounded { enterIdle(&body) }
            return
        default:
            break
        }

        guard body.isGrounded else {  // walked off an edge
            state = .fall(startY: body.position.y, thrown: false)
            setPose(.walk, .down)
            return
        }

        switch state {
        case .react, .landing, .waking:
            body.velocity.dx = 0
            if ctx.animationFinished { enterIdle(&body) }
        case .sleep:
            body.velocity.dx = 0
            if ctx.cursorMode != .off || personality == .wild {
                enterIdle(&body)
                return
            }
            napRemaining -= ctx.dt
            if napRemaining <= 0 {
                sinceInteraction = 0
                state = .waking
                setPose(.wake, .down, restart: true)
            }
        case .scripted(let script, let elapsed):
            runScript(script, elapsed: elapsed + ctx.dt, ctx, &body)
        case .idle(let remaining):
            body.velocity.dx = 0
            if applyCursor(ctx, &body) { return }
            if effectiveMode(ctx) == .follow { return }  // waits by the cursor instead of wandering
            let left = remaining - ctx.dt
            if left > 0 { state = .idle(remaining: left) } else { decideNext(ctx, &body) }
        case .walk(let targetX, let speed):
            if applyCursor(ctx, &body) { return }
            walk(toward: targetX, speed: speed, dt: ctx.dt, &body)
        default:
            break
        }
    }

    // MARK: - Scripts

    private mutating func start(_ script: Script, _ body: inout Body) {
        state = .scripted(script, elapsed: 0)
        body.velocity.dx = 0
        setPose(script.anim, script.facing, hearts: script.hearts, restart: true)
    }

    private mutating func runScript(_ script: Script, elapsed: Double, _ ctx: BrainContext, _ body: inout Body) {
        var arrived = true
        if let target = script.moveTo {
            let dx = target - body.position.x
            if abs(dx) <= max(2, script.speed * CGFloat(ctx.dt)) {
                body.velocity.dx = 0
                if script.anim == .walk { setPose(.idle, .down) }
            } else {
                arrived = false
                body.velocity.dx = dx > 0 ? script.speed : -script.speed
                let facing: Direction = script.anim == .walk ? (dx > 0 ? .right : .left) : script.facing
                setPose(script.anim, facing, hearts: script.hearts)
            }
        } else {
            body.velocity.dx = 0
        }

        let done: Bool
        switch script.end {
        case .animationFinished: done = ctx.animationFinished
        case .after(let seconds): done = elapsed >= seconds
        case .arrived: done = arrived
        }
        if done { finish(script, &body) } else { state = .scripted(script, elapsed: elapsed) }
    }

    private mutating func finish(_ script: Script, _ body: inout Body) {
        switch script.then {
        case .idle: enterIdle(&body)
        case .sleep: enterSleep(&body)
        case .script(let next): start(next, &body)
        }
    }

    // MARK: - Behaviors

    private func effectiveMode(_ ctx: BrainContext) -> CursorMode {
        personality == .wild ? .flee : ctx.cursorMode
    }

    /// Returns true if the cursor mode decided the movement for this tick.
    private mutating func applyCursor(_ ctx: BrainContext, _ body: inout Body) -> Bool {
        let p = body.position
        guard let id = body.surfaceID, let surface = ctx.world.surface(id: id, containingX: p.x) else { return false }
        switch effectiveMode(ctx) {
        case .off:
            return false

        case .follow:
            let c = ctx.cursor
            if c.y > p.y + 80, let target = bestJump(toward: c, from: p, ctx) {
                launch(to: target, x: c.x, halfWidth: ctx.halfWidth, &body)
                return true
            }
            guard abs(c.x - p.x) > 30 else { return false }
            let dropDown = c.y < p.y - 80 && surface.kind == .window
            let target = dropDown ? c.x : clamp(c.x, on: surface, ctx.halfWidth)
            let speed = Self.walkSpeed * 1.4 * speedFactor
            state = .walk(targetX: target, speed: speed)
            walk(toward: target, speed: speed, dt: ctx.dt, &body)
            return true

        case .flee:
            let radius = personality == .wild ? Self.wildFleeRadius : Self.fleeRadius
            let center = CGPoint(x: p.x, y: p.y + ctx.halfWidth)
            guard hypot(ctx.cursor.x - center.x, ctx.cursor.y - center.y) < radius else { return false }
            let away: CGFloat = ctx.cursor.x > p.x ? -1 : 1
            var target = p.x + away * 200
            if surface.kind == .floor { target = clamp(target, on: surface, ctx.halfWidth) }
            if abs(target - p.x) < 4, let escape = bestJump(awayFrom: ctx.cursor, from: p, ctx) {
                launch(to: escape, x: escape.midX, halfWidth: ctx.halfWidth, &body)
                return true
            }
            let speed = Self.walkSpeed * 1.8 * speedFactor
            state = .walk(targetX: target, speed: speed)
            walk(toward: target, speed: speed, dt: ctx.dt, &body)
            return true
        }
    }

    private mutating func decideNext(_ ctx: BrainContext, _ body: inout Body) {
        if personality == .pet && ctx.cursorMode == .off && sinceInteraction > Self.sleepAfter {
            enterSleep(&body)
            return
        }
        guard let id = body.surfaceID, let surface = ctx.world.surface(id: id, containingX: body.position.x) else {
            enterIdle(&body)
            return
        }
        let roll = rng.unit()
        if roll < (personality == .wild ? 0.35 : 0.2) {
            let options = reachable(from: body.position, ctx)
            if !options.isEmpty {
                let pick = options[min(Int(rng.unit() * Double(options.count)), options.count - 1)]
                launch(to: pick, x: pick.minX + CGFloat(rng.unit()) * pick.width, halfWidth: ctx.halfWidth, &body)
                return
            }
        }
        let target: CGFloat
        if surface.kind == .window && roll > 0.85 {
            // Stroll off the edge of the window.
            target = rng.unit() < 0.5 ? surface.minX - ctx.halfWidth * 2 : surface.maxX + ctx.halfWidth * 2
        } else {
            let lo = surface.minX + ctx.halfWidth, hi = surface.maxX - ctx.halfWidth
            guard hi > lo else { enterIdle(&body); return }
            target = lo + CGFloat(rng.unit()) * (hi - lo)
        }
        let speed = Self.walkSpeed * speedFactor
        state = .walk(targetX: target, speed: speed)
        walk(toward: target, speed: speed, dt: ctx.dt, &body)
    }

    private mutating func walk(toward targetX: CGFloat, speed: CGFloat, dt: Double, _ body: inout Body) {
        let dx = targetX - body.position.x
        if abs(dx) <= max(2, speed * CGFloat(dt)) {
            enterIdle(&body)
            return
        }
        body.velocity.dx = dx > 0 ? speed : -speed
        setPose(.walk, dx > 0 ? .right : .left)
    }

    private mutating func launch(to surface: Surface, x: CGFloat, halfWidth: CGFloat, _ body: inout Body) {
        let p = body.position
        let landingX = surface.width > halfWidth * 2
            ? min(max(x, surface.minX + halfWidth), surface.maxX - halfWidth)
            : surface.midX
        let g = Physics.gravity
        let overshoot: CGFloat = 40
        let vy = (2 * g * (surface.y - p.y + overshoot)).squareRoot()
        let flightTime = vy / g + (2 * overshoot / g).squareRoot()
        body.velocity = CGVector(dx: (landingX - p.x) / flightTime, dy: vy)
        body.surfaceID = nil
        state = .jump
        setPose(.walk, Direction.from(dx: landingX - p.x, dy: surface.y - p.y))
    }

    private mutating func enterIdle(_ body: inout Body) {
        body.velocity.dx = 0
        state = .idle(remaining: 2 + rng.unit() * 4)
        setPose(.idle, .down)
    }

    private mutating func enterSleep(_ body: inout Body) {
        body.velocity.dx = 0
        napRemaining = Self.napLength.lowerBound + rng.unit() * (Self.napLength.upperBound - Self.napLength.lowerBound)
        state = .sleep
        setPose(.sleep, .down)
    }

    private mutating func setPose(_ anim: PetAnim, _ facing: Direction, hearts: Int = 0, restart: Bool = false) {
        pose = Pose(anim: anim, facing: facing, hearts: hearts, token: restart ? pose.token + 1 : pose.token)
    }

    // MARK: - Helpers

    private func reachable(from p: CGPoint, _ ctx: BrainContext) -> [Surface] {
        ctx.world.reachableSurfaces(from: p, maxRise: Self.maxJumpRise, maxReach: Self.maxJumpReach,
                                    minWidth: ctx.halfWidth * 2)
    }

    private func bestJump(toward cursor: CGPoint, from p: CGPoint, _ ctx: BrainContext) -> Surface? {
        reachable(from: p, ctx)
            .filter { $0.y <= cursor.y + 40 }
            .min { $0.distance(toX: cursor.x) < $1.distance(toX: cursor.x) }
    }

    private func bestJump(awayFrom cursor: CGPoint, from p: CGPoint, _ ctx: BrainContext) -> Surface? {
        reachable(from: p, ctx).max { abs($0.midX - cursor.x) < abs($1.midX - cursor.x) }
    }

    private func clamp(_ x: CGFloat, on surface: Surface, _ halfWidth: CGFloat) -> CGFloat {
        let lo = surface.minX + halfWidth, hi = surface.maxX - halfWidth
        return hi > lo ? min(max(x, lo), hi) : surface.midX
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh`
Expected: all tests PASS (the app target is not built by `swift test`; `PetController` still compiles because `Pose.showHeart` remains).

Also run: `swift build 2>&1 | grep -E "error:" || echo "app builds"`
Expected: `app builds`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/PetBrain.swift Tests/PokeToyCoreTests/PetBrainScriptTests.swift Tests/PokeToyCoreTests/PetBrainTests.swift
git commit -m "feat: PetBrain scripts, wild personality, knock-backs and waking up"
```

---

### Task 3: Item art and items

**Files:**
- Create: `Sources/PokeToyCore/ItemArt.swift`, `Sources/PokeToyCore/Item.swift`
- Test: `Tests/PokeToyCoreTests/ItemTests.swift`

**Interfaces:**
- Consumes: `SpriteFrame`, `AlphaMask` (existing, internal memberwise inits), `Body`, `Physics`.
- Produces:
  - `enum ItemKind: String, CaseIterable { apple, oranBerry, pokeBall }`, `isTreat`
  - `enum ItemArt { static let size = 12; static func frame(for: ItemKind) -> SpriteFrame }` (internal: `grids`, `palette`)
  - `enum ItemEvent: Equatable { pressed, released, dragBegan, dragEnded(velocity:) }`
  - `struct Item: Identifiable { id; kind; body: Body; state: State; init(id:kind:body:state:); wobbleAngle; static let wobbleDuration = 0.6 }`, `Item.State { free, held, flying, wobbling(petID:wobblesLeft:caught:timer:), fading(remaining:) }`

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/PokeToyCoreTests/ItemTests.swift -->
```swift
import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct ItemTests {
    @Test func gridsAreTwelveByTwelveWithKnownColors() {
        for kind in ItemKind.allCases {
            let rows = ItemArt.grids[kind]!
            #expect(rows.count == ItemArt.size, "\(kind) rows")
            for row in rows {
                #expect(row.count == ItemArt.size, "\(kind) row '\(row)'")
                for symbol in row where symbol != "." {
                    #expect(ItemArt.palette[symbol] != nil, "\(kind) uses unknown color '\(symbol)'")
                }
            }
        }
    }

    @Test func framesRenderWithOpaqueCenters() {
        for kind in ItemKind.allCases {
            let frame = ItemArt.frame(for: kind)
            #expect(frame.image.width == 12 && frame.image.height == 12)
            #expect(frame.mask.isOpaque(x: 6, y: 6), "\(kind) center")
            #expect(!frame.mask.isOpaque(x: 0, y: 0), "\(kind) corner")
        }
    }

    @Test func onlyFoodIsATreat() {
        #expect(ItemKind.apple.isTreat)
        #expect(ItemKind.oranBerry.isTreat)
        #expect(!ItemKind.pokeBall.isTreat)
    }

    @Test func itemsFallAndLandLikePets() {
        let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))
        let world = World(screens: [screen], surfaces: [Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor)])
        var item = Item(kind: .apple, body: Body(position: CGPoint(x: 500, y: 300)))
        #expect(item.state == .free)
        for _ in 0..<60 { Physics.step(&item.body, dt: 1.0 / 60, world: world) }
        #expect(item.body.surfaceID == -1)
        #expect(item.body.position.y == 50)
    }

    @Test func onlyAGroundedWobblingBallTilts() {
        var ball = Item(kind: .pokeBall, body: Body(position: .zero, surfaceID: -1), state: .flying)
        #expect(ball.wobbleAngle == 0)
        ball.state = .wobbling(petID: UUID(), wobblesLeft: 2, caught: true, timer: Item.wobbleDuration * 0.75)
        #expect(ball.wobbleAngle != 0)
        ball.body.surfaceID = nil
        #expect(ball.wobbleAngle == 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter ItemTests`
Expected: build FAILS with "cannot find 'ItemArt' in scope".

- [ ] **Step 3: Implement ItemArt and Item**

<!-- file: Sources/PokeToyCore/ItemArt.swift -->
```swift
import CoreGraphics
import Foundation

public enum ItemKind: String, CaseIterable, Sendable {
    case apple, oranBerry, pokeBall

    public var isTreat: Bool { self != .pokeBall }
}

/// Pixel art for items, drawn from text grids so no asset files are needed.
public enum ItemArt {
    public static let size = 12

    static let palette: [Character: (UInt8, UInt8, UInt8)] = [
        "K": (24, 20, 28), "R": (224, 48, 56), "r": (150, 24, 40), "W": (248, 248, 248),
        "H": (255, 255, 255), "G": (72, 168, 72), "B": (120, 80, 40), "b": (64, 120, 232),
        "d": (32, 64, 160),
    ]

    static let grids: [ItemKind: [String]] = [
        .apple: [
            ".....BG.....",
            ".....BGG....",
            "...KKBKKK...",
            "..KRRRRRRK..",
            ".KRHRRRRRRK.",
            ".KRHRRRRRRK.",
            ".KRRRRRRRrK.",
            ".KRRRRRRRrK.",
            ".KRRRRRRrrK.",
            "..KRRRrrrK..",
            "...KKrrKK...",
            ".....KK.....",
        ],
        .oranBerry: [
            ".....GG.....",
            "....GGBG....",
            "...KKKBKK...",
            "..KbbbbbbK..",
            ".KbHbbbbbbK.",
            ".KbHbbbbbbK.",
            ".KbbbbbbbdK.",
            ".KbbbbbbddK.",
            ".KbbbbbdddK.",
            "..KbbbdddK..",
            "...KKKKK....",
            "............",
        ],
        .pokeBall: [
            "....KKKK....",
            "..KKRRRRKK..",
            ".KRHRRRRRRK.",
            ".KRRRRRRRRK.",
            "KRRRRKKRRRRK",
            "KKKKKWWKKKKK",
            "KWWWKWWKWWWK",
            ".KWWWKKWWWK.",
            ".KWWWWWWWWK.",
            "..KKWWWWKK..",
            "....KKKK....",
            "............",
        ],
    ]

    private static let cache: [ItemKind: SpriteFrame] = Dictionary(
        uniqueKeysWithValues: ItemKind.allCases.map { ($0, render(grids[$0]!)) })

    /// The item's image and opacity mask.
    public static func frame(for kind: ItemKind) -> SpriteFrame {
        cache[kind]!
    }

    static func render(_ rows: [String]) -> SpriteFrame {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        var opaque = [Bool](repeating: false, count: size * size)
        for (y, row) in rows.prefix(size).enumerated() {
            for (x, symbol) in row.prefix(size).enumerated() {
                guard let (r, g, b) = palette[symbol] else { continue }
                let i = (y * size + x) * 4
                bytes[i] = r
                bytes[i + 1] = g
                bytes[i + 2] = b
                bytes[i + 3] = 255
                opaque[y * size + x] = true
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return SpriteFrame(image: image, mask: AlphaMask(width: size, height: size, opaque: opaque))
    }
}
```

<!-- file: Sources/PokeToyCore/Item.swift -->
```swift
import CoreGraphics
import Foundation

public enum ItemEvent: Equatable, Sendable {
    case pressed
    /// Let go without dragging.
    case released
    case dragBegan
    case dragEnded(velocity: CGVector)
}

/// A treat or Poké Ball in the world. Items use the same `Physics` as pets.
public struct Item: Identifiable, Sendable {
    public enum State: Equatable, Sendable {
        case free
        /// Pressed or dragged by the user; physics is paused.
        case held
        /// A thrown Poké Ball that hasn't hit anything yet.
        case flying
        /// A Poké Ball holding a wild Pokémon; `caught` was decided when it hit.
        case wobbling(petID: UUID, wobblesLeft: Int, caught: Bool, timer: Double)
        case fading(remaining: Double)
    }

    public static let wobbleDuration = 0.6

    public let id: UUID
    public let kind: ItemKind
    public internal(set) var body: Body
    public internal(set) var state: State

    public init(id: UUID = UUID(), kind: ItemKind, body: Body, state: State = .free) {
        self.id = id
        self.kind = kind
        self.body = body
        self.state = state
    }

    /// Tilt for drawing a wobbling ball, in radians.
    public var wobbleAngle: CGFloat {
        guard case .wobbling(_, _, _, let timer) = state, body.isGrounded else { return 0 }
        return sin(CGFloat(timer / Self.wobbleDuration) * .pi * 2) * 0.35
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh --filter ItemTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/ItemArt.swift Sources/PokeToyCore/Item.swift Tests/PokeToyCoreTests/ItemTests.swift
git commit -m "feat: pixel-art items (apple, Oran Berry, Poké Ball)"
```

---

### Task 4: Friendships and new settings

**Files:**
- Create: `Sources/PokeToyCore/Friendships.swift`
- Modify: `Sources/PokeToyCore/Settings.swift` (replace)
- Test: `Tests/PokeToyCoreTests/FriendshipsTests.swift`; append two tests to `Tests/PokeToyCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces:
  - `enum FriendshipLevel: Int, Comparable { stranger, friend, bestFriend }`, `init(points:)`
  - `struct Friendships { points: [String: Int]; init(points:); static func key(_:_:) -> String; func score(_:_:) -> Int; func level(_:_:) -> FriendshipLevel; mutating func add(_:_:_:); mutating func remove(_:); func bestFriend(of:among:) -> UUID? }`
  - `Settings.friendships: [String: Int]` (default `[:]`), `Settings.bestCatchScore: Int` (default 0); `Settings.init(pets:hidden:cursorMode:scale:friendships:bestCatchScore:)` with defaults for the last two.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/PokeToyCoreTests/FriendshipsTests.swift -->
```swift
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct FriendshipsTests {
    let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    let c = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    @Test func keyIsOrderIndependent() {
        #expect(Friendships.key(a, b) == Friendships.key(b, a))
        #expect(Friendships.key(a, b) == "\(a.uuidString)+\(b.uuidString)")
    }

    @Test func levelsFollowPoints() {
        #expect(FriendshipLevel(points: 0) == .stranger)
        #expect(FriendshipLevel(points: 2) == .stranger)
        #expect(FriendshipLevel(points: 3) == .friend)
        #expect(FriendshipLevel(points: 9) == .friend)
        #expect(FriendshipLevel(points: 10) == .bestFriend)
        #expect(FriendshipLevel.stranger < .bestFriend)
    }

    @Test func addingRaisesScoreAndLevel() {
        var friendships = Friendships()
        friendships.add(a, b)
        friendships.add(b, a, 2)
        #expect(friendships.score(a, b) == 3)
        #expect(friendships.level(b, a) == .friend)
        friendships.add(a, a, 5)
        #expect(friendships.points.count == 1)
    }

    @Test func removingAPetDropsItsPairs() {
        var friendships = Friendships()
        friendships.add(a, b, 4)
        friendships.add(b, c, 4)
        friendships.remove(a)
        #expect(friendships.score(a, b) == 0)
        #expect(friendships.score(b, c) == 4)
    }

    @Test func malformedKeysAreDroppedAndReversedKeysNormalized() {
        let reversed = "\(b.uuidString)+\(a.uuidString)"
        let friendships = Friendships(points: ["garbage": 3, "A+B": 2, reversed: 4, Friendships.key(a, c): -1])
        #expect(friendships.points == [Friendships.key(a, b): 4])
    }

    @Test func bestFriendIsTheHighestBestFriendAmongCandidates() {
        var friendships = Friendships()
        friendships.add(a, b, 12)
        friendships.add(a, c, 15)
        #expect(friendships.bestFriend(of: a, among: [a, b, c]) == c)
        #expect(friendships.bestFriend(of: a, among: [b]) == b)
        friendships.remove(b)
        #expect(friendships.bestFriend(of: a, among: [b]) == nil)
        #expect(Friendships().bestFriend(of: a, among: [b, c]) == nil)
    }
}
```

Append inside `SettingsTests` (before its closing brace):

<!-- append-in-suite: Tests/PokeToyCoreTests/SettingsTests.swift -->
```swift
    @Test func roundTripsFriendshipsAndBestScore() {
        let defaults = freshDefaults()
        var settings = Settings.default
        settings.friendships = ["x+y": 4]
        settings.bestCatchScore = 725
        settings.save(to: defaults)
        #expect(Settings.load(from: defaults) == settings)
    }

    @Test func toleratesBadFriendshipsAndBestScore() {
        let defaults = freshDefaults()
        defaults.set(Data(#"{"friendships": "nope", "bestCatchScore": "high", "scale": 1}"#.utf8), forKey: "settings")
        let settings = Settings.load(from: defaults)
        #expect(settings.friendships.isEmpty)
        #expect(settings.bestCatchScore == 0)
        #expect(settings.scale == 1)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter "FriendshipsTests|SettingsTests"`
Expected: build FAILS with "cannot find 'Friendships' in scope" / "value of type 'Settings' has no member 'friendships'".

- [ ] **Step 3: Implement Friendships and extend Settings**

<!-- file: Sources/PokeToyCore/Friendships.swift -->
```swift
import Foundation

public enum FriendshipLevel: Int, Comparable, Sendable {
    case stranger = 0, friend = 1, bestFriend = 2

    public init(points: Int) {
        self = points >= 10 ? .bestFriend : points >= 3 ? .friend : .stranger
    }

    public static func < (lhs: FriendshipLevel, rhs: FriendshipLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Friendship points per unordered pair of pets.
public struct Friendships: Equatable, Sendable {
    public private(set) var points: [String: Int]

    /// Builds from saved points, dropping malformed keys and normalizing key order.
    public init(points: [String: Int] = [:]) {
        var clean: [String: Int] = [:]
        for (key, value) in points {
            let parts = key.split(separator: "+").map(String.init)
            guard parts.count == 2, value > 0,
                  let a = UUID(uuidString: parts[0]), let b = UUID(uuidString: parts[1]), a != b else { continue }
            clean[Self.key(a, b), default: 0] += value
        }
        self.points = clean
    }

    public static func key(_ a: UUID, _ b: UUID) -> String {
        let (first, second) = a.uuidString < b.uuidString ? (a, b) : (b, a)
        return "\(first.uuidString)+\(second.uuidString)"
    }

    public func score(_ a: UUID, _ b: UUID) -> Int {
        points[Self.key(a, b)] ?? 0
    }

    public func level(_ a: UUID, _ b: UUID) -> FriendshipLevel {
        FriendshipLevel(points: score(a, b))
    }

    public mutating func add(_ a: UUID, _ b: UUID, _ amount: Int = 1) {
        guard a != b else { return }
        points[Self.key(a, b), default: 0] += amount
    }

    public mutating func remove(_ id: UUID) {
        points = points.filter { !$0.key.contains(id.uuidString) }
    }

    /// The highest-scoring partner of `id` among `candidates` that is at best-friend level.
    public func bestFriend(of id: UUID, among candidates: [UUID]) -> UUID? {
        candidates
            .filter { $0 != id && level(id, $0) == .bestFriend }
            .max { score(id, $0) < score(id, $1) }
    }
}
```

<!-- file: Sources/PokeToyCore/Settings.swift -->
```swift
import CoreGraphics
import Foundation

public struct PetRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// SpriteCollab path, e.g. `0025` or `0025/0000/0001`.
    public var spritePath: String
    public var displayName: String
    /// Last known feet position; nil means "spawn at the top of the screen".
    public var position: CGPoint?

    public init(id: UUID = UUID(), spritePath: String, displayName: String, position: CGPoint? = nil) {
        self.id = id
        self.spritePath = spritePath
        self.displayName = displayName
        self.position = position
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var pets: [PetRecord]
    public var hidden: Bool
    public var cursorMode: CursorMode
    /// Pixel scale, 1...3.
    public var scale: Int
    /// `Friendships.points`, keyed `"<uuidA>+<uuidB>"`.
    public var friendships: [String: Int]
    public var bestCatchScore: Int

    public static let defaultPet = PetRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
                                             spritePath: "0025", displayName: "Pikachu")
    public static let `default` = Settings(pets: [defaultPet], hidden: false, cursorMode: .off, scale: 2)

    public init(pets: [PetRecord], hidden: Bool, cursorMode: CursorMode, scale: Int,
                friendships: [String: Int] = [:], bestCatchScore: Int = 0) {
        self.pets = pets
        self.hidden = hidden
        self.cursorMode = cursorMode
        self.scale = scale
        self.friendships = friendships
        self.bestCatchScore = bestCatchScore
    }

    private enum CodingKeys: String, CodingKey {
        case pets, hidden, cursorMode, scale, friendships, bestCatchScore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pets = try container.decodeIfPresent([PetRecord].self, forKey: .pets) ?? Self.default.pets
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        cursorMode = (try? container.decodeIfPresent(CursorMode.self, forKey: .cursorMode)) ?? .off
        scale = min(max(try container.decodeIfPresent(Int.self, forKey: .scale) ?? 2, 1), 3)
        friendships = (try? container.decodeIfPresent([String: Int].self, forKey: .friendships)) ?? [:]
        bestCatchScore = (try? container.decodeIfPresent(Int.self, forKey: .bestCatchScore)) ?? 0
    }

    public static func load(from defaults: UserDefaults, key: String = "settings") -> Settings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return .default }
        return settings
    }

    public func save(to defaults: UserDefaults, key: String = "settings") {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh --filter "FriendshipsTests|SettingsTests"`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/Friendships.swift Sources/PokeToyCore/Settings.swift Tests/PokeToyCoreTests/FriendshipsTests.swift Tests/PokeToyCoreTests/SettingsTests.swift
git commit -m "feat: friendship scores and levels, saved with best catch score"
```

---

### Task 5: Complete-sprites flag in the catalog

**Files:**
- Modify: `Sources/PokeToyCore/Catalog.swift` (replace)
- Modify: `Tests/PokeToyCoreTests/CatalogTests.swift` (replace); in `Tests/PokeToyCoreTests/SpriteStoreTests.swift` change one expectation (Step 1)

**Interfaces:**
- Produces: `CatalogEntry(path:displayName:isComplete:)` with `isComplete` defaulting to `false`; `Catalog.filter(_:query:completeOnly:)` with `completeOnly` defaulting to `false`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/PokeToyCoreTests/CatalogTests.swift -->
```swift
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct CatalogTests {
    let json = """
    {
      "0000": {"name": "Missingno_", "sprite_complete": 2, "canon": false, "subgroups": {}},
      "0025": {"name": "Pikachu", "sprite_complete": 2, "sprite_files": {"Walk": true}, "subgroups": {
        "0000": {"name": "", "sprite_complete": 0, "subgroups": {
          "0001": {"name": "Shiny", "sprite_complete": 2, "subgroups": {
            "0002": {"name": "Female", "sprite_complete": 2, "subgroups": {}}}},
          "0000": {"name": "", "sprite_complete": 0, "subgroups": {
            "0002": {"name": "Female", "sprite_complete": 2, "subgroups": {}}}}}},
        "0001": {"name": "Gigantamax", "sprite_complete": 0, "subgroups": {}},
        "0002": {"name": "Rock_Star", "sprite_complete": 1, "subgroups": {}}}},
      "0026": {"name": "Raichu", "sprite_complete": 0, "subgroups": {}}
    }
    """

    @Test func flattensFormsWithSprites() throws {
        let entries = try Catalog.parse(trackerJSON: Data(json.utf8))
        #expect(entries == [
            CatalogEntry(path: "0000", displayName: "Missingno", isComplete: true),
            CatalogEntry(path: "0025", displayName: "Pikachu", isComplete: true),
            CatalogEntry(path: "0025/0000/0000/0002", displayName: "Pikachu (Female)", isComplete: true),
            CatalogEntry(path: "0025/0000/0001", displayName: "Pikachu (Shiny)", isComplete: true),
            CatalogEntry(path: "0025/0000/0001/0002", displayName: "Pikachu (Shiny, Female)", isComplete: true),
            CatalogEntry(path: "0025/0002", displayName: "Pikachu (Rock Star)", isComplete: false),
        ])
    }

    @Test func toleratesMissingFields() throws {
        let entries = try Catalog.parse(trackerJSON: Data(#"{"0001": {"name": "Bulbasaur", "sprite_complete": 1}}"#.utf8))
        #expect(entries == [CatalogEntry(path: "0001", displayName: "Bulbasaur", isComplete: false)])
    }

    @Test func rejectsInvalidJSON() {
        #expect(throws: (any Error).self) { try Catalog.parse(trackerJSON: Data("not json".utf8)) }
    }

    @Test func filtersByNameOrNumber() throws {
        let entries = try Catalog.parse(trackerJSON: Data(json.utf8))
        #expect(Catalog.filter(entries, query: "").count == 6)
        #expect(Catalog.filter(entries, query: "  SHINY ").map(\.path) == ["0025/0000/0001", "0025/0000/0001/0002"])
        #expect(Catalog.filter(entries, query: "25").count == 5)
        #expect(Catalog.filter(entries, query: "zzz").isEmpty)
    }

    @Test func completeOnlyHidesPartialSpriteSets() throws {
        let entries = try Catalog.parse(trackerJSON: Data(json.utf8))
        #expect(Catalog.filter(entries, query: "", completeOnly: true).count == 5)
        #expect(Catalog.filter(entries, query: "rock", completeOnly: true).isEmpty)
        #expect(Catalog.filter(entries, query: "rock", completeOnly: false).count == 1)
    }
}
```

In `Tests/PokeToyCoreTests/SpriteStoreTests.swift`, test `catalogIsCachedAndUsedWhenOffline`, replace
`#expect(try await store.catalog() == [CatalogEntry(path: "0025", displayName: "Pikachu")])`
with
`#expect(try await store.catalog() == [CatalogEntry(path: "0025", displayName: "Pikachu", isComplete: true)])`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter "CatalogTests|SpriteStoreTests"`
Expected: build FAILS with "extra argument 'isComplete' in call".

- [ ] **Step 3: Implement**

<!-- file: Sources/PokeToyCore/Catalog.swift -->
```swift
import Foundation

/// A Pokémon (or form) that has sprites on SpriteCollab.
public struct CatalogEntry: Hashable, Codable, Identifiable, Sendable {
    /// Path under `sprite/`, e.g. `0025` or `0025/0000/0001`.
    public let path: String
    public let displayName: String
    /// SpriteCollab marks the sprite set "Full" (`sprite_complete == 2`, ~35 animations).
    public let isComplete: Bool
    public var id: String { path }

    public init(path: String, displayName: String, isComplete: Bool = false) {
        self.path = path
        self.displayName = displayName
        self.isComplete = isComplete
    }
}

public enum Catalog {
    public static func parse(trackerJSON: Data) throws -> [CatalogEntry] {
        let root = try JSONDecoder().decode([String: TrackerNode].self, from: trackerJSON)
        var entries: [CatalogEntry] = []
        for (id, node) in root {
            let base = cleanName(node.name)
            collect(node, path: id, base: base, qualifiers: [], into: &entries)
        }
        return entries.sorted { $0.path < $1.path }
    }

    public static func filter(_ entries: [CatalogEntry], query: String, completeOnly: Bool = false) -> [CatalogEntry] {
        let pool = completeOnly ? entries.filter(\.isComplete) : entries
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return pool }
        return pool.filter { $0.displayName.lowercased().contains(needle) || $0.path.contains(needle) }
    }

    private static func collect(_ node: TrackerNode, path: String, base: String, qualifiers: [String],
                                into entries: inout [CatalogEntry]) {
        if node.spriteComplete > 0 {
            let name = qualifiers.isEmpty ? base : "\(base) (\(qualifiers.joined(separator: ", ")))"
            entries.append(CatalogEntry(path: path, displayName: name, isComplete: node.spriteComplete >= 2))
        }
        for (id, child) in node.subgroups {
            let label = cleanName(child.name)
            collect(child, path: "\(path)/\(id)", base: base,
                    qualifiers: label.isEmpty ? qualifiers : qualifiers + [label], into: &entries)
        }
    }

    private static func cleanName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    }
}

private struct TrackerNode: Decodable {
    let name: String
    let spriteComplete: Int
    let subgroups: [String: TrackerNode]

    enum CodingKeys: String, CodingKey {
        case name
        case spriteComplete = "sprite_complete"
        case subgroups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        spriteComplete = try container.decodeIfPresent(Int.self, forKey: .spriteComplete) ?? 0
        subgroups = try container.decodeIfPresent([String: TrackerNode].self, forKey: .subgroups) ?? [:]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh --filter "CatalogTests|SpriteStoreTests"`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/Catalog.swift Tests/PokeToyCoreTests/CatalogTests.swift Tests/PokeToyCoreTests/SpriteStoreTests.swift
git commit -m "feat: mark complete sprite sets and filter by them"
```

---
### Task 6: Pet metrics and catch-game rules

**Files:**
- Create: `Sources/PokeToyCore/PetMetrics.swift`, `Sources/PokeToyCore/CatchGame.swift`
- Test: `Tests/PokeToyCoreTests/CatchGameTests.swift`

**Interfaces:**
- Consumes: `SpriteSet`, `PetAnim`, `SplitMix64`.
- Produces:
  - `struct PetMetrics: Equatable { durations: [PetAnim: [Int]]; frameSizes: [PetAnim: CGSize]; init(durations:frameSizes:); init(sprites:); static func uniform(width:height:durations:) -> PetMetrics }`
  - `struct WildSpec: Equatable { path; displayName; metrics }`, `struct CatchRecord: Equatable { petID; path; displayName; position }`, `struct CatchResults: Equatable { score; catches }`
  - `struct CatchGame { enum Phase { countdown(remaining:), playing(remaining:), finished }; roster; phase; score; catches; isPlaying; isActive; init(roster:seed:); requestEnd(); advance(dt:) -> Bool; spawn(dt:wildCount:) -> WildSpec?; wildLifetime() -> Double; rollCatch() -> (caught: Bool, wobbles: Int); randomUnit() -> Double; recordHit(); recordCatch(_:); static func keepable(_:ownPetCount:cap:) -> Int }`; internal `catchChance` (tests set it); constants `countdownLength = 3`, `roundLength = 60`, `maxWild = 3`, `maxBallsInFlight = 8`, `defaultCatchChance = 0.6`, `hitPoints = 25`, `catchPoints = 100`, `spawnInterval = 4...7`, `lifetime = 12...20`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/PokeToyCoreTests/CatchGameTests.swift -->
```swift
import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct CatchGameTests {
    let spec = WildSpec(path: "0025", displayName: "Pikachu", metrics: .uniform())

    /// Advances `seconds` in 1/60 s steps and returns how many steps reported the round finishing.
    @discardableResult
    func advance(_ game: inout CatchGame, seconds: Double) -> Int {
        var finishes = 0
        for _ in 0..<Int((seconds * 60).rounded()) where game.advance(dt: 1.0 / 60) { finishes += 1 }
        return finishes
    }

    @Test func metricsComeFromTheSpriteSet() throws {
        let dir = makeTempDirectory()
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk", width: 8, height: 6, durations: [2, 4])])
        let metrics = PetMetrics(sprites: try SpriteSet(directory: dir))
        #expect(metrics.durations[.walk] == [2, 4])
        #expect(metrics.frameSizes[.eat] == CGSize(width: 8, height: 6))
        #expect(PetMetrics.uniform().frameSizes[.idle] == CGSize(width: 32, height: 40))
    }

    @Test func countsDownThenPlaysThenFinishesOnce() {
        var game = CatchGame(roster: [spec], seed: 1)
        #expect(game.phase == .countdown(remaining: 3))
        advance(&game, seconds: 2.9)
        #expect(!game.isPlaying)
        #expect(game.isActive)
        advance(&game, seconds: 0.2)
        #expect(game.isPlaying)
        #expect(advance(&game, seconds: 61) == 1)
        #expect(game.phase == .finished)
        #expect(!game.isActive)
    }

    @Test func requestingTheEndFinishesOnTheNextStep() {
        var countingDown = CatchGame(roster: [spec], seed: 1)
        countingDown.requestEnd()
        #expect(countingDown.advance(dt: 1.0 / 60))
        #expect(countingDown.phase == .finished)

        var playing = CatchGame(roster: [spec], seed: 1)
        advance(&playing, seconds: 4)
        playing.requestEnd()
        #expect(playing.advance(dt: 1.0 / 60))
    }

    @Test func noSpawnsDuringCountdownAndTheFirstSoonAfterGo() {
        var game = CatchGame(roster: [spec], seed: 2)
        for _ in 0..<(3 * 60 - 2) {
            game.advance(dt: 1.0 / 60)
            #expect(game.spawn(dt: 1.0 / 60, wildCount: 0) == nil)
        }
        var spawnedAt: Int?
        for step in 0..<120 {
            game.advance(dt: 1.0 / 60)
            if game.spawn(dt: 1.0 / 60, wildCount: 0) != nil { spawnedAt = step; break }
        }
        #expect(spawnedAt != nil)
        #expect((spawnedAt ?? 999) <= 40)
    }

    @Test func respectsTheWildCap() {
        var game = CatchGame(roster: [spec], seed: 3)
        advance(&game, seconds: 3.1)
        for _ in 0..<(20 * 60) {
            game.advance(dt: 1.0 / 60)
            #expect(game.spawn(dt: 1.0 / 60, wildCount: CatchGame.maxWild) == nil)
        }
    }

    @Test func spawnsEveryFourToSevenSeconds() {
        var game = CatchGame(roster: [spec], seed: 4)
        advance(&game, seconds: 3.1)
        var times: [Double] = []
        for step in 0..<(55 * 60) {
            game.advance(dt: 1.0 / 60)
            if game.spawn(dt: 1.0 / 60, wildCount: 0) != nil { times.append(Double(step) / 60) }
        }
        #expect(times.count >= 7)
        for (earlier, later) in zip(times, times.dropFirst()) {
            #expect(later - earlier >= 4 - 0.02 && later - earlier <= 7 + 0.02)
        }
    }

    @Test func emptyRosterNeverSpawns() {
        var game = CatchGame(roster: [], seed: 5)
        advance(&game, seconds: 3.1)
        for _ in 0..<(10 * 60) { #expect(game.spawn(dt: 1.0 / 60, wildCount: 0) == nil) }
    }

    @Test func lifetimesAreTwelveToTwentySeconds() {
        var game = CatchGame(roster: [spec], seed: 6)
        for _ in 0..<200 {
            let lifetime = game.wildLifetime()
            #expect(lifetime >= 12 && lifetime <= 20)
        }
    }

    @Test func catchRollsMatchTheChance() {
        var game = CatchGame(roster: [spec], seed: 7)
        var caught = 0
        var wobbleCounts = Set<Int>()
        for _ in 0..<2000 {
            let roll = game.rollCatch()
            if roll.caught { caught += 1 }
            wobbleCounts.insert(roll.wobbles)
        }
        #expect(Double(caught) / 2000 > 0.55 && Double(caught) / 2000 < 0.65)
        #expect(wobbleCounts == [1, 2, 3])
    }

    @Test func scoring() {
        var game = CatchGame(roster: [spec], seed: 8)
        game.recordHit()
        #expect(game.score == 25)
        game.recordCatch(CatchRecord(petID: UUID(), path: "0025", displayName: "Pikachu", position: .zero))
        #expect(game.score == 125)
        #expect(game.catches.count == 1)
    }

    @Test func keepableRespectsThePetCap() {
        let record = CatchRecord(petID: UUID(), path: "0025", displayName: "Pikachu", position: .zero)
        #expect(CatchGame.keepable([record, record, record], ownPetCount: 10, cap: 12) == 2)
        #expect(CatchGame.keepable([record], ownPetCount: 12, cap: 12) == 0)
        #expect(CatchGame.keepable([record], ownPetCount: 1, cap: 12) == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter CatchGameTests`
Expected: build FAILS with "cannot find 'WildSpec' in scope".

- [ ] **Step 3: Implement PetMetrics and CatchGame**

<!-- file: Sources/PokeToyCore/PetMetrics.swift -->
```swift
import CoreGraphics

/// Per-animation frame timing and size for one Pokémon — what the simulation needs from its sprites.
public struct PetMetrics: Equatable, Sendable {
    public var durations: [PetAnim: [Int]]
    /// Frame size in sprite pixels.
    public var frameSizes: [PetAnim: CGSize]

    public init(durations: [PetAnim: [Int]], frameSizes: [PetAnim: CGSize]) {
        self.durations = durations
        self.frameSizes = frameSizes
    }

    public init(sprites: SpriteSet) {
        var durations: [PetAnim: [Int]] = [:]
        var sizes: [PetAnim: CGSize] = [:]
        for kind in PetAnim.allCases {
            let animation = sprites.animation(kind)
            durations[kind] = animation.durations
            sizes[kind] = CGSize(width: animation.info.frameWidth, height: animation.info.frameHeight)
        }
        self.init(durations: durations, frameSizes: sizes)
    }

    /// The same size and timing for every animation (tests and fallbacks).
    public static func uniform(width: CGFloat = 32, height: CGFloat = 40, durations: [Int] = [4, 4]) -> PetMetrics {
        PetMetrics(durations: Dictionary(uniqueKeysWithValues: PetAnim.allCases.map { ($0, durations) }),
                   frameSizes: Dictionary(uniqueKeysWithValues: PetAnim.allCases.map { ($0, CGSize(width: width, height: height)) }))
    }
}
```

<!-- file: Sources/PokeToyCore/CatchGame.swift -->
```swift
import CoreGraphics
import Foundation

/// A Pokémon that can appear in a catch round.
public struct WildSpec: Equatable, Sendable {
    public let path: String
    public let displayName: String
    public let metrics: PetMetrics

    public init(path: String, displayName: String, metrics: PetMetrics) {
        self.path = path
        self.displayName = displayName
        self.metrics = metrics
    }
}

public struct CatchRecord: Equatable, Sendable {
    public let petID: UUID
    public let path: String
    public let displayName: String
    /// Where the ball was when the Pokémon was caught; kept Pokémon appear here.
    public let position: CGPoint

    public init(petID: UUID, path: String, displayName: String, position: CGPoint) {
        self.petID = petID
        self.path = path
        self.displayName = displayName
        self.position = position
    }
}

public struct CatchResults: Equatable, Sendable {
    public let score: Int
    public let catches: [CatchRecord]

    public init(score: Int, catches: [CatchRecord]) {
        self.score = score
        self.catches = catches
    }
}

/// Timers, spawning, catch rolls and score for one timed catch round.
public struct CatchGame: Sendable {
    public enum Phase: Equatable, Sendable {
        case countdown(remaining: Double)
        case playing(remaining: Double)
        case finished
    }

    public static let countdownLength = 3.0
    public static let roundLength = 60.0
    public static let maxWild = 3
    public static let maxBallsInFlight = 8
    public static let defaultCatchChance = 0.6
    public static let hitPoints = 25
    public static let catchPoints = 100
    public static let spawnInterval: ClosedRange<Double> = 4...7
    public static let lifetime: ClosedRange<Double> = 12...20

    public let roster: [WildSpec]
    public private(set) var phase: Phase = .countdown(remaining: CatchGame.countdownLength)
    public private(set) var score = 0
    public private(set) var catches: [CatchRecord] = []
    var catchChance = CatchGame.defaultCatchChance
    private var rng: SplitMix64
    private var nextSpawnIn = 0.5
    private var endRequested = false

    public init(roster: [WildSpec], seed: UInt64) {
        self.roster = roster
        rng = SplitMix64(seed: seed)
    }

    public var isPlaying: Bool {
        if case .playing = phase { return true }
        return false
    }

    /// Counting down or playing.
    public var isActive: Bool { phase != .finished }

    public mutating func requestEnd() {
        endRequested = true
    }

    /// Advances the timers. Returns true on the step the round finishes.
    @discardableResult
    public mutating func advance(dt: Double) -> Bool {
        switch phase {
        case .countdown(let remaining):
            if endRequested {
                phase = .finished
                return true
            }
            let left = remaining - dt
            phase = left > 0 ? .countdown(remaining: left) : .playing(remaining: Self.roundLength)
        case .playing(let remaining):
            let left = remaining - dt
            if endRequested || left <= 0 {
                phase = .finished
                return true
            }
            phase = .playing(remaining: left)
        case .finished:
            break
        }
        return false
    }

    /// A wild Pokémon to spawn this step, if one is due and there is room.
    public mutating func spawn(dt: Double, wildCount: Int) -> WildSpec? {
        guard isPlaying, !roster.isEmpty else { return nil }
        nextSpawnIn -= dt
        guard nextSpawnIn <= 0, wildCount < Self.maxWild else { return nil }
        nextSpawnIn = random(in: Self.spawnInterval)
        return roster[min(Int(rng.unit() * Double(roster.count)), roster.count - 1)]
    }

    public mutating func wildLifetime() -> Double {
        random(in: Self.lifetime)
    }

    /// Decides at the moment of a hit whether the Pokémon will be caught and how often the ball wobbles first.
    public mutating func rollCatch() -> (caught: Bool, wobbles: Int) {
        let caught = rng.unit() < catchChance
        let wobbles = 1 + min(Int(rng.unit() * 3), 2)
        return (caught, wobbles)
    }

    public mutating func randomUnit() -> Double {
        rng.unit()
    }

    public mutating func recordHit() {
        score += Self.hitPoints
    }

    public mutating func recordCatch(_ record: CatchRecord) {
        score += Self.catchPoints
        catches.append(record)
    }

    /// How many of `catches` can still become pets without exceeding `cap`.
    public static func keepable(_ catches: [CatchRecord], ownPetCount: Int, cap: Int) -> Int {
        max(0, min(catches.count, cap - ownPetCount))
    }

    private mutating func random(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + rng.unit() * (range.upperBound - range.lowerBound)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh --filter CatchGameTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/PetMetrics.swift Sources/PokeToyCore/CatchGame.swift Tests/PokeToyCoreTests/CatchGameTests.swift
git commit -m "feat: catch game rules and pet metrics"
```

---

### Task 7: Playground core

**Files:**
- Create: `Sources/PokeToyCore/Playground.swift`
- Modify: `Tests/PokeToyCoreTests/TestSupport.swift` (append helpers)
- Test: `Tests/PokeToyCoreTests/PlaygroundTests.swift`

**Interfaces:**
- Consumes: `PetBrain`, `Script`, `PetEvent`, `Personality` (Task 2); `Item`, `ItemKind`, `ItemEvent`, `ItemArt` (Task 3); `Friendships` (Task 4); `PetMetrics`, `CatchGame`, `CatchResults`, `WildSpec` (Task 6); `Physics`, `World`, `Animator`.
- Produces:
  - `enum PetRole { own, wild }`
  - `struct PetActor { id; role; metrics; brain; body; animator; visible; scale; pose; halfWidth; bodyRect; hitRect }` (internal: `poseToken`, `lifetime`, `leaving`, `wasSleeping`)
  - `enum MomentKind { greet, tag, playFight }`
  - `enum PlaygroundEvent: Equatable { friendshipChanged, momentStarted(MomentKind), treatEaten(petID:), wildSpawned(petID:path:), wildRemoved(petID:), ballHit(petID:), caught(petID:), brokeFree(petID:), roundEnded }`
  - `struct Playground { static maxOwnPets = 12, maxTreats = 10; pets; items; friendships; game; lastResults; scale; init(seed:scale:friendships:); pet(_:); canDropTreat; ballsInFlight; addPet(id:role:metrics:at:) -> UUID; removePet(_:); setScale(_:); handle(_: PetEvent, pet:); movePet(_:to:); dropTreat(_:at:) -> UUID?; handle(_: ItemEvent, item:); moveItem(_:to:); tick(dt:world:cursor:cursorMode:) -> [PlaygroundEvent] }`
  - Internal state for later tasks: `rng`, `moments: [ActiveMoment]`, `pairCooldowns`, `knockCooldowns`, `followTimers`, `treatTargets`, `wildSpecs`, `fleeBoost`, `events`; hooks `rulesBeforePhysics(dt:world:)`, `rulesAfterPhysics(dt:world:)` (empty here; later tasks fill them); helpers `index(of:)`, `itemIndex(of:)`, `inMoment(_:)`.
  - Internal `PetActor` wrappers that call the brain with the actor's own body (avoids overlapping access to `pets`): `update(_:)`, `handle(_:)`, `perform(_:) -> Bool`, `endScript()`, `fallAsleep() -> Bool`, `jump(to:x:) -> Bool`. Later tasks always use these instead of `pets[i].brain.x(body: &pets[i].body)`.
  - Test helpers: `TestWorld.{screen, floor, shelf, floorOnly, withShelf}`, `farAway`, `play(_:seconds:world:cursor:mode:) -> [PlaygroundEvent]`, `playUntil(_:seconds:world:cursor:mode:_:) -> (met: Bool, events: [PlaygroundEvent])`, `makePlayground(_:seed:scale:world:) -> (Playground, [UUID])`.

- [ ] **Step 1: Write the test helpers and the failing tests**

Append to the end of `Tests/PokeToyCoreTests/TestSupport.swift`:

<!-- append: Tests/PokeToyCoreTests/TestSupport.swift -->
```swift

// MARK: - Playground helpers

enum TestWorld {
    static let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                   visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))
    static let floor = Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor)
    static let shelf = Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)
    static let floorOnly = World(screens: [screen], surfaces: [floor])
    static let withShelf = World(screens: [screen], surfaces: [floor, shelf])
}

let farAway = CGPoint(x: -5000, y: -5000)

/// Ticks the playground for `seconds` at 60 Hz and returns every event.
@discardableResult
func play(_ playground: inout Playground, seconds: Double, world: World = TestWorld.floorOnly,
          cursor: CGPoint = farAway, mode: CursorMode = .off) -> [PlaygroundEvent] {
    var events: [PlaygroundEvent] = []
    for _ in 0..<Int((seconds * 60).rounded()) {
        events += playground.tick(dt: 1.0 / 60, world: world, cursor: cursor, cursorMode: mode)
    }
    return events
}

/// Ticks until `condition` holds (checked after every tick, at most `seconds`).
@discardableResult
func playUntil(_ playground: inout Playground, seconds: Double, world: World = TestWorld.floorOnly,
               cursor: CGPoint = farAway, mode: CursorMode = .off,
               _ condition: (Playground, [PlaygroundEvent]) -> Bool) -> (met: Bool, events: [PlaygroundEvent]) {
    var events: [PlaygroundEvent] = []
    for _ in 0..<Int((seconds * 60).rounded()) {
        events += playground.tick(dt: 1.0 / 60, world: world, cursor: cursor, cursorMode: mode)
        if condition(playground, events) { return (true, events) }
    }
    return (false, events)
}

/// A playground with one own pet standing on the floor at each x.
func makePlayground(_ xs: [CGFloat], seed: UInt64 = 1, scale: CGFloat = 1,
                    world: World = TestWorld.floorOnly) -> (Playground, [UUID]) {
    var playground = Playground(seed: seed, scale: scale)
    let ids = xs.map { playground.addPet(metrics: .uniform(), at: CGPoint(x: $0, y: TestWorld.floor.y + 1)) }
    play(&playground, seconds: 0.05, world: world)
    return (playground, ids)
}
```

<!-- file: Tests/PokeToyCoreTests/PlaygroundTests.swift -->
```swift
import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct PlaygroundTests {
    @Test func addedPetsFallAndLand() {
        var playground = Playground(seed: 1, scale: 1)
        let id = playground.addPet(metrics: .uniform(), at: CGPoint(x: 500, y: 400))
        play(&playground, seconds: 1)
        #expect(playground.pet(id)?.body.surfaceID == -1)
        #expect(playground.pet(id)?.role == .own)
        #expect(playground.pet(id)?.brain.personality == .pet)
    }

    @Test func clicksReachTheBrainAndTheReactionEnds() {
        var (playground, ids) = makePlayground([500])
        playground.handle(.click, pet: ids[0])
        #expect(playground.pet(ids[0])?.brain.state == .react)
        play(&playground, seconds: 0.5)
        #expect(playground.pet(ids[0])?.brain.isFree == true)
    }

    @Test func draggedPetsStayWhereTheyAreMoved() {
        var (playground, ids) = makePlayground([500])
        playground.handle(.dragBegan, pet: ids[0])
        playground.movePet(ids[0], to: CGPoint(x: 300, y: 500))
        play(&playground, seconds: 0.5)
        #expect(playground.pet(ids[0])?.body.position == CGPoint(x: 300, y: 500))
        playground.handle(.dragEnded(velocity: .zero), pet: ids[0])
        play(&playground, seconds: 1)
        #expect(playground.pet(ids[0])?.body.isGrounded == true)
    }

    @Test func ownPetsLostOffScreenRespawn() {
        var (playground, ids) = makePlayground([500])
        playground.handle(.dragBegan, pet: ids[0])
        playground.movePet(ids[0], to: CGPoint(x: 500, y: -2000))
        playground.handle(.dragEnded(velocity: .zero), pet: ids[0])
        play(&playground, seconds: 1.0 / 60)
        #expect((playground.pet(ids[0])?.body.position.y ?? 0) > 700)
    }

    @Test func wildPetsLeavingTheScreenAreRemoved() {
        var playground = Playground(seed: 1, scale: 1)
        let id = playground.addPet(role: .wild, metrics: .uniform(), at: CGPoint(x: 500, y: 51))
        #expect(playground.pet(id)?.brain.personality == .wild)
        playground.movePet(id, to: CGPoint(x: 1300, y: 51))
        let events = play(&playground, seconds: 1.0 / 60)
        #expect(playground.pet(id) == nil)
        #expect(events.contains(.wildRemoved(petID: id)))
    }

    @Test func removingAPetDropsItsFriendships() {
        var (playground, ids) = makePlayground([300, 600])
        playground.friendships.add(ids[0], ids[1], 5)
        playground.removePet(ids[0])
        #expect(playground.pet(ids[0]) == nil)
        #expect(playground.friendships.score(ids[0], ids[1]) == 0)
    }

    @Test func treatsDropFallAndAreCapped() {
        var playground = Playground(seed: 1, scale: 1)
        let id = playground.dropTreat(.apple, at: CGPoint(x: 500, y: 400))
        #expect(id != nil)
        #expect(playground.dropTreat(.pokeBall, at: .zero) == nil)
        play(&playground, seconds: 1)
        #expect(playground.items.first?.body.surfaceID == -1)
        for _ in 0..<20 { playground.dropTreat(.oranBerry, at: CGPoint(x: 200, y: 400)) }
        #expect(playground.items.count == Playground.maxTreats)
        #expect(!playground.canDropTreat)
    }

    @Test func treatsCanBeDraggedAndThrown() {
        var playground = Playground(seed: 1, scale: 1)
        let id = playground.dropTreat(.apple, at: CGPoint(x: 500, y: 60))!
        play(&playground, seconds: 0.2)
        playground.handle(.pressed, item: id)
        playground.handle(.dragBegan, item: id)
        playground.moveItem(id, to: CGPoint(x: 300, y: 400))
        play(&playground, seconds: 0.5)
        #expect(playground.items.first?.body.position == CGPoint(x: 300, y: 400))
        playground.handle(.dragEnded(velocity: CGVector(dx: 300, dy: 0)), item: id)
        play(&playground, seconds: 1)
        #expect(playground.items.first?.state == .free)
        #expect((playground.items.first?.body.position.x ?? 0) > 330)
        #expect(playground.items.first?.body.isGrounded == true)
    }

    @Test func pressedTreatsHangUntilReleased() {
        var playground = Playground(seed: 1, scale: 1)
        let id = playground.dropTreat(.apple, at: CGPoint(x: 500, y: 400))!
        playground.handle(.pressed, item: id)
        play(&playground, seconds: 0.5)
        #expect(playground.items.first?.body.position.y == 400)
        playground.handle(.released, item: id)
        play(&playground, seconds: 1)
        #expect(playground.items.first?.body.isGrounded == true)
    }

    @Test func scaleAppliesToEveryPet() {
        var (playground, ids) = makePlayground([300, 600])
        let before = playground.pet(ids[0])!.halfWidth
        playground.setScale(3)
        #expect(abs(playground.pet(ids[1])!.halfWidth - before * 3) < 1e-9)
        let wild = playground.addPet(role: .wild, metrics: .uniform(), at: CGPoint(x: 500, y: 51))
        #expect(playground.pet(wild)?.scale == 3)
    }

    @Test func hiddenActorsAreNotSimulated() {
        var (playground, ids) = makePlayground([500])
        playground.pets[0].visible = false
        playground.movePet(ids[0], to: CGPoint(x: 500, y: 400))
        play(&playground, seconds: 0.5)
        #expect(playground.pet(ids[0])?.body.position.y == 400)
    }

    @Test func rectanglesTrackTheFeet() {
        let (playground, ids) = makePlayground([500], scale: 2)
        let pet = playground.pet(ids[0])!
        #expect(pet.halfWidth == 32 * 2 * 0.3)
        #expect(abs(pet.bodyRect.midX - 500) < 1e-9)
        #expect(pet.bodyRect.minY == 50)
        #expect(pet.hitRect.width == 32 * 2 * 0.8)
        #expect(pet.hitRect.contains(CGPoint(x: 500, y: 80)))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter PlaygroundTests`
Expected: build FAILS with "cannot find 'Playground' in scope".

- [ ] **Step 3: Implement the Playground core**

<!-- file: Sources/PokeToyCore/Playground.swift -->
```swift
import CoreGraphics
import Foundation

public enum PetRole: Equatable, Sendable {
    case own, wild
}

/// One simulated Pokémon: its behavior, body and animation state.
public struct PetActor: Identifiable, Sendable {
    public let id: UUID
    public let role: PetRole
    public let metrics: PetMetrics
    public internal(set) var brain: PetBrain
    public internal(set) var body: Body
    public internal(set) var animator = Animator()
    /// False while caught inside a Poké Ball: not drawn and not simulated.
    public internal(set) var visible = true
    public internal(set) var scale: CGFloat
    var poseToken = -1
    var lifetime: Double = .infinity
    var leaving = false
    var wasSleeping = false

    init(id: UUID, role: PetRole, metrics: PetMetrics, brain: PetBrain, body: Body, scale: CGFloat) {
        self.id = id
        self.role = role
        self.metrics = metrics
        self.brain = brain
        self.body = body
        self.scale = scale
    }

    public var pose: Pose { brain.pose }

    // Brain calls that also need the body. Going through the actor avoids overlapping
    // accesses to the `Playground.pets` array (brain and body of the same element at once).

    mutating func update(_ context: BrainContext) {
        brain.update(context, body: &body)
    }

    mutating func handle(_ event: PetEvent) {
        brain.handle(event, body: &body)
    }

    @discardableResult
    mutating func perform(_ script: Script) -> Bool {
        brain.perform(script, body: &body)
    }

    mutating func endScript() {
        brain.endScript(body: &body)
    }

    @discardableResult
    mutating func fallAsleep() -> Bool {
        brain.fallAsleep(body: &body)
    }

    @discardableResult
    mutating func jump(to surface: Surface, x: CGFloat) -> Bool {
        brain.jump(to: surface, x: x, halfWidth: halfWidth, body: &body)
    }

    var frameSize: CGSize {
        metrics.frameSizes[brain.pose.anim] ?? CGSize(width: 32, height: 40)
    }

    /// Roughly half the visible character's width on screen (frames have transparent padding).
    public var halfWidth: CGFloat { frameSize.width * scale * 0.3 }

    /// The character's approximate body on screen, used for pet-to-pet overlap.
    public var bodyRect: CGRect {
        CGRect(x: body.position.x - halfWidth, y: body.position.y,
               width: halfWidth * 2, height: frameSize.height * scale * 0.6)
    }

    /// The sprite frame shrunk by 20%, used for Poké Ball hits.
    public var hitRect: CGRect {
        let width = frameSize.width * scale, height = frameSize.height * scale
        return CGRect(x: body.position.x - width * 0.4, y: body.position.y, width: width * 0.8, height: height * 0.8)
    }
}

public enum MomentKind: Equatable, Sendable {
    case greet, tag, playFight
}

public enum PlaygroundEvent: Equatable, Sendable {
    case friendshipChanged
    case momentStarted(MomentKind)
    case treatEaten(petID: UUID)
    case wildSpawned(petID: UUID, path: String)
    case wildRemoved(petID: UUID)
    case ballHit(petID: UUID)
    case caught(petID: UUID)
    case brokeFree(petID: UUID)
    case roundEnded
}

/// A social moment in progress between two pets.
struct ActiveMoment: Equatable, Sendable {
    var kind: MomentKind
    /// Greet: either pet. Tag: the chaser. Play-fight: the attacker.
    var a: UUID
    /// Greet: the other pet. Tag: the runner. Play-fight: the defender.
    var b: UUID
    var elapsed: Double = 0
    /// Play-fight: 0 attacking, 1 flinching. Tag: 1 once the roles have swapped.
    var stage = 0
}

/// The whole simulation: pets, items, friendships and the catch game, advanced by `tick`.
public struct Playground: Sendable {
    public static let maxOwnPets = 12
    public static let maxTreats = 10

    public internal(set) var pets: [PetActor] = []
    public internal(set) var items: [Item] = []
    public internal(set) var friendships: Friendships
    public internal(set) var game: CatchGame?
    public internal(set) var lastResults: CatchResults?
    public private(set) var scale: CGFloat

    var rng: SplitMix64
    var moments: [ActiveMoment] = []
    var pairCooldowns: [String: Double] = [:]
    var knockCooldowns: [String: Double] = [:]
    var followTimers: [UUID: Double] = [:]
    /// Pet → the treat it is heading for.
    var treatTargets: [UUID: UUID] = [:]
    var wildSpecs: [UUID: WildSpec] = [:]
    /// Wild Pokémon that just broke out of a ball and will dash away once they land.
    var fleeBoost: Set<UUID> = []
    var events: [PlaygroundEvent] = []

    public init(seed: UInt64, scale: CGFloat = 2, friendships: Friendships = Friendships()) {
        rng = SplitMix64(seed: seed)
        self.scale = scale
        self.friendships = friendships
    }

    // MARK: - Queries

    public func pet(_ id: UUID) -> PetActor? {
        pets.first { $0.id == id }
    }

    public var canDropTreat: Bool {
        game == nil && items.filter { $0.kind.isTreat }.count < Self.maxTreats
    }

    public var ballsInFlight: Int {
        items.filter { $0.state == .flying }.count
    }

    func index(of id: UUID) -> Int? {
        pets.firstIndex { $0.id == id }
    }

    func itemIndex(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    func inMoment(_ id: UUID) -> Bool {
        moments.contains { $0.a == id || $0.b == id }
    }

    // MARK: - Pets

    @discardableResult
    public mutating func addPet(id: UUID = UUID(), role: PetRole = .own, metrics: PetMetrics, at position: CGPoint) -> UUID {
        let brain = PetBrain(seed: rng.next(), personality: role == .own ? .pet : .wild)
        pets.append(PetActor(id: id, role: role, metrics: metrics, brain: brain, body: Body(position: position), scale: scale))
        return id
    }

    public mutating func removePet(_ id: UUID) {
        for moment in moments where moment.a == id || moment.b == id {
            let partner = moment.a == id ? moment.b : moment.a
            if let p = index(of: partner) { pets[p].endScript() }
        }
        moments.removeAll { $0.a == id || $0.b == id }
        let wasOwn = pet(id)?.role == .own
        pets.removeAll { $0.id == id }
        treatTargets[id] = nil
        followTimers[id] = nil
        wildSpecs[id] = nil
        fleeBoost.remove(id)
        if wasOwn {
            friendships.remove(id)
            events.append(.friendshipChanged)
        }
    }

    public mutating func setScale(_ scale: CGFloat) {
        self.scale = scale
        for i in pets.indices { pets[i].scale = scale }
    }

    public mutating func handle(_ event: PetEvent, pet id: UUID) {
        guard let i = index(of: id), pets[i].visible else { return }
        pets[i].handle(event)
    }

    public mutating func movePet(_ id: UUID, to position: CGPoint) {
        guard let i = index(of: id) else { return }
        pets[i].body.position = position
    }

    // MARK: - Items

    /// Adds a treat at `position` (it falls from there). Returns nil at the cap, during a game, or for a non-treat.
    @discardableResult
    public mutating func dropTreat(_ kind: ItemKind, at position: CGPoint) -> UUID? {
        guard kind.isTreat, canDropTreat else { return nil }
        let item = Item(kind: kind, body: Body(position: position))
        items.append(item)
        return item.id
    }

    public mutating func handle(_ event: ItemEvent, item id: UUID) {
        guard let i = itemIndex(of: id), items[i].kind.isTreat else { return }
        switch event {
        case .pressed:
            items[i].state = .held
            items[i].body.velocity = .zero
        case .released:
            guard items[i].state == .held else { return }
            items[i].state = .free
        case .dragBegan:
            items[i].state = .held
            items[i].body.surfaceID = nil
            items[i].body.velocity = .zero
        case .dragEnded(let velocity):
            items[i].state = .free
            items[i].body.surfaceID = nil
            items[i].body.velocity = velocity
        }
    }

    public mutating func moveItem(_ id: UUID, to position: CGPoint) {
        guard let i = itemIndex(of: id) else { return }
        items[i].body.position = position
    }

    // MARK: - Tick

    public mutating func tick(dt: Double, world: World, cursor: CGPoint, cursorMode: CursorMode) -> [PlaygroundEvent] {
        events = []
        Self.decay(&pairCooldowns, dt)
        Self.decay(&knockCooldowns, dt)
        for i in pets.indices where pets[i].visible {
            updateBrain(i, dt: dt, world: world, cursor: cursor, cursorMode: cursorMode)
        }
        rulesBeforePhysics(dt: dt, world: world)
        for i in pets.indices where pets[i].visible && pets[i].brain.state != .dragged {
            Physics.step(&pets[i].body, dt: CGFloat(dt), world: world)
        }
        stepItems(dt: dt, world: world)
        rulesAfterPhysics(dt: dt, world: world)
        for i in pets.indices { advanceAnimation(i, dt: dt) }
        recover(world: world)
        return events
    }

    /// Rules that direct pets before they move (catch game, social moments, feeding).
    mutating func rulesBeforePhysics(dt: Double, world: World) {}

    /// Rules that react to where things ended up (collisions, Poké Ball hits).
    mutating func rulesAfterPhysics(dt: Double, world: World) {}

    private mutating func updateBrain(_ i: Int, dt: Double, world: World, cursor: CGPoint, cursorMode: CursorMode) {
        let pet = pets[i]
        let finished = pet.animator.finished && pet.animator.kind == pet.brain.pose.anim
            && pet.poseToken == pet.brain.pose.token
        let context = BrainContext(dt: dt, world: world, cursor: cursor,
                                   cursorMode: pet.role == .own ? cursorMode : .off,
                                   halfWidth: pet.halfWidth, animationFinished: finished)
        pets[i].update(context)
    }

    private mutating func advanceAnimation(_ i: Int, dt: Double) {
        let pose = pets[i].brain.pose
        pets[i].animator.play(pose.anim)
        if pose.token != pets[i].poseToken {
            pets[i].animator.restart()
            pets[i].poseToken = pose.token
        }
        pets[i].animator.advance(dt: dt, durations: pets[i].metrics.durations[pose.anim] ?? [1])
    }

    private mutating func stepItems(dt: Double, world: World) {
        for i in items.indices {
            switch items[i].state {
            case .held:
                continue
            case .fading(let remaining):
                items[i].state = .fading(remaining: remaining - dt)
            default:
                break
            }
            let landed = Physics.step(&items[i].body, dt: CGFloat(dt), world: world)
            if landed && items[i].state == .flying {
                items[i].state = .fading(remaining: 1.5)  // a ball that hit nothing
            }
        }
        items.removeAll {
            if case .fading(let remaining) = $0.state { return remaining <= 0 }
            return false
        }
    }

    private mutating func recover(world: World) {
        guard !world.screens.isEmpty else { return }
        for i in pets.indices where pets[i].role == .own && pets[i].visible && pets[i].brain.state != .dragged
            && !world.isRecoverable(pets[i].body.position, margin: 200) {
            pets[i].body = Body(position: world.spawnPoint(fraction: 0.5))  // lost off-screen: drop back in
            pets[i].handle(.dragEnded(velocity: .zero))
        }
        let gone = pets.filter {
            $0.role == .wild && $0.visible
                && (!world.isWithinScreens(x: $0.body.position.x) || !world.isRecoverable($0.body.position, margin: 200))
        }.map(\.id)
        for id in gone {
            removePet(id)
            events.append(.wildRemoved(petID: id))
        }
        items.removeAll { item in
            if case .wobbling = item.state { return false }
            return item.state != .held && !world.isRecoverable(item.body.position, margin: 200)
        }
    }

    static func decay(_ timers: inout [String: Double], _ dt: Double) {
        timers = timers.compactMapValues { $0 - dt > 0 ? $0 - dt : nil }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh --filter PlaygroundTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/Playground.swift Tests/PokeToyCoreTests/TestSupport.swift Tests/PokeToyCoreTests/PlaygroundTests.swift
git commit -m "feat: Playground owns pets, items and the tick"
```

---

### Task 8: Feeding

**Files:**
- Create: `Sources/PokeToyCore/Playground+Feeding.swift`
- Modify: `Sources/PokeToyCore/Playground.swift` (hook, Step 3)
- Test: `Tests/PokeToyCoreTests/FeedingTests.swift`

**Interfaces:**
- Consumes: Playground internals (Task 7), `PetBrain.perform/updateScriptTarget/endScript/jump`, `Script` (Task 2).
- Produces: internal `feedingRules(world:)`, `eat(treat:by:)`; constants `Playground.eatDistance = 16`, `treatSightRange = 800`, `sharedTreatRadius = 150`. Emits `.treatEaten(petID:)` and `.friendshipChanged`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/PokeToyCoreTests/FeedingTests.swift -->
```swift
import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct FeedingTests {
    func eaten(_ events: [PlaygroundEvent]) -> UUID? {
        for event in events { if case .treatEaten(let id) = event { return id } }
        return nil
    }

    @Test func aPetWalksToATreatAndEatsIt() {
        var (playground, ids) = makePlayground([300])
        playground.dropTreat(.apple, at: CGPoint(x: 500, y: 300))
        let result = playUntil(&playground, seconds: 10) { _, events in eaten(events) != nil }
        #expect(result.met)
        #expect(eaten(result.events) == ids[0])
        #expect(playground.items.isEmpty)
        #expect(playground.pet(ids[0])?.brain.script?.anim == .eat)
        play(&playground, seconds: 2.6)
        #expect(playground.pet(ids[0])?.pose.anim == .greet)
        #expect(playground.pet(ids[0])?.pose.hearts == 1)
    }

    @Test func closestPetWinsOthersAreSad() {
        var (playground, ids) = makePlayground([250, 700, 900])
        playground.dropTreat(.oranBerry, at: CGPoint(x: 400, y: 300))
        let result = playUntil(&playground, seconds: 10) { _, events in eaten(events) != nil }
        #expect(eaten(result.events) == ids[0])
        #expect(playground.pet(ids[1])?.pose.anim == .sad)
        #expect(playground.pet(ids[2])?.pose.anim == .sad)
        let more = play(&playground, seconds: 3)
        #expect(eaten(more) == nil)
    }

    @Test func sleepingPetsIgnoreTreats() {
        var (playground, ids) = makePlayground([500])
        #expect(playground.pets[0].fallAsleep())
        playground.dropTreat(.apple, at: CGPoint(x: 520, y: 60))
        play(&playground, seconds: 2)
        #expect(playground.items.count == 1)
        #expect(playground.pet(ids[0])?.brain.isSleeping == true)
    }

    @Test func heldTreatsAreIgnored() {
        var (playground, _) = makePlayground([300])
        let treat = playground.dropTreat(.apple, at: CGPoint(x: 350, y: 60))!
        playground.handle(.pressed, item: treat)
        play(&playground, seconds: 3)
        #expect(playground.items.count == 1)
        #expect(playground.treatTargets.isEmpty)
    }

    @Test func petsNearTheTreatBecomeFriendlier() {
        var (playground, ids) = makePlayground([380, 430])
        playground.dropTreat(.apple, at: CGPoint(x: 405, y: 52))
        let result = playUntil(&playground, seconds: 10) { _, events in eaten(events) != nil }
        #expect(result.met)
        #expect(playground.friendships.score(ids[0], ids[1]) >= 1)
        #expect(result.events.contains(.friendshipChanged))
    }

    @Test func treatsOnAReachableWindowAreReachedByJumping() {
        var (playground, ids) = makePlayground([700], world: TestWorld.withShelf)
        playground.dropTreat(.apple, at: CGPoint(x: 450, y: 300))
        let result = playUntil(&playground, seconds: 8, world: TestWorld.withShelf) { _, events in eaten(events) != nil }
        #expect(result.met)
        #expect(playground.pet(ids[0])?.body.surfaceID == 7)
    }

    @Test func unreachableTreatIsIgnored() {
        let high = Surface(id: 9, minX: 300, maxX: 600, y: 600, kind: .window)
        let world = World(screens: [TestWorld.screen], surfaces: [TestWorld.floor, high])
        var (playground, ids) = makePlayground([450], world: world)
        playground.dropTreat(.apple, at: CGPoint(x: 450, y: 650))
        play(&playground, seconds: 3, world: world)
        #expect(playground.items.count == 1)
        #expect(playground.items.first?.body.surfaceID == 9)
        #expect(playground.treatTargets.isEmpty)
        #expect(playground.pet(ids[0])?.body.surfaceID == -1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter FeedingTests`
Expected: tests FAIL (`aPetWalksToATreatAndEatsIt` — expectation `result.met` false: no feeding rules yet).

- [ ] **Step 3: Implement feeding and hook it into the tick**

<!-- file: Sources/PokeToyCore/Playground+Feeding.swift -->
```swift
import CoreGraphics
import Foundation

extension Playground {
    static let eatDistance: CGFloat = 16
    static let treatSightRange: CGFloat = 800
    static let sharedTreatRadius: CGFloat = 150

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
```

In `Sources/PokeToyCore/Playground.swift`, replace

```swift
    mutating func rulesBeforePhysics(dt: Double, world: World) {}
```

with

```swift
    mutating func rulesBeforePhysics(dt: Double, world: World) {
        feedingRules(world: world)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh --filter "FeedingTests|PlaygroundTests"`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/Playground+Feeding.swift Sources/PokeToyCore/Playground.swift Tests/PokeToyCoreTests/FeedingTests.swift
git commit -m "feat: pets race for treats; the winner eats, the rest are sad"
```

---
### Task 9: Social moments, napping together and best-friend following

**Files:**
- Create: `Sources/PokeToyCore/Playground+Social.swift`
- Modify: `Sources/PokeToyCore/Playground.swift` (hook, Step 3)
- Test: `Tests/PokeToyCoreTests/SocialTests.swift`

**Interfaces:**
- Consumes: Playground internals and `PetActor` wrappers (Task 7), `Friendships` (Task 4), `Script` (Task 2).
- Produces: internal `socialRules(dt:world:)`, `startMoment(_:_:kind:)`, `pickMoment(for:) -> MomentKind`, `static momentWeights(_:) -> [(kind: MomentKind, weight: Double)]`, `abort(_:_:)` (used by Task 11), `interrupted(_:) -> Bool`, `facing(from:to:) -> Direction`, `clampOnSurface(_:pet:world:) -> CGFloat` (used by Task 10); constants `tagLength = 5`, `meetingGap = 60`, `followInterval = 8`. Emits `.momentStarted(kind)` and `.friendshipChanged`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/PokeToyCoreTests/SocialTests.swift -->
```swift
import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct SocialTests {
    let cursorBetween = CGPoint(x: 500, y: 60)

    func startedMoment(_ events: [PlaygroundEvent]) -> Bool {
        events.contains { if case .momentStarted = $0 { return true }; return false }
    }

    @Test func petsThatMeetStartAMoment() {
        var (playground, _) = makePlayground([480, 520])
        // Follow mode with the cursor between them keeps both idle side by side.
        let result = playUntil(&playground, seconds: 10, cursor: cursorBetween, mode: .follow) { _, events in
            startedMoment(events)
        }
        #expect(result.met)
    }

    @Test func aCompletedMomentAddsFriendshipAndACooldown() {
        var (playground, ids) = makePlayground([480, 520])
        play(&playground, seconds: 15, cursor: cursorBetween, mode: .follow)
        #expect(playground.friendships.score(ids[0], ids[1]) >= 1)
        #expect((playground.pairCooldowns[Friendships.key(ids[0], ids[1])] ?? 0) > 0)
    }

    @Test func momentChoiceFollowsFriendship() {
        #expect(Playground.momentWeights(.stranger).map(\.weight) == [60, 15, 25])
        #expect(Playground.momentWeights(.friend).map(\.weight) == [40, 30, 30])
        #expect(Playground.momentWeights(.bestFriend).map(\.weight) == [30, 35, 35])
        var playground = Playground(seed: 9)
        var greets = 0
        for _ in 0..<3000 where playground.pickMoment(for: .stranger) == .greet { greets += 1 }
        #expect(Double(greets) / 3000 > 0.55 && Double(greets) / 3000 < 0.65)
    }

    @Test func greetingShowsHeartsByFriendship() {
        for (points, hearts) in [(0, 0), (3, 1), (10, 2)] {
            var (playground, ids) = makePlayground([480, 520])
            if points > 0 { playground.friendships.add(ids[0], ids[1], points) }
            playground.startMoment(0, 1, kind: .greet)
            #expect(playground.pet(ids[0])?.pose == Pose(anim: .greet, facing: .right, hearts: hearts,
                                                         token: playground.pet(ids[0])!.pose.token))
            #expect(playground.pet(ids[1])?.pose.facing == .left)
            #expect(playground.pet(ids[1])?.pose.hearts == hearts)
        }
    }

    @Test func tagChaserChasesThenBothStop() {
        var (playground, ids) = makePlayground([400, 600])
        playground.startMoment(0, 1, kind: .tag)
        let chaser = playground.moments[0].a
        let runner = playground.moments[0].b
        play(&playground, seconds: 0.5)
        let c = playground.pet(chaser)!, r = playground.pet(runner)!
        #expect(c.body.velocity.dx * (r.body.position.x - c.body.position.x) > 0)
        #expect(r.body.velocity.dx * (r.body.position.x - c.body.position.x) > 0)
        play(&playground, seconds: 4.8)
        #expect(playground.moments.isEmpty)
        #expect(playground.friendships.score(ids[0], ids[1]) == 1)
        #expect(playground.pet(ids[0])?.brain.script == nil)
        #expect(playground.pet(ids[1])?.brain.script == nil)
    }

    @Test func playFightAttackThenFlinch() {
        var (playground, ids) = makePlayground([480, 520])
        playground.startMoment(0, 1, kind: .playFight)
        let attacker = playground.moments[0].a
        let defender = playground.moments[0].b
        #expect(playground.pet(attacker)?.pose.anim == .attack)
        let flinch = playUntil(&playground, seconds: 2) { p, _ in p.pet(defender)?.pose.anim == .sad }
        #expect(flinch.met)
        play(&playground, seconds: 1.0 / 60)
        let a = playground.pet(attacker)!, d = playground.pet(defender)!
        #expect(d.body.velocity.dx * (d.body.position.x - a.body.position.x) > 0)
        play(&playground, seconds: 2)
        #expect(playground.moments.isEmpty)
        #expect(playground.friendships.score(ids[0], ids[1]) == 1)
    }

    @Test func interruptedGreetGivesNoFriendship() {
        var (playground, ids) = makePlayground([480, 520])
        playground.startMoment(0, 1, kind: .greet)
        playground.handle(.click, pet: ids[0])
        play(&playground, seconds: 0.1)
        #expect(playground.moments.isEmpty)
        #expect(playground.friendships.score(ids[0], ids[1]) == 0)
        #expect(playground.pet(ids[1])?.brain.script == nil)
    }

    @Test func removingAPartnerEndsTheMoment() {
        var (playground, ids) = makePlayground([400, 600])
        playground.startMoment(0, 1, kind: .tag)
        playground.removePet(ids[1])
        #expect(playground.moments.isEmpty)
        #expect(playground.pet(ids[0])?.brain.script == nil)
    }

    @Test func bestFriendsNapTogether() {
        var (playground, ids) = makePlayground([300, 600])
        playground.friendships.add(ids[0], ids[1], 10)
        #expect(playground.pets[0].fallAsleep())
        let result = playUntil(&playground, seconds: 8) { p, _ in p.pet(ids[1])?.brain.isSleeping == true }
        #expect(result.met)
        let gap = abs(playground.pet(ids[0])!.body.position.x - playground.pet(ids[1])!.body.position.x)
        #expect(gap < 40)
    }

    @Test func strangersDoNotNapTogether() {
        var (playground, ids) = makePlayground([300, 600])
        #expect(playground.pets[0].fallAsleep())
        play(&playground, seconds: 5)
        #expect(playground.pet(ids[1])?.brain.isSleeping == false)
    }

    @Test func bestFriendsSeekEachOtherOut() {
        var (playground, ids) = makePlayground([150, 850])
        playground.friendships.add(ids[0], ids[1], 10)
        let result = playUntil(&playground, seconds: 40) { p, _ in
            abs(p.pet(ids[0])!.body.position.x - p.pet(ids[1])!.body.position.x) < 100
        }
        #expect(result.met)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter SocialTests`
Expected: build FAILS with "value of type 'Playground' has no member 'startMoment'".

- [ ] **Step 3: Implement the social rules and hook them in**

<!-- file: Sources/PokeToyCore/Playground+Social.swift -->
```swift
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
                if moment.stage == 0, abs(pets[i].body.position.x - pets[j].body.position.x) < 20 {
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
```

In `Sources/PokeToyCore/Playground.swift`, replace

```swift
    mutating func rulesBeforePhysics(dt: Double, world: World) {
        feedingRules(world: world)
    }
```

with

```swift
    mutating func rulesBeforePhysics(dt: Double, world: World) {
        socialRules(dt: dt, world: world)
        feedingRules(world: world)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh --filter "SocialTests|FeedingTests|PlaygroundTests"`
Expected: all PASS. If `bestFriendsSeekEachOtherOut` or `petsThatMeetStartAMoment` fail only because the seeded RNG never rolls in time, change the seed passed to `makePlayground` (a ledgered ruling), not the behavior.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/Playground+Social.swift Sources/PokeToyCore/Playground.swift Tests/PokeToyCoreTests/SocialTests.swift
git commit -m "feat: pets greet, play tag, play-fight, nap together and follow best friends"
```

---

### Task 10: Collisions

**Files:**
- Create: `Sources/PokeToyCore/Playground+Collisions.swift`
- Modify: `Sources/PokeToyCore/Playground.swift` (hook, Step 3)
- Test: `Tests/PokeToyCoreTests/CollisionTests.swift`

**Interfaces:**
- Consumes: `PetActor.bodyRect`, wrappers (Task 7), `clampOnSurface` (Task 9), `PetEvent.knocked` (Task 2).
- Produces: internal `collisionRules(world:)`; constant `Playground.knockSpeed = 250`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/PokeToyCoreTests/CollisionTests.swift -->
```swift
import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct CollisionTests {
    func isThrownFall(_ state: PetBrain.State?) -> Bool {
        if case .fall(_, true) = state { return true }
        return false
    }

    @Test func aThrownPetKnocksAnotherOver() {
        var (playground, ids) = makePlayground([500], scale: 2)
        let thrown = playground.addPet(metrics: .uniform(), at: CGPoint(x: 420, y: 120))
        playground.handle(.dragBegan, pet: thrown)
        playground.handle(.dragEnded(velocity: CGVector(dx: 600, dy: 0)), pet: thrown)
        let result = playUntil(&playground, seconds: 1) { p, _ in isThrownFall(p.pet(ids[0])?.brain.state) }
        #expect(result.met)
        #expect(playground.pet(ids[0])?.body.velocity == CGVector(dx: 220, dy: 380))
        #expect(playground.pet(ids[0])?.pose.anim == .dangle)
        #expect((playground.pet(thrown)?.body.velocity.dx ?? 0) < 0)
        #expect((playground.knockCooldowns[Friendships.key(thrown, ids[0])] ?? 0) > 0)
        play(&playground, seconds: 2)
        #expect(playground.pet(ids[0])?.body.isGrounded == true)
        #expect((playground.pet(ids[0])?.body.position.x ?? 0) > 520)
    }

    @Test func aGentleDropDoesNotKnockAnyoneOver() {
        var (playground, ids) = makePlayground([500], scale: 2)
        let dropped = playground.addPet(metrics: .uniform(), at: CGPoint(x: 470, y: 52))
        playground.handle(.dragBegan, pet: dropped)
        playground.handle(.dragEnded(velocity: CGVector(dx: 100, dy: 0)), pet: dropped)
        for _ in 0..<30 {
            play(&playground, seconds: 1.0 / 60)
            #expect(!isThrownFall(playground.pet(ids[0])?.brain.state))
        }
    }

    @Test func petsWalkingIntoEachOtherTurnAround() {
        var (playground, _) = makePlayground([450, 470], scale: 2)
        let world = TestWorld.floorOnly
        playground.pets[0].update(BrainContext(dt: 1.0 / 60, world: world, cursor: CGPoint(x: 900, y: 60),
                                               cursorMode: .follow, halfWidth: playground.pets[0].halfWidth,
                                               animationFinished: false))
        playground.pets[1].update(BrainContext(dt: 1.0 / 60, world: world, cursor: CGPoint(x: 0, y: 60),
                                               cursorMode: .follow, halfWidth: playground.pets[1].halfWidth,
                                               animationFinished: false))
        #expect(playground.pets[0].body.velocity.dx > 0)
        #expect(playground.pets[1].body.velocity.dx < 0)
        playground.collisionRules(world: world)
        #expect(playground.pets[0].brain.script?.moveTo == 390)
        #expect(playground.pets[1].brain.script?.moveTo == 530)
    }

    @Test func wildPokemonAreNeverKnocked() {
        var playground = Playground(seed: 1, scale: 2)
        let wild = playground.addPet(role: .wild, metrics: .uniform(), at: CGPoint(x: 500, y: 51))
        let thrown = playground.addPet(metrics: .uniform(), at: CGPoint(x: 420, y: 120))
        play(&playground, seconds: 1.0 / 60)
        playground.handle(.dragBegan, pet: thrown)
        playground.handle(.dragEnded(velocity: CGVector(dx: 600, dy: 0)), pet: thrown)
        for _ in 0..<60 {
            play(&playground, seconds: 1.0 / 60)
            #expect(!isThrownFall(playground.pet(wild)?.brain.state))
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter CollisionTests`
Expected: build FAILS with "value of type 'Playground' has no member 'collisionRules'".

- [ ] **Step 3: Implement collisions and hook them in**

<!-- file: Sources/PokeToyCore/Playground+Collisions.swift -->
```swift
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
                let direction: CGFloat = pets[y].body.position.x >= pets[x].body.position.x ? 1 : -1
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
```

In `Sources/PokeToyCore/Playground.swift`, replace

```swift
    mutating func rulesAfterPhysics(dt: Double, world: World) {}
```

with

```swift
    mutating func rulesAfterPhysics(dt: Double, world: World) {
        collisionRules(world: world)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh --filter "CollisionTests|SocialTests|FeedingTests|PlaygroundTests"`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/Playground+Collisions.swift Sources/PokeToyCore/Playground.swift Tests/PokeToyCoreTests/CollisionTests.swift
git commit -m "feat: thrown pets knock others over; walkers bump and turn"
```

---

### Task 11: The catch game inside the Playground

**Files:**
- Create: `Sources/PokeToyCore/Playground+Game.swift`
- Modify: `Sources/PokeToyCore/Playground.swift` (hooks, Step 3)
- Test: `Tests/PokeToyCoreTests/GameTests.swift`

**Interfaces:**
- Consumes: `CatchGame`, `WildSpec`, `CatchRecord`, `CatchResults` (Task 6); Playground internals and wrappers (Task 7); `abort` (Task 9); `Item` (Task 3).
- Produces: `Playground.startGame(roster:seed:)`, `endGame()`, `throwBall(from:velocity:) -> Bool`; internal `gameRulesBeforePhysics(dt:world:)`, `gameRulesAfterPhysics(dt:)`. Emits `.wildSpawned`, `.ballHit`, `.caught`, `.wildRemoved`, `.brokeFree`, `.roundEnded`; sets `lastResults`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/PokeToyCoreTests/GameTests.swift -->
```swift
import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct GameTests {
    let spec = WildSpec(path: "0025", displayName: "Pikachu", metrics: .uniform())

    func started(_ xs: [CGFloat] = [500]) -> (Playground, [UUID]) {
        var (playground, ids) = makePlayground(xs)
        playground.startGame(roster: [spec], seed: 3)
        return (playground, ids)
    }

    func wild(_ playground: Playground) -> PetActor? {
        playground.pets.first { $0.role == .wild }
    }

    /// Plays until a wild Pokémon stands on the floor, and returns it.
    func untilWildLands(_ playground: inout Playground) -> PetActor? {
        playUntil(&playground, seconds: 6) { p, _ in wild(p)?.body.isGrounded == true }
        return wild(playground)
    }

    func ballAbove(_ pet: PetActor) -> CGPoint {
        CGPoint(x: pet.body.position.x, y: pet.body.position.y + 10)
    }

    @Test func wildPokemonArriveAfterTheCountdown() {
        var (playground, _) = started()
        let early = play(&playground, seconds: 2.9)
        #expect(!early.contains { if case .wildSpawned = $0 { return true }; return false })
        let later = play(&playground, seconds: 1)
        let arrived = wild(playground)
        #expect(arrived != nil)
        #expect(later.contains(.wildSpawned(petID: arrived!.id, path: "0025")))
        #expect(arrived?.brain.personality == .wild)
    }

    @Test func ownPetsSitWhileTreatsAndMomentsPause() {
        var (playground, ids) = started([490, 510])
        play(&playground, seconds: 0.1)
        #expect(playground.pet(ids[0])?.brain.script?.anim == .sit)
        #expect(playground.pet(ids[0])?.brain.script?.priority == 3)
        #expect(!playground.canDropTreat)
        #expect(playground.dropTreat(.apple, at: CGPoint(x: 500, y: 300)) == nil)
        play(&playground, seconds: 5)
        #expect(playground.moments.isEmpty)
    }

    @Test func aHitScoresAndACatchIsRecorded() {
        var (playground, ids) = started()
        playground.game!.catchChance = 1
        let target = untilWildLands(&playground)!
        #expect(playground.throwBall(from: ballAbove(target), velocity: .zero))
        let hit = play(&playground, seconds: 1.0 / 60)
        #expect(hit.contains(.ballHit(petID: target.id)))
        #expect(playground.game?.score == 25)
        #expect(playground.pet(target.id)?.visible == false)
        let result = playUntil(&playground, seconds: 3) { _, events in events.contains(.caught(petID: target.id)) }
        #expect(result.met)
        #expect(result.events.contains(.wildRemoved(petID: target.id)))
        #expect(playground.game?.score == 125)
        #expect(playground.game?.catches.map(\.displayName) == ["Pikachu"])
        #expect(playground.pet(target.id) == nil)
        #expect(playground.pet(ids[0])?.brain.script?.anim == .cheer)
    }

    @Test func aWildThatBreaksFreeComesBack() {
        var (playground, _) = started()
        playground.game!.catchChance = 0
        let target = untilWildLands(&playground)!
        playground.throwBall(from: ballAbove(target), velocity: .zero)
        let result = playUntil(&playground, seconds: 3) { _, events in events.contains(.brokeFree(petID: target.id)) }
        #expect(result.met)
        #expect(playground.pet(target.id)?.visible == true)
        #expect(playground.game?.score == 25)
        #expect(!playground.items.contains { if case .wobbling = $0.state { return true }; return false })
    }

    @Test func theRoundEndsWithResults() {
        var (playground, ids) = started()
        let events = play(&playground, seconds: 63.2)
        #expect(events.contains(.roundEnded))
        #expect(playground.game == nil)
        #expect(playground.lastResults != nil)
        #expect((playground.pet(ids[0])?.brain.script?.priority ?? 0) < 3)
        #expect(playground.canDropTreat)
    }

    @Test func endingMidWobbleResolvesTheCatch() {
        var (playground, _) = started()
        playground.game!.catchChance = 1
        let target = untilWildLands(&playground)!
        playground.throwBall(from: ballAbove(target), velocity: .zero)
        play(&playground, seconds: 1.0 / 60)
        playground.endGame()
        let events = play(&playground, seconds: 1.0 / 60)
        #expect(events.contains(.roundEnded))
        #expect(events.contains(.caught(petID: target.id)))
        #expect(playground.lastResults?.catches.map(\.petID) == [target.id])
        #expect(!playground.pets.contains { !$0.visible })
    }

    @Test func wildPokemonLeaveWhenTheirTimeIsUp() {
        var (playground, _) = started()
        let target = untilWildLands(&playground)!
        let index = playground.pets.firstIndex { $0.id == target.id }!
        playground.pets[index].lifetime = 0.05
        let result = playUntil(&playground, seconds: 12) { _, events in events.contains(.wildRemoved(petID: target.id)) }
        #expect(result.met)
    }

    @Test func throwsOnlyWhilePlayingAndAtMostEightInFlight() {
        var (playground, _) = started()
        let up = CGVector(dx: 0, dy: 800)
        #expect(!playground.throwBall(from: CGPoint(x: 500, y: 600), velocity: up))
        play(&playground, seconds: 3.1)
        for _ in 0..<CatchGame.maxBallsInFlight {
            #expect(playground.throwBall(from: CGPoint(x: 500, y: 600), velocity: up))
        }
        #expect(!playground.throwBall(from: CGPoint(x: 500, y: 600), velocity: up))
        #expect(playground.ballsInFlight == CatchGame.maxBallsInFlight)
    }

    @Test func ballsPassThroughOwnPets() {
        var (playground, ids) = started()
        play(&playground, seconds: 3.1)
        playground.throwBall(from: ballAbove(playground.pet(ids[0])!), velocity: .zero)
        let events = play(&playground, seconds: 1)
        #expect(!events.contains { if case .ballHit = $0 { return true }; return false })
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter GameTests`
Expected: build FAILS with "value of type 'Playground' has no member 'startGame'".

- [ ] **Step 3: Implement the game rules and hook them in**

<!-- file: Sources/PokeToyCore/Playground+Game.swift -->
```swift
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
        game = CatchGame(roster: roster, seed: seed)
        lastResults = nil
    }

    public mutating func endGame() {
        game?.requestEnd()
    }

    /// Throws a Poké Ball from `position`. Only while playing, and at most `CatchGame.maxBallsInFlight` at once.
    @discardableResult
    public mutating func throwBall(from position: CGPoint, velocity: CGVector) -> Bool {
        guard game?.isPlaying == true, ballsInFlight < CatchGame.maxBallsInFlight else { return false }
        items.append(Item(kind: .pokeBall, body: Body(position: position, velocity: velocity), state: .flying))
        return true
    }

    mutating func gameRulesBeforePhysics(dt: Double, world: World) {
        if game != nil {
            if game!.advance(dt: dt) {
                finishRound()
            } else {
                if game!.isActive { keepOwnPetsSitting() }
                let wildCount = pets.filter { $0.role == .wild }.count
                if let spec = game!.spawn(dt: dt, wildCount: wildCount) { spawnWild(spec, world: world) }
            }
        }
        driveWild(dt: dt, world: world)
    }

    mutating func gameRulesAfterPhysics(dt: Double) {
        if game?.isPlaying == true { ballHits() }
        advanceWobbles(dt: dt)
    }

    // MARK: - Pets during a round

    private mutating func keepOwnPetsSitting() {
        let sit = Script(anim: .sit, end: .after(3600), priority: 3)
        for i in pets.indices where pets[i].role == .own && pets[i].visible && (pets[i].brain.script?.priority ?? 0) < 3 {
            pets[i].perform(sit)
        }
    }

    private mutating func spawnWild(_ spec: WildSpec, world: World) {
        guard !world.screens.isEmpty else { return }
        let pick = game?.randomUnit() ?? 0
        let screen = world.screens[min(Int(pick * Double(world.screens.count)), world.screens.count - 1)]
        let fromLeft = (game?.randomUnit() ?? 0) < 0.5
        let x = fromLeft ? screen.frame.minX + 40 : screen.frame.maxX - 40
        let id = addPet(role: .wild, metrics: spec.metrics, at: CGPoint(x: x, y: screen.visibleFrame.minY + 1))
        pets[pets.count - 1].lifetime = game?.wildLifetime() ?? CatchGame.lifetime.lowerBound
        wildSpecs[id] = spec
        events.append(.wildSpawned(petID: id, path: spec.path))
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
            guard pets[i].leaving, (pets[i].brain.script?.priority ?? 0) < 3,
                  let screen = world.screens.first(where: { $0.frame.minX <= x && x <= $0.frame.maxX }) else { continue }
            let exit = x - screen.frame.minX < screen.frame.maxX - x ? screen.frame.minX - 200 : screen.frame.maxX + 200
            pets[i].perform(Script(anim: .walk, moveTo: exit, speed: PetBrain.walkSpeed * 1.6 * 1.5, end: .arrived, priority: 3))
        }
    }

    // MARK: - Balls

    private mutating func ballHits() {
        for b in items.indices where items[b].kind == .pokeBall && items[b].state == .flying {
            let center = CGPoint(x: items[b].body.position.x,
                                 y: items[b].body.position.y + CGFloat(ItemArt.size) * scale / 2)
            guard let w = pets.indices.first(where: {
                pets[$0].role == .wild && pets[$0].visible && pets[$0].hitRect.contains(center)
            }) else { continue }
            let outcome = game?.rollCatch() ?? (caught: false, wobbles: 1)
            game?.recordHit()
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
                game?.recordCatch(CatchRecord(petID: petID, path: spec.path, displayName: spec.displayName, position: position))
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
        for i in pets.indices where pets[i].role == .own && (pets[i].brain.script?.priority ?? 0) >= 3 {
            pets[i].endScript()
        }
        if let game { lastResults = CatchResults(score: game.score, catches: game.catches) }
        game = nil
        events.append(.roundEnded)
    }
}
```

In `Sources/PokeToyCore/Playground.swift`, replace

```swift
    mutating func rulesBeforePhysics(dt: Double, world: World) {
        socialRules(dt: dt, world: world)
        feedingRules(world: world)
    }

    /// Rules that react to where things ended up (collisions, Poké Ball hits).
    mutating func rulesAfterPhysics(dt: Double, world: World) {
        collisionRules(world: world)
    }
```

with

```swift
    mutating func rulesBeforePhysics(dt: Double, world: World) {
        gameRulesBeforePhysics(dt: dt, world: world)
        socialRules(dt: dt, world: world)
        feedingRules(world: world)
    }

    /// Rules that react to where things ended up (collisions, Poké Ball hits).
    mutating func rulesAfterPhysics(dt: Double, world: World) {
        collisionRules(world: world)
        gameRulesAfterPhysics(dt: dt)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh`
Expected: the whole suite PASSES.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/Playground+Game.swift Sources/PokeToyCore/Playground.swift Tests/PokeToyCoreTests/GameTests.swift
git commit -m "feat: catch rounds in the playground: wild spawns, hits, wobbles, catches"
```

---

### Task 12: Offline-friendly sprite loading

**Files:**
- Modify: `Sources/PokeToyCore/SpriteStore.swift` (replace)
- Test: append to `Tests/PokeToyCoreTests/SpriteStoreTests.swift`

**Interfaces:**
- Produces: `SpriteStoreError.timedOut` and `LocalizedError` messages; `SpriteStore.isUsable(_:) -> Bool`; `SpriteStore.cachedSpritePaths() -> [String]`; `SpriteStore.spriteDirectory(for:timeout:) async throws -> URL`. `spriteDirectory(for:)` now falls back to a usable (incomplete) cached or bundled directory when the network fails.

- [ ] **Step 1: Write the failing tests**

Append inside `SpriteStoreTests` (before its closing brace):

<!-- append-in-suite: Tests/PokeToyCoreTests/SpriteStoreTests.swift -->
```swift
    @Test func offlineUsesAnIncompleteCache() async throws {
        let cache = makeTempDirectory()
        let dir = cache.appendingPathComponent("sprite/0025")
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk"), TestAnim(name: "Idle"), TestAnim(name: "Eat")])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Eat-Anim.png"))
        #expect(!SpriteStore.isComplete(dir))
        #expect(SpriteStore.isUsable(dir))
        let store = SpriteStore(cacheDirectory: cache, remoteBase: URL(fileURLWithPath: "/nonexistent-remote"))
        let found = try await store.spriteDirectory(for: "0025")
        #expect(found.standardizedFileURL == dir.standardizedFileURL)
        #expect(try SpriteSet(directory: found).animation(.eat).info.name == "Idle")
    }

    @Test func offlineCacheWithoutIdleOrWalkIsNotUsed() async throws {
        let cache = makeTempDirectory()
        let dir = cache.appendingPathComponent("sprite/0025")
        try writeSpriteDirectory(at: dir, anims: [TestAnim(name: "Walk"), TestAnim(name: "Idle")])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Walk-Anim.png"))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Idle-Anim.png"))
        #expect(!SpriteStore.isUsable(dir))
        let store = SpriteStore(cacheDirectory: cache, remoteBase: URL(fileURLWithPath: "/nonexistent-remote"))
        await #expect(throws: (any Error).self) { try await store.spriteDirectory(for: "0025") }
    }

    @Test func cachedSpritePathsListUsableDirectories() async throws {
        let cache = makeTempDirectory()
        try writeSpriteDirectory(at: cache.appendingPathComponent("sprite/0025"), anims: anims)
        try writeSpriteDirectory(at: cache.appendingPathComponent("sprite/0025/0000/0001"), anims: anims)
        let broken = cache.appendingPathComponent("sprite/0099")
        try writeSpriteDirectory(at: broken, anims: [TestAnim(name: "Walk")])
        try FileManager.default.removeItem(at: broken.appendingPathComponent("Walk-Anim.png"))
        let bundle = makeTempDirectory()
        try writeSpriteDirectory(at: bundle.appendingPathComponent("0133"), anims: anims)
        let store = SpriteStore(cacheDirectory: cache, remoteBase: URL(fileURLWithPath: "/nonexistent-remote"),
                                bundledSprites: bundle)
        #expect(await store.cachedSpritePaths() == ["0025", "0025/0000/0001", "0133"])
    }

    @Test func timeoutVariantReturnsWhenFast() async throws {
        let bundle = makeTempDirectory()
        try writeSpriteDirectory(at: bundle.appendingPathComponent("0025"), anims: anims)
        let store = SpriteStore(cacheDirectory: makeTempDirectory(), remoteBase: URL(fileURLWithPath: "/nonexistent-remote"),
                                bundledSprites: bundle)
        let dir = try await store.spriteDirectory(for: "0025", timeout: 5)
        #expect(SpriteStore.isComplete(dir))
    }

    @Test func errorsReadWell() {
        #expect(SpriteStoreError.http(status: 404, path: "x").localizedDescription == "Not found on SpriteCollab.")
        #expect(SpriteStoreError.http(status: 500, path: "x").localizedDescription == "SpriteCollab answered with HTTP 500.")
        #expect(SpriteStoreError.timedOut.localizedDescription == "SpriteCollab took too long to answer.")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter SpriteStoreTests`
Expected: build FAILS with "type 'SpriteStore' has no member 'isUsable'".

- [ ] **Step 3: Implement**

<!-- file: Sources/PokeToyCore/SpriteStore.swift -->
```swift
import Foundation

public enum SpriteStoreError: Error, Equatable, LocalizedError {
    case http(status: Int, path: String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .http(404, _): return "Not found on SpriteCollab."
        case .http(let status, _): return "SpriteCollab answered with HTTP \(status)."
        case .timedOut: return "SpriteCollab took too long to answer."
        }
    }
}

/// Fetches SpriteCollab data and keeps it in a local cache.
public actor SpriteStore {
    public static let defaultRemoteBase = URL(string: "https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/")!
    public static let catalogMaxAge: TimeInterval = 7 * 24 * 3600

    private let cacheDirectory: URL
    private let remoteBase: URL
    private let bundledSprites: URL?
    private let session: URLSession

    public init(cacheDirectory: URL, remoteBase: URL = SpriteStore.defaultRemoteBase, bundledSprites: URL? = nil,
                session: URLSession = .shared) {
        self.cacheDirectory = cacheDirectory
        self.remoteBase = remoteBase
        self.bundledSprites = bundledSprites
        self.session = session
    }

    /// The Pokémon list. Uses a cached copy younger than `catalogMaxAge` unless `forceRefresh`;
    /// falls back to any cached copy when the network fails.
    public func catalog(forceRefresh: Bool = false) async throws -> [CatalogEntry] {
        let cached = cacheDirectory.appendingPathComponent("tracker.json")
        if !forceRefresh, let age = Self.age(of: cached), age < Self.catalogMaxAge,
           let data = try? Data(contentsOf: cached), let entries = try? Catalog.parse(trackerJSON: data) {
            return entries
        }
        do {
            let data = try await fetch("tracker.json")
            let entries = try Catalog.parse(trackerJSON: data)
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: cached, options: .atomic)
            return entries
        } catch {
            if let data = try? Data(contentsOf: cached), let entries = try? Catalog.parse(trackerJSON: data) {
                return entries
            }
            throw error
        }
    }

    /// A local directory with what `SpriteSet` needs for `path`, downloading missing files.
    /// Offline, an incomplete but usable cached or bundled copy is returned instead.
    public func spriteDirectory(for path: String) async throws -> URL {
        let cached = cacheDirectory.appendingPathComponent("sprite").appendingPathComponent(path, isDirectory: true)
        let bundled = bundledSprites?.appendingPathComponent(path, isDirectory: true)
        if Self.isComplete(cached) { return cached }
        if let bundled, Self.isComplete(bundled) { return bundled }
        do {
            let xml = try await fetch("sprite/\(path)/AnimData.xml")
            let animData = try AnimData(xml: xml)
            try FileManager.default.createDirectory(at: cached, withIntermediateDirectories: true)
            for file in SpriteSet.requiredFiles(for: animData).sorted() {
                let target = cached.appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: target.path) { continue }
                try await fetch("sprite/\(path)/\(file)").write(to: target, options: .atomic)
            }
            // Written last: its presence marks the directory as complete.
            try xml.write(to: cached.appendingPathComponent("AnimData.xml"), options: .atomic)
            return cached
        } catch {
            if Self.isUsable(cached) { return cached }
            if let bundled, Self.isUsable(bundled) { return bundled }
            throw error
        }
    }

    /// Like `spriteDirectory(for:)`, but gives up after `timeout` seconds.
    public func spriteDirectory(for path: String, timeout: TimeInterval) async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await self.spriteDirectory(for: path) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw SpriteStoreError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw SpriteStoreError.timedOut }
            return first
        }
    }

    /// Paths (e.g. `0025/0000/0001`) of every usable cached or bundled sprite directory.
    public func cachedSpritePaths() -> [String] {
        var paths = Set<String>()
        let roots = [cacheDirectory.appendingPathComponent("sprite"), bundledSprites].compactMap { $0 }
        for root in roots {
            let rootPath = root.resolvingSymlinksInPath().path
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.lastPathComponent == "AnimData.xml" {
                let directory = url.deletingLastPathComponent()
                guard Self.isUsable(directory) else { continue }
                let path = directory.resolvingSymlinksInPath().path
                guard path.hasPrefix(rootPath) else { continue }
                let relative = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !relative.isEmpty { paths.insert(relative) }
            }
        }
        return paths.sorted()
    }

    public static func isComplete(_ directory: URL) -> Bool {
        guard let xml = try? Data(contentsOf: directory.appendingPathComponent("AnimData.xml")),
              let data = try? AnimData(xml: xml) else { return false }
        return SpriteSet.requiredFiles(for: data).allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    /// Has `AnimData.xml` and an `Idle` or `Walk` sheet, so `SpriteSet` can load it using fallbacks.
    public static func isUsable(_ directory: URL) -> Bool {
        guard let xml = try? Data(contentsOf: directory.appendingPathComponent("AnimData.xml")),
              let data = try? AnimData(xml: xml) else { return false }
        return ["Idle", "Walk"].contains { name in
            guard let info = data.anims[name] else { return false }
            return FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(info.sourceName)-Anim.png").path)
        }
    }

    private func fetch(_ relativePath: String) async throws -> Data {
        let (data, response) = try await session.data(from: remoteBase.appendingPathComponent(relativePath))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SpriteStoreError.http(status: http.statusCode, path: relativePath)
        }
        return data
    }

    private static func age(of url: URL) -> TimeInterval? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(modified)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh`
Expected: the whole suite PASSES.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/SpriteStore.swift Tests/PokeToyCoreTests/SpriteStoreTests.swift
git commit -m "feat: offline fallback to usable caches, cached sprite list, fetch timeout"
```

---
### Task 13: Pets prefer the active window

**Files:**
- Modify: `Sources/PokeToyCore/World.swift` (three edits, Step 3), `Sources/PokeToyCore/PetBrain.swift` (replace `decideNext`, add one constant and one helper, Step 3), `Sources/PokeToy/WorldMonitor.swift` (replace `refresh()`, Step 3)
- Test: `Tests/PokeToyCoreTests/PetBrainActiveWindowTests.swift`; append one test to `Tests/PokeToyCoreTests/WorldTests.swift`

**Interfaces:**
- Consumes: `PetBrain` (Task 2), `World` (existing).
- Produces: `World.activeWindowID: Int?`; `World.init(screens:surfaces:windowOrigins:activeWindowID:)` and `World.build(screens:windows:primaryScreenHeight:activeWindowID:)` with `activeWindowID` defaulting to nil; `PetBrain.activeWindowPreference = 0.6`.

- [ ] **Step 1: Write the failing tests**

<!-- file: Tests/PokeToyCoreTests/PetBrainActiveWindowTests.swift -->
```swift
import CoreGraphics
import Testing
@testable import PokeToyCore

@Suite struct PetBrainActiveWindowTests {
    let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                            visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))
    let floor = Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor)

    /// Runs brain + physics; returns true as soon as `until` holds.
    @discardableResult
    func run(_ brain: inout PetBrain, _ body: inout Body, seconds: Double, world: World,
             until: (Body) -> Bool = { _ in false }, each: (Body) -> Void = { _ in }) -> Bool {
        for _ in 0..<Int(seconds * 60) {
            let context = BrainContext(dt: 1.0 / 60, world: world, cursor: CGPoint(x: -5000, y: -5000),
                                       cursorMode: .off, halfWidth: 20, animationFinished: true)
            brain.update(context, body: &body)
            Physics.step(&body, dt: 1.0 / 60, world: world)
            each(body)
            if until(body) { return true }
        }
        return false
    }

    @Test func jumpsOntoTheActiveWindow() {
        let active = Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)
        let other = Surface(id: 8, minX: 650, maxX: 950, y: 250, kind: .window)
        let world = World(screens: [screen], surfaces: [floor, active, other], activeWindowID: 7)
        var brain = PetBrain(seed: 1)
        var body = Body(position: CGPoint(x: 100, y: 50), surfaceID: -1)
        #expect(run(&brain, &body, seconds: 60, world: world) { $0.surfaceID == 7 })
    }

    @Test func walksUnderAnActiveWindowThatIsOutOfReach() {
        let active = Surface(id: 9, minX: 700, maxX: 950, y: 300, kind: .window)
        let world = World(screens: [screen], surfaces: [floor, active], activeWindowID: 9)
        var brain = PetBrain(seed: 2)
        var body = Body(position: CGPoint(x: 50, y: 50), surfaceID: -1)
        #expect(run(&brain, &body, seconds: 60, world: world) { $0.surfaceID == 9 })
    }

    @Test func dropsDownToALowerActiveWindow() {
        let high = Surface(id: 9, minX: 300, maxX: 600, y: 500, kind: .window)
        let active = Surface(id: 7, minX: 100, maxX: 900, y: 250, kind: .window)
        let world = World(screens: [screen], surfaces: [floor, active, high], activeWindowID: 7)
        var brain = PetBrain(seed: 3)
        var body = Body(position: CGPoint(x: 450, y: 500), surfaceID: 9)
        #expect(run(&brain, &body, seconds: 60, world: world) { $0.surfaceID == 7 })
    }

    @Test func staysOnTheActiveWindow() {
        let active = Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)
        let other = Surface(id: 8, minX: 650, maxX: 950, y: 250, kind: .window)
        let world = World(screens: [screen], surfaces: [floor, active, other], activeWindowID: 7)
        var brain = PetBrain(seed: 4)
        var body = Body(position: CGPoint(x: 450, y: 250), surfaceID: 7)
        var leftIt = false
        run(&brain, &body, seconds: 120, world: world, each: { body in
            if body.isGrounded && body.surfaceID != 7 { leftIt = true }
        })
        #expect(!leftIt)
    }

    @Test func withoutAnActiveWindowPetsStillWanderOff() {
        let window = Surface(id: 7, minX: 300, maxX: 600, y: 250, kind: .window)
        let world = World(screens: [screen], surfaces: [floor, window])
        var brain = PetBrain(seed: 5)
        var body = Body(position: CGPoint(x: 450, y: 250), surfaceID: 7)
        #expect(run(&brain, &body, seconds: 180, world: world) { $0.surfaceID == -1 })
    }
}
```

Append inside `WorldTests` (before its closing brace):

<!-- append-in-suite: Tests/PokeToyCoreTests/WorldTests.swift -->
```swift
    @Test func recordsTheActiveWindow() {
        let window = WindowInfo(id: 42, cgBounds: CGRect(x: 100, y: 200, width: 300, height: 400))
        #expect(World.build(screens: [screen], windows: [window], primaryScreenHeight: 800, activeWindowID: 42)
            .activeWindowID == 42)
        #expect(World.build(screens: [screen], windows: [window], primaryScreenHeight: 800).activeWindowID == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh --filter "PetBrainActiveWindowTests|WorldTests"`
Expected: build FAILS with "extra argument 'activeWindowID' in call".

- [ ] **Step 3: Implement**

In `Sources/PokeToyCore/World.swift`, replace

```swift
    public let windowOrigins: [Int: CGFloat]

    public init(screens: [ScreenInfo], surfaces: [Surface], windowOrigins: [Int: CGFloat] = [:]) {
        self.screens = screens
        self.surfaces = surfaces
        self.windowOrigins = windowOrigins
    }
```

with

```swift
    public let windowOrigins: [Int: CGFloat]
    /// The frontmost window of the frontmost app (pets prefer walking on it), if any.
    public let activeWindowID: Int?

    public init(screens: [ScreenInfo], surfaces: [Surface], windowOrigins: [Int: CGFloat] = [:],
                activeWindowID: Int? = nil) {
        self.screens = screens
        self.surfaces = surfaces
        self.windowOrigins = windowOrigins
        self.activeWindowID = activeWindowID
    }
```

replace

```swift
    public static func build(screens: [ScreenInfo], windows: [WindowInfo], primaryScreenHeight: CGFloat) -> World {
```

with

```swift
    public static func build(screens: [ScreenInfo], windows: [WindowInfo], primaryScreenHeight: CGFloat,
                             activeWindowID: Int? = nil) -> World {
```

and replace

```swift
        return World(screens: screens, surfaces: surfaces, windowOrigins: origins)
```

with

```swift
        return World(screens: screens, surfaces: surfaces, windowOrigins: origins, activeWindowID: activeWindowID)
```

In `Sources/PokeToyCore/PetBrain.swift`, add after `public static let maxJumpReach: CGFloat = 360`:

```swift
    /// Chance that a wandering pet heads for the active window instead of a random spot.
    public static let activeWindowPreference = 0.6
```

and replace the whole `decideNext` function with these two functions:

```swift
    private mutating func decideNext(_ ctx: BrainContext, _ body: inout Body) {
        if personality == .pet && ctx.cursorMode == .off && sinceInteraction > Self.sleepAfter {
            enterSleep(&body)
            return
        }
        guard let id = body.surfaceID, let surface = ctx.world.surface(id: id, containingX: body.position.x) else {
            enterIdle(&body)
            return
        }
        let active = personality == .pet ? ctx.world.activeWindowID : nil
        let onActive = active != nil && surface.id == active
        if let active, !onActive, rng.unit() < Self.activeWindowPreference,
           headFor(activeWindow: active, from: surface, ctx, &body) {
            return
        }
        let roll = rng.unit()
        let jumpChance = personality == .wild ? 0.35 : (onActive ? 0.03 : 0.2)
        if roll < jumpChance {
            let options = reachable(from: body.position, ctx)
            if !options.isEmpty {
                let pick = options[min(Int(rng.unit() * Double(options.count)), options.count - 1)]
                launch(to: pick, x: pick.minX + CGFloat(rng.unit()) * pick.width, halfWidth: ctx.halfWidth, &body)
                return
            }
        }
        let target: CGFloat
        if surface.kind == .window && roll > 0.85 && !onActive {
            // Stroll off the edge of the window.
            target = rng.unit() < 0.5 ? surface.minX - ctx.halfWidth * 2 : surface.maxX + ctx.halfWidth * 2
        } else {
            let lo = surface.minX + ctx.halfWidth, hi = surface.maxX - ctx.halfWidth
            guard hi > lo else { enterIdle(&body); return }
            target = lo + CGFloat(rng.unit()) * (hi - lo)
        }
        let speed = Self.walkSpeed * speedFactor
        state = .walk(targetX: target, speed: speed)
        walk(toward: target, speed: speed, dt: ctx.dt, &body)
    }

    /// Moves toward the active window's top: jumps if it is reachable, walks underneath it if it is above
    /// but too far, or walks off this window's nearer edge if it is below. Returns false if there is no way.
    private mutating func headFor(activeWindow active: Int, from surface: Surface, _ ctx: BrainContext,
                                  _ body: inout Body) -> Bool {
        let p = body.position
        let tops = ctx.world.surfaces.filter { $0.id == active && $0.width >= ctx.halfWidth * 2 }
        guard let nearest = tops.min(by: { $0.distance(toX: p.x) < $1.distance(toX: p.x) }) else { return false }
        if let top = reachable(from: p, ctx).filter({ $0.id == active })
            .min(by: { $0.distance(toX: p.x) < $1.distance(toX: p.x) }) {
            launch(to: top, x: top.minX + CGFloat(rng.unit()) * top.width, halfWidth: ctx.halfWidth, &body)
            return true
        }
        let speed = Self.walkSpeed * speedFactor
        if nearest.y > p.y {
            let under = clamp(min(max(p.x, nearest.minX + ctx.halfWidth), nearest.maxX - ctx.halfWidth),
                              on: surface, ctx.halfWidth)
            guard abs(under - p.x) > 4 else { return false }
            state = .walk(targetX: under, speed: speed)
            walk(toward: under, speed: speed, dt: ctx.dt, &body)
            return true
        }
        guard surface.kind == .window else { return false }
        let target = nearest.midX < p.x ? surface.minX - ctx.halfWidth * 2 : surface.maxX + ctx.halfWidth * 2
        state = .walk(targetX: target, speed: speed)
        walk(toward: target, speed: speed, dt: ctx.dt, &body)
        return true
    }
```

In `Sources/PokeToy/WorldMonitor.swift`, replace the whole `refresh()` function with:

```swift
    func refresh() {
        let screens = NSScreen.screens.map { ScreenInfo(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var activeWindowID: Int?
        let windows: [WindowInfo] = list.compactMap { info in
            let pid = info[kCGWindowOwnerPID as String] as? Int32
            guard (info[kCGWindowLayer as String] as? Int) == 0, pid != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 80, bounds.height >= 40,
                  let number = info[kCGWindowNumber as String] as? Int else { return nil }
            // The list is front to back, so the first window of the frontmost app is its active one.
            if activeWindowID == nil, pid == frontPID { activeWindowID = number }
            return WindowInfo(id: number, cgBounds: bounds)
        }
        world = World.build(screens: screens, windows: windows, primaryScreenHeight: primaryHeight,
                            activeWindowID: activeWindowID)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh && swift build 2>&1 | grep -E "error:" || echo "app builds"`
Expected: the whole suite PASSES and `app builds`. If one of the seeded walk tests misses its deadline only because of the random rolls, change its seed (a ledgered ruling), not the behavior.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokeToyCore/World.swift Sources/PokeToyCore/PetBrain.swift Sources/PokeToy/WorldMonitor.swift Tests/PokeToyCoreTests/PetBrainActiveWindowTests.swift Tests/PokeToyCoreTests/WorldTests.swift
git commit -m "feat: pets prefer walking on the active window"
```

---

### Task 14: App on the Playground — treats, Feed, friendships in the menu, picker filter

**Files:**
- Create: `Sources/PokeToy/DragTracker.swift`, `Sources/PokeToy/ItemController.swift`
- Modify (replace): `Sources/PokeToy/PetWindow.swift`, `Sources/PokeToy/PetController.swift`, `Sources/PokeToy/AppModel.swift`, `Sources/PokeToy/MenuBuilder.swift`, `Sources/PokeToy/PickerWindowController.swift`
- Unchanged in this task: `AppDelegate.swift`, `WorldMonitor.swift` (changed in Task 13), `main.swift`

**Interfaces:**
- Consumes: all of PokeToyCore (Tasks 1–13).
- Produces (app-internal): `DragTracker { begin(at:objectPosition:); move(to:) -> CGPoint; releaseVelocity(cap:) -> CGVector }`; `PetWindow.render(sprite:footPadding:hearts:feet:scale:)`; `PetController(id:sprites:model:interactive:) { show(); hide(); close(); render(_:cursor:) }`; `ItemController(id:model:) { show(); hide(); close(); render(_:cursor:scale:) }`; `AppModel { settings; playground; start(); addPet(_:) async throws; removePet(_:); bestFriendName(of:) -> String?; handle(_: PetEvent, pet:); movePet(_:to:); canFeed; feed(); handle(_: ItemEvent, item:); moveItem(_:to:); setHidden(_:); setCursorMode(_:); setScale(_:); showPicker(); catalog(forceRefresh:); save() }`; `ActionItem(_:key:state:enabled:handler:)`; `AppError.tooManyPets`.

This task is AppKit glue with no unit tests; it is verified by building and running the app (Step 3).

- [ ] **Step 1: Shared drag handling, pet window with hearts, pet and treat controllers**

<!-- file: Sources/PokeToy/DragTracker.swift -->
```swift
import AppKit

/// Turns a press-and-drag on a floating panel into an offset and a release velocity.
struct DragTracker {
    private var offset = CGVector.zero
    private var samples: [(time: CFTimeInterval, point: CGPoint)] = []

    mutating func begin(at point: CGPoint, objectPosition: CGPoint) {
        offset = CGVector(dx: objectPosition.x - point.x, dy: objectPosition.y - point.y)
        samples = [(CACurrentMediaTime(), point)]
    }

    /// Records the mouse at `point` and returns where the dragged object should be.
    mutating func move(to point: CGPoint) -> CGPoint {
        let now = CACurrentMediaTime()
        samples.append((now, point))
        samples.removeAll { $0.time < now - 0.1 }
        return CGPoint(x: point.x + offset.dx, y: point.y + offset.dy)
    }

    /// The mouse velocity over the last 0.1 s, limited to `cap` points per second.
    func releaseVelocity(cap: CGFloat) -> CGVector {
        let now = CACurrentMediaTime()
        let recent = samples.filter { $0.time >= now - 0.1 }
        guard let first = recent.first, let last = recent.last, last.time - first.time > 0.01 else { return .zero }
        let elapsed = CGFloat(last.time - first.time)
        var velocity = CGVector(dx: (last.point.x - first.point.x) / elapsed, dy: (last.point.y - first.point.y) / elapsed)
        let speed = hypot(velocity.dx, velocity.dy)
        if speed > cap {
            velocity.dx *= cap / speed
            velocity.dy *= cap / speed
        }
        return velocity
    }
}
```

<!-- file: Sources/PokeToy/PetWindow.swift -->
```swift
import AppKit
import PokeToyCore

@MainActor
protocol PetViewDelegate: AnyObject {
    func petViewPressed()
    func petViewClicked()
    func petViewDragBegan(at point: CGPoint)
    func petViewDragMoved(to point: CGPoint)
    func petViewDragEnded()
}

/// Borderless transparent panel that floats above every app, on every Space, sized to the current sprite frame.
@MainActor
final class PetWindow: NSPanel {
    static let heartSpace: CGFloat = 24

    let petView = PetView()
    private var sprite: SpriteFrame?
    private var spriteScale: CGFloat = 2

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        contentView = petView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Positions the panel so the sprite's feet sit at `feet` and draws `sprite` with `hearts` above it.
    func render(sprite: SpriteFrame, footPadding: Int, hearts: Int, feet: CGPoint, scale: CGFloat) {
        let width = CGFloat(sprite.image.width) * scale
        let height = CGFloat(sprite.image.height) * scale
        let rect = NSRect(x: (feet.x - width / 2).rounded(), y: (feet.y - CGFloat(footPadding) * scale).rounded(),
                          width: width, height: height + Self.heartSpace)
        if rect != frame { setFrame(rect, display: false) }
        if petView.frameImage !== sprite.image || petView.hearts != hearts {
            petView.frameImage = sprite.image
            petView.hearts = hearts
            petView.needsDisplay = true
        }
        self.sprite = sprite
        spriteScale = scale
    }

    /// True if `screenPoint` is on (or within one pixel of) an opaque sprite pixel.
    func hitsSprite(at screenPoint: CGPoint) -> Bool {
        guard let sprite, isVisible else { return false }
        let x = Int(floor((screenPoint.x - frame.minX) / spriteScale))
        let yFromBottom = Int(floor((screenPoint.y - frame.minY) / spriteScale))
        let y = sprite.mask.height - 1 - yFromBottom
        for dx in -1...1 {
            for dy in -1...1 where sprite.mask.isOpaque(x: x + dx, y: y + dy) { return true }
        }
        return false
    }
}

@MainActor
final class PetView: NSView {
    weak var delegate: PetViewDelegate?
    var frameImage: CGImage?
    var hearts = 0
    private var mouseDownPoint: CGPoint?
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = frameImage, let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        context.interpolationQuality = .none
        let spriteRect = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - PetWindow.heartSpace)
        context.draw(image, in: spriteRect)
        if hearts > 0 {
            let text = NSAttributedString(string: String(repeating: "♥", count: hearts), attributes: [
                .font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.systemPink,
            ])
            let size = text.size()
            text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: spriteRect.maxY - 4))
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = NSEvent.mouseLocation
        dragging = false
        delegate?.petViewPressed()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let point = NSEvent.mouseLocation
        if !dragging, hypot(point.x - start.x, point.y - start.y) > 3 {
            dragging = true
            delegate?.petViewDragBegan(at: start)
        }
        if dragging { delegate?.petViewDragMoved(to: point) }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            delegate?.petViewDragEnded()
        } else if mouseDownPoint != nil {
            delegate?.petViewClicked()
        }
        mouseDownPoint = nil
        dragging = false
    }
}
```

<!-- file: Sources/PokeToy/PetController.swift -->
```swift
import AppKit
import PokeToyCore

/// Draws one pet (own or wild) from its `PetActor` and forwards mouse input to the model.
@MainActor
final class PetController: PetViewDelegate {
    let id: UUID
    private let sprites: SpriteSet
    private unowned let model: AppModel
    private let interactive: Bool
    private let window = PetWindow()
    private var drag = DragTracker()
    private var pressing = false
    private var wanted = false

    init(id: UUID, sprites: SpriteSet, model: AppModel, interactive: Bool) {
        self.id = id
        self.sprites = sprites
        self.model = model
        self.interactive = interactive
        window.petView.delegate = self
    }

    func show() { wanted = true }

    func hide() {
        wanted = false
        window.orderOut(nil)
    }

    func close() { window.close() }

    func render(_ actor: PetActor, cursor: CGPoint) {
        if pressing, NSEvent.pressedMouseButtons & 1 == 0 {
            // The mouse-up never reached us (e.g. a system gesture took over mid-drag).
            if actor.brain.state == .dragged { petViewDragEnded() } else { model.handle(.released, pet: id) }
            pressing = false
        }
        guard wanted, actor.visible else {
            if window.isVisible { window.orderOut(nil) }
            return
        }
        let pose = actor.pose
        let animation = sprites.animation(pose.anim)
        let frames = animation.frames(facing: pose.facing)
        window.render(sprite: frames[actor.animator.frameIndex % frames.count],
                      footPadding: animation.footPadding(facing: pose.facing),
                      hearts: pose.hearts, feet: actor.body.position, scale: actor.scale)
        if !window.isVisible { window.orderFrontRegardless() }
        // Clicks pass through to other apps except over the sprite's own pixels.
        window.ignoresMouseEvents = !interactive || (!pressing && !window.hitsSprite(at: cursor))
    }

    // MARK: PetViewDelegate

    func petViewPressed() {
        pressing = true
        model.handle(.pressed, pet: id)
    }

    func petViewClicked() {
        pressing = false
        model.handle(.click, pet: id)
    }

    func petViewDragBegan(at point: CGPoint) {
        model.handle(.dragBegan, pet: id)
        drag.begin(at: point, objectPosition: model.playground.pet(id)?.body.position ?? point)
    }

    func petViewDragMoved(to point: CGPoint) {
        model.movePet(id, to: drag.move(to: point))
    }

    func petViewDragEnded() {
        pressing = false
        model.handle(.dragEnded(velocity: drag.releaseVelocity(cap: 1500)), pet: id)
    }
}
```

<!-- file: Sources/PokeToy/ItemController.swift -->
```swift
import AppKit
import PokeToyCore

/// A treat in its own floating panel; it can be pressed, dragged and thrown like a pet.
@MainActor
final class ItemController: PetViewDelegate {
    let id: UUID
    private unowned let model: AppModel
    private let window = PetWindow()
    private var drag = DragTracker()
    private var pressing = false
    private var wanted = true

    init(id: UUID, model: AppModel) {
        self.id = id
        self.model = model
        window.petView.delegate = self
    }

    func show() { wanted = true }

    func hide() {
        wanted = false
        window.orderOut(nil)
    }

    func close() { window.close() }

    func render(_ item: Item, cursor: CGPoint, scale: CGFloat) {
        if pressing, NSEvent.pressedMouseButtons & 1 == 0 {
            model.handle(.released, item: id)
            pressing = false
        }
        guard wanted else {
            if window.isVisible { window.orderOut(nil) }
            return
        }
        window.render(sprite: ItemArt.frame(for: item.kind), footPadding: 0, hearts: 0, feet: item.body.position, scale: scale)
        if !window.isVisible { window.orderFrontRegardless() }
        window.ignoresMouseEvents = !pressing && !window.hitsSprite(at: cursor)
    }

    // MARK: PetViewDelegate

    func petViewPressed() {
        pressing = true
        model.handle(.pressed, item: id)
    }

    func petViewClicked() {
        pressing = false
        model.handle(.released, item: id)
    }

    func petViewDragBegan(at point: CGPoint) {
        model.handle(.dragBegan, item: id)
        let position = model.playground.items.first { $0.id == id }?.body.position ?? point
        drag.begin(at: point, objectPosition: position)
    }

    func petViewDragMoved(to point: CGPoint) {
        model.moveItem(id, to: drag.move(to: point))
    }

    func petViewDragEnded() {
        pressing = false
        model.handle(.dragEnded(velocity: drag.releaseVelocity(cap: 1500)), item: id)
    }
}
```

- [ ] **Step 2: Model, menus and picker**

<!-- file: Sources/PokeToy/AppModel.swift -->
```swift
import AppKit
import OSLog
import PokeToyCore

enum AppError: LocalizedError {
    case tooManyPets

    var errorDescription: String? {
        switch self {
        case .tooManyPets: return "You already have \(Playground.maxOwnPets) pets — remove one first."
        }
    }
}

/// Owns the settings, the sprite store and the playground, and drives the 60 Hz tick.
@MainActor
final class AppModel {
    private(set) var settings: Settings
    private(set) var playground: Playground
    private let store: SpriteStore
    private let worldMonitor = WorldMonitor()
    private var petViews: [UUID: PetController] = [:]
    private var itemViews: [UUID: ItemController] = [:]
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private lazy var picker = PickerWindowController(model: self)
    private let logger = Logger(subsystem: "local.poketoy.PokeToy", category: "app")

    init() {
        let settings = Settings.load(from: .standard)
        self.settings = settings
        playground = Playground(seed: .random(in: .min ... .max), scale: CGFloat(settings.scale),
                                friendships: Friendships(points: settings.friendships))
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeToy", isDirectory: true)
        store = SpriteStore(cacheDirectory: caches,
                            bundledSprites: Bundle.main.resourceURL?.appendingPathComponent("Sprites", isDirectory: true))
    }

    func start() {
        worldMonitor.start()
        for record in settings.pets {
            Task {
                do {
                    attach(record, sprites: try await loadSprites(record.spritePath))
                } catch {
                    logger.error("Couldn't load \(record.spritePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Pets

    func addPet(_ entry: CatalogEntry) async throws {
        guard settings.pets.count < Playground.maxOwnPets else { throw AppError.tooManyPets }
        let sprites = try await loadSprites(entry.path)
        guard settings.pets.count < Playground.maxOwnPets else { throw AppError.tooManyPets }
        let record = PetRecord(spritePath: entry.path, displayName: entry.displayName)
        settings.pets.append(record)
        if settings.hidden { setHidden(false) }
        attach(record, sprites: sprites)
        save()
    }

    func removePet(_ id: UUID) {
        playground.removePet(id)
        petViews.removeValue(forKey: id)?.close()
        settings.pets.removeAll { $0.id == id }
        save()
    }

    func bestFriendName(of id: UUID) -> String? {
        guard let friend = playground.friendships.bestFriend(of: id, among: settings.pets.map(\.id)) else { return nil }
        return settings.pets.first { $0.id == friend }?.displayName
    }

    func handle(_ event: PetEvent, pet id: UUID) {
        playground.handle(event, pet: id)
    }

    func movePet(_ id: UUID, to point: CGPoint) {
        playground.movePet(id, to: point)
    }

    // MARK: - Treats

    var canFeed: Bool { playground.canDropTreat }

    /// Drops a random treat from the top of the screen under the cursor.
    func feed() {
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        let kind: ItemKind = Bool.random() ? .apple : .oranBerry
        playground.dropTreat(kind, at: CGPoint(x: cursor.x, y: screen.visibleFrame.maxY - 10))
    }

    func handle(_ event: ItemEvent, item id: UUID) {
        playground.handle(event, item: id)
    }

    func moveItem(_ id: UUID, to point: CGPoint) {
        playground.moveItem(id, to: point)
    }

    // MARK: - Settings

    func setHidden(_ hidden: Bool) {
        settings.hidden = hidden
        for record in settings.pets {
            if hidden { petViews[record.id]?.hide() } else { petViews[record.id]?.show() }
        }
        for view in itemViews.values {
            if hidden { view.hide() } else { view.show() }
        }
        save()
    }

    func setCursorMode(_ mode: CursorMode) {
        settings.cursorMode = mode
        save()
    }

    func setScale(_ scale: Int) {
        settings.scale = min(max(scale, 1), 3)
        playground.setScale(CGFloat(settings.scale))
        save()
    }

    func showPicker() {
        picker.show()
    }

    func catalog(forceRefresh: Bool) async throws -> [CatalogEntry] {
        try await store.catalog(forceRefresh: forceRefresh)
    }

    /// Records current pet positions and friendships and writes settings to disk.
    func save() {
        for index in settings.pets.indices {
            if let pet = playground.pet(settings.pets[index].id) { settings.pets[index].position = pet.body.position }
        }
        settings.friendships = playground.friendships.points
        settings.save(to: .standard)
    }

    // MARK: - Private

    private func loadSprites(_ path: String) async throws -> SpriteSet {
        let directory = try await store.spriteDirectory(for: path)
        return try SpriteSet(directory: directory)
    }

    private func attach(_ record: PetRecord, sprites: SpriteSet) {
        // A pet removed while its sprites were loading is dropped.
        guard settings.pets.contains(where: { $0.id == record.id }), petViews[record.id] == nil else { return }
        let world = worldMonitor.world
        let start = record.position.flatMap { world.isOnAnyScreen($0, margin: 0) ? $0 : nil }
            ?? world.spawnPoint(fraction: .random(in: 0.2...0.8))
        playground.addPet(id: record.id, role: .own, metrics: PetMetrics(sprites: sprites), at: start)
        let view = PetController(id: record.id, sprites: sprites, model: self, interactive: true)
        if !settings.hidden { view.show() }
        petViews[record.id] = view
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTick == 0 ? 1.0 / 60.0 : min(now - lastTick, 0.1)
        lastTick = now
        let cursor = NSEvent.mouseLocation
        let events = playground.tick(dt: dt, world: worldMonitor.world, cursor: cursor, cursorMode: settings.cursorMode)
        if events.contains(.friendshipChanged) { save() }
        syncItemViews()
        for pet in playground.pets { petViews[pet.id]?.render(pet, cursor: cursor) }
        for item in playground.items { itemViews[item.id]?.render(item, cursor: cursor, scale: playground.scale) }
    }

    /// Opens a panel for each new treat and closes panels whose treat is gone.
    private func syncItemViews() {
        let treats = Set(playground.items.filter { $0.kind.isTreat }.map(\.id))
        for (id, view) in itemViews where !treats.contains(id) {
            view.close()
            itemViews[id] = nil
        }
        for id in treats where itemViews[id] == nil {
            let view = ItemController(id: id, model: self)
            if settings.hidden { view.hide() }
            itemViews[id] = view
        }
    }
}
```

<!-- file: Sources/PokeToy/MenuBuilder.swift -->
```swift
import AppKit
import PokeToyCore

/// Menu item that runs a closure; `enabled` (if given) decides whether it can be chosen.
@MainActor
final class ActionItem: NSMenuItem, NSMenuItemValidation {
    private let handler: () -> Void
    private let isAllowed: (() -> Bool)?

    init(_ title: String, key: String = "", state: NSControl.StateValue = .off, enabled: (() -> Bool)? = nil,
         handler: @escaping () -> Void) {
        self.handler = handler
        isAllowed = enabled
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        self.state = state
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        isAllowed?() ?? true
    }
}

extension CursorMode {
    var title: String {
        switch self {
        case .off: return "Off"
        case .follow: return "Follow Cursor"
        case .flee: return "Run from Cursor"
        }
    }
}

/// Builds the status-item, Dock and main menus from the current `AppModel` state.
@MainActor
final class MenuBuilder: NSObject, NSMenuDelegate {
    private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populate(menu, includeQuit: true)
        return menu
    }

    func makeDockMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu, includeQuit: false)  // the Dock adds its own Quit
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu, includeQuit: true)
    }

    func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "PokeToy")
        appMenu.addItem(withTitle: "About PokeToy",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(ActionItem("Add Pokémon…", key: "n") { [unowned model] in model.showPicker() })
        appMenu.addItem(ActionItem("Feed", key: "f", enabled: { [unowned model] in model.canFeed }) {
            [unowned model] in model.feed()
        })
        appMenu.addItem(ActionItem("Show/Hide Pets") { [unowned model] in model.setHidden(!model.settings.hidden) })
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PokeToy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(edit, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(window, to: main)
        return main
    }

    private func populate(_ menu: NSMenu, includeQuit: Bool) {
        menu.removeAllItems()
        let hidden = model.settings.hidden
        menu.addItem(ActionItem(hidden ? "Show Pets" : "Hide Pets") { [unowned model] in model.setHidden(!hidden) })
        menu.addItem(ActionItem("Add Pokémon…") { [unowned model] in model.showPicker() })
        menu.addItem(ActionItem("Feed", enabled: { [unowned model] in model.canFeed }) { [unowned model] in model.feed() })
        menu.addItem(.separator())

        let pets = model.settings.pets
        if pets.isEmpty {
            menu.addItem(NSMenuItem(title: "No pets yet", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Pets", action: nil, keyEquivalent: ""))
            for pet in pets {
                let item = NSMenuItem(title: pet.displayName, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                if let friend = model.bestFriendName(of: pet.id) {
                    submenu.addItem(NSMenuItem(title: "Best friend: \(friend)", action: nil, keyEquivalent: ""))
                    submenu.addItem(.separator())
                }
                submenu.addItem(ActionItem("Remove") { [unowned model] in model.removePet(pet.id) })
                item.submenu = submenu
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        let cursorMenu = NSMenu()
        for mode in CursorMode.allCases {
            cursorMenu.addItem(ActionItem(mode.title, state: model.settings.cursorMode == mode ? .on : .off) {
                [unowned model] in model.setCursorMode(mode)
            })
        }
        addSubmenu(cursorMenu, titled: "Cursor", to: menu)

        let sizeMenu = NSMenu()
        for scale in 1...3 {
            sizeMenu.addItem(ActionItem("\(scale)×", state: model.settings.scale == scale ? .on : .off) {
                [unowned model] in model.setScale(scale)
            })
        }
        addSubmenu(sizeMenu, titled: "Size", to: menu)

        if includeQuit {
            menu.addItem(.separator())
            menu.addItem(ActionItem("Quit PokeToy") { NSApp.terminate(nil) })
        }
    }

    private func addSubmenu(_ submenu: NSMenu, titled title: String? = nil, to menu: NSMenu) {
        let item = NSMenuItem(title: title ?? submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}
```

<!-- file: Sources/PokeToy/PickerWindowController.swift -->
```swift
import AppKit
import PokeToyCore

/// Searchable list of SpriteCollab Pokémon; choosing one adds it as a new pet.
@MainActor
final class PickerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let model: AppModel
    private var all: [CatalogEntry] = []
    private var shown: [CatalogEntry] = []
    private var busy = false

    private let search = NSSearchField()
    private let showAll = NSButton(checkboxWithTitle: "Show all Pokémon (including incomplete sprites)", target: nil, action: nil)
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    private let addButton = NSButton(title: "Add", target: nil, action: nil)

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Add Pokémon"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 300, height: 300)
        super.init(window: window)
        buildLayout(in: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(search)
        if all.isEmpty { load(forceRefresh: false) }
    }

    private func buildLayout(in window: NSWindow) {
        search.placeholderString = "Search by name or number"
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(filterChanged)
        showAll.state = .off
        showAll.target = self
        showAll.action = #selector(filterChanged)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(addSelected)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        retryButton.target = self
        retryButton.action = #selector(retry)
        retryButton.isHidden = true
        addButton.target = self
        addButton.action = #selector(addSelected)
        addButton.keyEquivalent = "\r"

        let footer = NSStackView(views: [status, spinner, retryButton, addButton])
        footer.orientation = .horizontal
        let stack = NSStackView(views: [search, showAll, scroll, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
        ])
    }

    private func load(forceRefresh: Bool) {
        setBusy(true, message: "Loading Pokémon list…")
        retryButton.isHidden = true
        Task {
            do {
                all = try await model.catalog(forceRefresh: forceRefresh)
                applyFilter()
                setBusy(false, message: countMessage)
            } catch {
                setBusy(false, message: "Couldn't reach SpriteCollab.")
                retryButton.isHidden = false
            }
        }
    }

    private var countMessage: String {
        "\(shown.count) Pokémon — double-click to add"
    }

    private func applyFilter() {
        shown = Catalog.filter(all, query: search.stringValue, completeOnly: showAll.state != .on)
        table.reloadData()
    }

    private func setBusy(_ busy: Bool, message: String) {
        self.busy = busy
        status.stringValue = message
        addButton.isEnabled = !busy
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    @objc private func filterChanged() {
        applyFilter()
        if !busy && !all.isEmpty { status.stringValue = countMessage }
    }

    @objc private func retry() {
        load(forceRefresh: true)
    }

    @objc private func addSelected() {
        guard !busy, table.selectedRow >= 0, table.selectedRow < shown.count else { return }
        let entry = shown[table.selectedRow]
        setBusy(true, message: "Downloading \(entry.displayName)…")
        Task {
            do {
                try await model.addPet(entry)
                setBusy(false, message: "Added \(entry.displayName)!")
            } catch {
                setBusy(false, message: "Couldn't add \(entry.displayName): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        shown.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let label = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField ?? {
            let label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.lineBreakMode = .byTruncatingTail
            return label
        }()
        let entry = shown[row]
        label.stringValue = "\(entry.displayName)   #\(entry.path)"
        return label
    }
}
```

- [ ] **Step 3: Build, run and verify by hand**

Run: `./scripts/test.sh 2>&1 | tail -1 && swift build 2>&1 | grep -E "error:" ; ./scripts/build-app.sh && open build/PokeToy.app`
Expected: the test suite passes, no build errors, "Built build/PokeToy.app".

Check and note any failure before continuing:
1. Pets load as before (walk, click ♥, drag and throw, window riding, follow/flee, hide/show, size).
2. Menu → **Feed** (or ⌘F with the app active) drops an apple or Oran Berry above the cursor; it lands; the nearest pet walks (or jumps) to it and eats (`Eat`, then a ♥); a second pet arriving late looks sad.
3. A treat can be picked up, dragged and thrown; pets ignore it while it's held.
4. With two pets, over a few minutes they greet (Nod), play tag and play-fight; a pet thrown into another knocks it over; two walkers bumping turn around.
5. After enough moments, Pets → *name* shows "Best friend: …"; best friends wander to each other and nap side by side.
6. A sleeping pet wakes on its own after a while (`Wake` animation).
7. **Add Pokémon…** lists only complete Pokémon (about 680); ticking "Show all Pokémon" shows every entry (about 3,200). Adding a 13th pet shows "You already have 12 pets — remove one first."
8. Click into another app's window: over the next minute pets drift onto that window's top and mostly stay there; activating a different window draws them over to it.

- [ ] **Step 4: Commit**

```bash
git add Sources/PokeToy
git commit -m "feat: app runs on the Playground; Feed, treat panels, best friends, complete-only picker"
```

---

### Task 15: Catch game UI

**Files:**
- Create: `Sources/PokeToy/GameController.swift`, `Sources/PokeToy/GameOverlayWindow.swift`, `Sources/PokeToy/ResultsWindowController.swift`
- Modify (replace): `Sources/PokeToy/AppModel.swift`, `Sources/PokeToy/MenuBuilder.swift`

**Interfaces:**
- Consumes: `Playground.startGame/endGame/throwBall/game/lastResults`, `CatchGame`, `WildSpec`, `CatchResults`, `CatchRecord`, `SpriteStore.cachedSpritePaths/spriteDirectory(for:timeout:)`, `ItemArt`, `Item.wobbleAngle`, `DragTracker` (Task 14).
- Produces (app-internal): `GameController { status: Status { idle, loading, running, failed(String) }; beginLoading(); begin(); fail(_:); finish(); redraw(); showResults(_:best:isNewBest:keepable:) }`; `GameOverlayWindow(screen:showsHUD:model:controller:)` with `gameView`; `ResultsWindowController(model:results:best:isNewBest:keepable:) { show() }`; `AppModel.isGameRunning`, `startCatchGame()`, `endCatchGame()`, `throwBall(from:velocity:)`, `keepCatches(_:)`.

AppKit glue, verified by running the app (Step 3).

- [ ] **Step 1: Game controller, overlay and results window**

<!-- file: Sources/PokeToy/GameController.swift -->
```swift
import AppKit
import PokeToyCore

/// The catch game's on-screen parts: overlays that capture the mouse, the HUD and the results window.
@MainActor
final class GameController {
    enum Status: Equatable {
        case idle
        case loading
        case running
        case failed(String)
    }

    private unowned let model: AppModel
    private(set) var status: Status = .idle
    private var overlays: [GameOverlayWindow] = []
    private var results: ResultsWindowController?

    init(model: AppModel) {
        self.model = model
    }

    func beginLoading() {
        status = .loading
        showOverlays()
    }

    func begin() {
        status = .running
    }

    /// Shows `message` in the HUD for three seconds, then closes the overlays.
    func fail(_ message: String) {
        status = .failed(message)
        redraw()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .failed = self.status else { return }
                self.finish()
            }
        }
    }

    func finish() {
        status = .idle
        for overlay in overlays { overlay.close() }
        overlays = []
    }

    func redraw() {
        for overlay in overlays { overlay.gameView.needsDisplay = true }
    }

    func showResults(_ results: CatchResults, best: Int, isNewBest: Bool, keepable: Int) {
        let controller = ResultsWindowController(model: model, results: results, best: best, isNewBest: isNewBest,
                                                 keepable: keepable)
        self.results = controller
        controller.show()
    }

    private func showOverlays() {
        for overlay in overlays { overlay.close() }
        let primary = NSScreen.screens.first
        overlays = NSScreen.screens.map {
            GameOverlayWindow(screen: $0, showsHUD: $0 == primary, model: model, controller: self)
        }
        NSApp.activate()
        for overlay in overlays { overlay.orderFrontRegardless() }
        if let first = overlays.first {
            first.makeKey()
            first.makeFirstResponder(first.gameView)
        }
    }
}
```

<!-- file: Sources/PokeToy/GameOverlayWindow.swift -->
```swift
import AppKit
import PokeToyCore

/// Full-screen, nearly transparent window that takes the mouse during a catch round and draws the balls and HUD.
@MainActor
final class GameOverlayWindow: NSWindow {
    let gameView: GameView

    init(screen: NSScreen, showsHUD: Bool, model: AppModel, controller: GameController) {
        gameView = GameView(model: model, controller: controller, showsHUD: showsHUD)
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.06)  // a faint tint shows the game has the mouse
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        contentView = gameView
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
final class GameView: NSView {
    private unowned let model: AppModel
    private unowned let controller: GameController
    private let showsHUD: Bool
    private var drag = DragTracker()
    private var holding = false

    init(model: AppModel, controller: GameController, showsHUD: Bool) {
        self.model = model
        self.controller = controller
        self.showsHUD = showsHUD
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        holding = true
        let point = NSEvent.mouseLocation
        drag.begin(at: point, objectPosition: point)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        _ = drag.move(to: NSEvent.mouseLocation)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard holding else { return }
        holding = false
        let point = NSEvent.mouseLocation
        let ballHeight = CGFloat(ItemArt.size) * model.playground.scale
        model.throwBall(from: CGPoint(x: point.x, y: point.y - ballHeight / 2), velocity: drag.releaseVelocity(cap: 2200))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            model.endCatchGame()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let window, let context = NSGraphicsContext.current?.cgContext else { return }
        let origin = window.frame.origin
        let size = CGFloat(ItemArt.size) * model.playground.scale
        let ball = ItemArt.frame(for: .pokeBall).image
        context.interpolationQuality = .none
        for item in model.playground.items where item.kind == .pokeBall {
            let base = CGPoint(x: item.body.position.x - origin.x, y: item.body.position.y - origin.y)
            guard bounds.insetBy(dx: -size, dy: -size).contains(base) else { continue }
            context.saveGState()
            context.translateBy(x: base.x, y: base.y + size / 2)
            context.rotate(by: -item.wobbleAngle)
            if case .fading(let remaining) = item.state { context.setAlpha(CGFloat(min(1, max(0, remaining / 0.5)))) }
            context.draw(ball, in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
            context.restoreGState()
        }
        if holding {
            let mouse = NSEvent.mouseLocation
            context.draw(ball, in: CGRect(x: mouse.x - origin.x - size / 2, y: mouse.y - origin.y - size / 2,
                                          width: size, height: size))
        }
        if showsHUD { drawHUD() }
    }

    private func drawHUD() {
        var big = false
        let text: String
        switch controller.status {
        case .idle:
            return
        case .loading:
            text = "Getting wild Pokémon…"
        case .failed(let message):
            text = message
        case .running:
            guard let game = model.playground.game else { return }
            switch game.phase {
            case .countdown(let remaining):
                text = "\(max(1, Int(remaining.rounded(.up))))"
                big = true
            case .playing(let remaining) where remaining > CatchGame.roundLength - 0.8:
                text = "Go!"
                big = true
            case .playing(let remaining):
                text = "⏱ \(Int(remaining.rounded(.up)))    ★ \(game.score)    ◓ \(game.catches.count)    Esc to stop"
            case .finished:
                return
            }
        }
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: big ? 96 : 20, weight: .bold),
            .foregroundColor: NSColor.white,
        ])
        let size = string.size()
        let x = (bounds.width - size.width) / 2
        let y = big ? (bounds.height - size.height) / 2 : bounds.height - size.height - 48
        NSColor.black.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 16, y: y - 8, width: size.width + 32, height: size.height + 16),
                     xRadius: 12, yRadius: 12).fill()
        string.draw(at: CGPoint(x: x, y: y))
    }
}
```

<!-- file: Sources/PokeToy/ResultsWindowController.swift -->
```swift
import AppKit
import PokeToyCore

/// End-of-round summary: score, best score, and which catches to keep as pets.
@MainActor
final class ResultsWindowController: NSWindowController {
    private unowned let model: AppModel
    private let results: CatchResults
    private var checkboxes: [NSButton] = []

    init(model: AppModel, results: CatchResults, best: Int, isNewBest: Bool, keepable: Int) {
        self.model = model
        self.results = results
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 220), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Catch Results"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        var rows: [NSView] = []
        let headline = NSTextField(labelWithString: "Score: \(results.score)")
        headline.font = .boldSystemFont(ofSize: 22)
        rows.append(headline)
        rows.append(NSTextField(labelWithString: isNewBest ? "New best score!" : "Best: \(best)"))
        if results.catches.isEmpty {
            rows.append(NSTextField(labelWithString: "Nothing caught this time."))
        } else {
            rows.append(NSTextField(labelWithString: "Caught — tick the ones to keep as pets:"))
            for (index, record) in results.catches.enumerated() {
                let box = NSButton(checkboxWithTitle: record.displayName, target: nil, action: nil)
                box.state = index < keepable ? .on : .off
                box.isEnabled = index < keepable
                checkboxes.append(box)
                rows.append(box)
            }
            if keepable < results.catches.count {
                rows.append(NSTextField(labelWithString: "You can keep \(keepable) more (limit \(Playground.maxOwnPets) pets)."))
            }
        }
        let keep = NSButton(title: results.catches.isEmpty ? "OK" : "Keep Selected", target: self, action: #selector(keepSelected))
        keep.keyEquivalent = "\r"
        let release = NSButton(title: "Release All", target: self, action: #selector(releaseAll))
        release.isHidden = results.catches.isEmpty
        let buttons = NSStackView(views: [release, keep])
        buttons.orientation = .horizontal
        rows.append(buttons)

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.setContentSize(stack.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func keepSelected() {
        let kept = zip(results.catches, checkboxes).filter { $0.1.state == .on }.map(\.0)
        model.keepCatches(kept)
        close()
    }

    @objc private func releaseAll() {
        close()
    }
}
```

- [ ] **Step 2: Wire the game into the model and menus**

<!-- file: Sources/PokeToy/AppModel.swift -->
```swift
import AppKit
import OSLog
import PokeToyCore

enum AppError: LocalizedError {
    case tooManyPets

    var errorDescription: String? {
        switch self {
        case .tooManyPets: return "You already have \(Playground.maxOwnPets) pets — remove one first."
        }
    }
}

/// A wild Pokémon's catalog entry with its loaded sprites.
private struct LoadedWild: Sendable {
    let entry: CatalogEntry
    let sprites: SpriteSet
}

/// Owns the settings, the sprite store and the playground, and drives the 60 Hz tick.
@MainActor
final class AppModel {
    private(set) var settings: Settings
    private(set) var playground: Playground
    private let store: SpriteStore
    private let worldMonitor = WorldMonitor()
    private var petViews: [UUID: PetController] = [:]
    private var itemViews: [UUID: ItemController] = [:]
    private var wildSprites: [String: SpriteSet] = [:]
    private var gameAttempt = UUID()
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private lazy var picker = PickerWindowController(model: self)
    private lazy var gameUI = GameController(model: self)
    private let logger = Logger(subsystem: "local.poketoy.PokeToy", category: "app")

    init() {
        let settings = Settings.load(from: .standard)
        self.settings = settings
        playground = Playground(seed: .random(in: .min ... .max), scale: CGFloat(settings.scale),
                                friendships: Friendships(points: settings.friendships))
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeToy", isDirectory: true)
        store = SpriteStore(cacheDirectory: caches,
                            bundledSprites: Bundle.main.resourceURL?.appendingPathComponent("Sprites", isDirectory: true))
    }

    func start() {
        worldMonitor.start()
        for record in settings.pets {
            Task {
                do {
                    attach(record, sprites: try await loadSprites(record.spritePath))
                } catch {
                    logger.error("Couldn't load \(record.spritePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Pets

    func addPet(_ entry: CatalogEntry) async throws {
        guard settings.pets.count < Playground.maxOwnPets else { throw AppError.tooManyPets }
        let sprites = try await loadSprites(entry.path)
        guard settings.pets.count < Playground.maxOwnPets else { throw AppError.tooManyPets }
        let record = PetRecord(spritePath: entry.path, displayName: entry.displayName)
        settings.pets.append(record)
        if settings.hidden { setHidden(false) }
        attach(record, sprites: sprites)
        save()
    }

    func removePet(_ id: UUID) {
        playground.removePet(id)
        petViews.removeValue(forKey: id)?.close()
        settings.pets.removeAll { $0.id == id }
        save()
    }

    func bestFriendName(of id: UUID) -> String? {
        guard let friend = playground.friendships.bestFriend(of: id, among: settings.pets.map(\.id)) else { return nil }
        return settings.pets.first { $0.id == friend }?.displayName
    }

    func handle(_ event: PetEvent, pet id: UUID) {
        playground.handle(event, pet: id)
    }

    func movePet(_ id: UUID, to point: CGPoint) {
        playground.movePet(id, to: point)
    }

    // MARK: - Treats

    var canFeed: Bool { !isGameRunning && playground.canDropTreat }

    /// Drops a random treat from the top of the screen under the cursor.
    func feed() {
        guard canFeed else { return }
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        let kind: ItemKind = Bool.random() ? .apple : .oranBerry
        playground.dropTreat(kind, at: CGPoint(x: cursor.x, y: screen.visibleFrame.maxY - 10))
    }

    func handle(_ event: ItemEvent, item id: UUID) {
        playground.handle(event, item: id)
    }

    func moveItem(_ id: UUID, to point: CGPoint) {
        playground.moveItem(id, to: point)
    }

    // MARK: - Catch game

    var isGameRunning: Bool { gameUI.status != .idle || playground.game != nil }

    /// Loads a roster of wild Pokémon (complete sprite sets first, cached ones when offline) and starts a round.
    func startCatchGame() {
        guard !isGameRunning else { return }
        gameUI.beginLoading()
        let attempt = UUID()
        gameAttempt = attempt
        Task {
            let roster = await loadRoster()
            guard gameAttempt == attempt, gameUI.status == .loading else { return }  // cancelled meanwhile
            if roster.isEmpty {
                gameUI.fail("Couldn't load wild Pokémon")
            } else {
                playground.startGame(roster: roster, seed: .random(in: .min ... .max))
                gameUI.begin()
            }
        }
    }

    func endCatchGame() {
        if playground.game != nil {
            playground.endGame()
        } else {
            gameAttempt = UUID()
            gameUI.finish()
        }
    }

    func throwBall(from point: CGPoint, velocity: CGVector) {
        playground.throwBall(from: point, velocity: velocity)
    }

    /// Turns kept catches into pets where they were caught.
    func keepCatches(_ records: [CatchRecord]) {
        for record in records {
            guard settings.pets.count < Playground.maxOwnPets, let sprites = wildSprites[record.path] else { continue }
            let pet = PetRecord(spritePath: record.path, displayName: record.displayName, position: record.position)
            settings.pets.append(pet)
            attach(pet, sprites: sprites)
        }
        save()
    }

    // MARK: - Settings

    func setHidden(_ hidden: Bool) {
        settings.hidden = hidden
        for record in settings.pets {
            if hidden { petViews[record.id]?.hide() } else { petViews[record.id]?.show() }
        }
        for view in itemViews.values {
            if hidden { view.hide() } else { view.show() }
        }
        save()
    }

    func setCursorMode(_ mode: CursorMode) {
        settings.cursorMode = mode
        save()
    }

    func setScale(_ scale: Int) {
        settings.scale = min(max(scale, 1), 3)
        playground.setScale(CGFloat(settings.scale))
        save()
    }

    func showPicker() {
        picker.show()
    }

    func catalog(forceRefresh: Bool) async throws -> [CatalogEntry] {
        try await store.catalog(forceRefresh: forceRefresh)
    }

    /// Records current pet positions and friendships and writes settings to disk.
    func save() {
        for index in settings.pets.indices {
            if let pet = playground.pet(settings.pets[index].id) { settings.pets[index].position = pet.body.position }
        }
        settings.friendships = playground.friendships.points
        settings.save(to: .standard)
    }

    // MARK: - Private

    private func loadSprites(_ path: String) async throws -> SpriteSet {
        let directory = try await store.spriteDirectory(for: path)
        return try SpriteSet(directory: directory)
    }

    private func attach(_ record: PetRecord, sprites: SpriteSet) {
        // A pet removed while its sprites were loading is dropped.
        guard settings.pets.contains(where: { $0.id == record.id }), petViews[record.id] == nil else { return }
        let world = worldMonitor.world
        let start = record.position.flatMap { world.isOnAnyScreen($0, margin: 0) ? $0 : nil }
            ?? world.spawnPoint(fraction: .random(in: 0.2...0.8))
        playground.addPet(id: record.id, role: .own, metrics: PetMetrics(sprites: sprites), at: start)
        let view = PetController(id: record.id, sprites: sprites, model: self, interactive: true)
        if !settings.hidden { view.show() }
        petViews[record.id] = view
    }

    private func loadRoster() async -> [WildSpec] {
        let catalog = (try? await store.catalog()) ?? []
        let complete = catalog.filter(\.isComplete)
        let pool = complete.isEmpty ? catalog : complete
        var loaded = await loadWild(Array(pool.shuffled().prefix(8)))
        if loaded.count < 3 {
            // Offline or unlucky: fill up with Pokémon already on disk (the bundled Pikachu is always there).
            let names = Dictionary(catalog.map { ($0.path, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            let have = Set(loaded.map(\.entry.path))
            let cached = await store.cachedSpritePaths().filter { !have.contains($0) }.shuffled().prefix(8 - loaded.count)
            loaded += await loadWild(cached.map {
                CatalogEntry(path: $0, displayName: names[$0] ?? ($0 == "0025" ? "Pikachu" : "Pokémon #\($0)"))
            })
        }
        for wild in loaded { wildSprites[wild.entry.path] = wild.sprites }
        return loaded.map {
            WildSpec(path: $0.entry.path, displayName: $0.entry.displayName, metrics: PetMetrics(sprites: $0.sprites))
        }
    }

    private func loadWild(_ entries: [CatalogEntry]) async -> [LoadedWild] {
        let store = self.store
        return await withTaskGroup(of: LoadedWild?.self) { group in
            for entry in entries {
                group.addTask {
                    guard let directory = try? await store.spriteDirectory(for: entry.path, timeout: 10),
                          let sprites = try? SpriteSet(directory: directory) else { return nil }
                    return LoadedWild(entry: entry, sprites: sprites)
                }
            }
            var result: [LoadedWild] = []
            for await wild in group {
                if let wild { result.append(wild) }
            }
            return result
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTick == 0 ? 1.0 / 60.0 : min(now - lastTick, 0.1)
        lastTick = now
        let cursor = NSEvent.mouseLocation
        let events = playground.tick(dt: dt, world: worldMonitor.world, cursor: cursor, cursorMode: settings.cursorMode)
        var friendshipsChanged = false
        for event in events {
            switch event {
            case .wildSpawned(let id, let path):
                if let sprites = wildSprites[path] {
                    let view = PetController(id: id, sprites: sprites, model: self, interactive: false)
                    view.show()
                    petViews[id] = view
                }
            case .wildRemoved(let id):
                petViews.removeValue(forKey: id)?.close()
            case .friendshipChanged:
                friendshipsChanged = true
            case .roundEnded:
                showResults()
            default:
                break
            }
        }
        if friendshipsChanged { save() }
        syncItemViews()
        for pet in playground.pets { petViews[pet.id]?.render(pet, cursor: cursor) }
        for item in playground.items { itemViews[item.id]?.render(item, cursor: cursor, scale: playground.scale) }
        gameUI.redraw()
    }

    private func showResults() {
        gameUI.finish()
        guard let results = playground.lastResults else { return }
        let isNewBest = results.score > settings.bestCatchScore
        if isNewBest {
            settings.bestCatchScore = results.score
            save()
        }
        let keepable = CatchGame.keepable(results.catches, ownPetCount: settings.pets.count, cap: Playground.maxOwnPets)
        gameUI.showResults(results, best: settings.bestCatchScore, isNewBest: isNewBest, keepable: keepable)
    }

    /// Opens a panel for each new treat and closes panels whose treat is gone.
    private func syncItemViews() {
        let treats = Set(playground.items.filter { $0.kind.isTreat }.map(\.id))
        for (id, view) in itemViews where !treats.contains(id) {
            view.close()
            itemViews[id] = nil
        }
        for id in treats where itemViews[id] == nil {
            let view = ItemController(id: id, model: self)
            if settings.hidden { view.hide() }
            itemViews[id] = view
        }
    }
}
```

<!-- file: Sources/PokeToy/MenuBuilder.swift -->
```swift
import AppKit
import PokeToyCore

/// Menu item that runs a closure; `enabled` (if given) decides whether it can be chosen.
@MainActor
final class ActionItem: NSMenuItem, NSMenuItemValidation {
    private let handler: () -> Void
    private let isAllowed: (() -> Bool)?

    init(_ title: String, key: String = "", state: NSControl.StateValue = .off, enabled: (() -> Bool)? = nil,
         handler: @escaping () -> Void) {
        self.handler = handler
        isAllowed = enabled
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        self.state = state
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        isAllowed?() ?? true
    }
}

extension CursorMode {
    var title: String {
        switch self {
        case .off: return "Off"
        case .follow: return "Follow Cursor"
        case .flee: return "Run from Cursor"
        }
    }
}

/// Builds the status-item, Dock and main menus from the current `AppModel` state.
@MainActor
final class MenuBuilder: NSObject, NSMenuDelegate {
    private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populate(menu, includeQuit: true)
        return menu
    }

    func makeDockMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu, includeQuit: false)  // the Dock adds its own Quit
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu, includeQuit: true)
    }

    func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "PokeToy")
        appMenu.addItem(withTitle: "About PokeToy",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(ActionItem("Add Pokémon…", key: "n") { [unowned model] in model.showPicker() })
        appMenu.addItem(ActionItem("Feed", key: "f", enabled: { [unowned model] in model.canFeed }) {
            [unowned model] in model.feed()
        })
        appMenu.addItem(ActionItem("Start/End Catch Game", key: "g") { [unowned model] in
            if model.isGameRunning { model.endCatchGame() } else { model.startCatchGame() }
        })
        appMenu.addItem(ActionItem("Show/Hide Pets") { [unowned model] in model.setHidden(!model.settings.hidden) })
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PokeToy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(edit, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(window, to: main)
        return main
    }

    private func populate(_ menu: NSMenu, includeQuit: Bool) {
        menu.removeAllItems()
        let hidden = model.settings.hidden
        menu.addItem(ActionItem(hidden ? "Show Pets" : "Hide Pets") { [unowned model] in model.setHidden(!hidden) })
        menu.addItem(ActionItem("Add Pokémon…") { [unowned model] in model.showPicker() })
        menu.addItem(ActionItem("Feed", enabled: { [unowned model] in model.canFeed }) { [unowned model] in model.feed() })
        if model.isGameRunning {
            menu.addItem(ActionItem("End Catch Game") { [unowned model] in model.endCatchGame() })
        } else {
            menu.addItem(ActionItem("Start Catch Game") { [unowned model] in model.startCatchGame() })
        }
        menu.addItem(.separator())

        let pets = model.settings.pets
        if pets.isEmpty {
            menu.addItem(NSMenuItem(title: "No pets yet", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Pets", action: nil, keyEquivalent: ""))
            for pet in pets {
                let item = NSMenuItem(title: pet.displayName, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                if let friend = model.bestFriendName(of: pet.id) {
                    submenu.addItem(NSMenuItem(title: "Best friend: \(friend)", action: nil, keyEquivalent: ""))
                    submenu.addItem(.separator())
                }
                submenu.addItem(ActionItem("Remove") { [unowned model] in model.removePet(pet.id) })
                item.submenu = submenu
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        let cursorMenu = NSMenu()
        for mode in CursorMode.allCases {
            cursorMenu.addItem(ActionItem(mode.title, state: model.settings.cursorMode == mode ? .on : .off) {
                [unowned model] in model.setCursorMode(mode)
            })
        }
        addSubmenu(cursorMenu, titled: "Cursor", to: menu)

        let sizeMenu = NSMenu()
        for scale in 1...3 {
            sizeMenu.addItem(ActionItem("\(scale)×", state: model.settings.scale == scale ? .on : .off) {
                [unowned model] in model.setScale(scale)
            })
        }
        addSubmenu(sizeMenu, titled: "Size", to: menu)

        if includeQuit {
            menu.addItem(.separator())
            menu.addItem(ActionItem("Quit PokeToy") { NSApp.terminate(nil) })
        }
    }

    private func addSubmenu(_ submenu: NSMenu, titled title: String? = nil, to menu: NSMenu) {
        let item = NSMenuItem(title: title ?? submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}
```

- [ ] **Step 3: Build, run and verify by hand**

Run: `./scripts/test.sh 2>&1 | tail -1 && swift build 2>&1 | grep -E "error:" ; ./scripts/build-app.sh && open build/PokeToy.app`
Expected: suite passes, no build errors, "Built build/PokeToy.app".

Check and note any failure:
1. Menu bar, Dock menu and ⌘G → **Start Catch Game**: the screen dims slightly, "Getting wild Pokémon…", then "3 · 2 · 1 · Go!".
2. Wild Pokémon run in from screen edges (at most 3), dodge the cursor, and leave after a while.
3. Press, flick and release anywhere to throw a Poké Ball; a hit makes the Pokémon vanish into the ball, which drops and wobbles 1–3 times, then catches (score +100, own pets cheer) or breaks free (the Pokémon pops out and dashes away).
4. The HUD shows time, score and catches; own pets sit and watch; Feed is disabled during the round.
5. After 60 s (or Esc / End Catch Game) the overlay goes away and a results window shows score, best score ("New best score!" on a record) and the catches with Keep checkboxes; **Keep Selected** adds them as pets where they were caught; **Release All** doesn't.
6. Clicks reach other apps again after the round.
7. Turn off Wi-Fi and start a round: wild Pokémon come from already-downloaded ones (at least Pikachu).

- [ ] **Step 4: Commit**

```bash
git add Sources/PokeToy
git commit -m "feat: catch game overlay, HUD and results window"
```

---

### Task 16: README and final verification

**Files:**
- Modify: `README.md` (replace the "Using it" section as shown)

- [ ] **Step 1: Update the README**

In `README.md`, replace the whole `## Using it` section (up to `## Development`) with:

<!-- snippet: README Using it -->
````markdown
## Using it

- **Click** a pet to make it happy; **drag** it to pick it up and let go (or throw it — thrown pets knock others over).
- Pets wander along the Dock, the bottom of the screen and the tops of your windows, nap when ignored and wake up on their own.
- Pets that meet greet each other, play tag or play-fight. Pairs that play a lot become **friends** and then **best friends**,
  who seek each other out and nap side by side (Pets → *name* shows a pet's best friend).
- **Feed** (⌘F) drops an apple or Oran Berry above the cursor; the nearest pet runs over to eat it. Treats can be dragged and thrown too.
- **Start Catch Game** (⌘G): a 60-second round where wild Pokémon run across the screen. Press, flick and release to throw
  Poké Balls. Hits score 25, catches 100. Afterwards, pick which catches to keep as pets. Esc ends the round early.
- Menu bar paw icon or right-click the Dock icon:
  - **Show / Hide Pets**, **Add Pokémon…**, **Feed**, **Start / End Catch Game**
  - **Pets** — best friend and Remove
  - **Cursor** — Off, Follow Cursor, Run from Cursor
  - **Size** — 1×, 2×, 3×
- **Add Pokémon…** lists Pokémon with complete sprite sets; tick **Show all Pokémon** for every entry on SpriteCollab.
  Sprites download on first use and are cached in `~/Library/Caches/PokeToy`. Up to 12 pets.
- Clicking the Dock icon shows hidden pets, or opens the picker.

````

- [ ] **Step 2: Full verification**

Run: `./scripts/test.sh 2>&1 | tail -1 && ./scripts/build-app.sh`
Expected: all tests pass and "Built build/PokeToy.app".

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README for feeding, friendships and the catch game"
```
