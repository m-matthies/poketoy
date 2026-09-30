# PokeToy Pet Life Implementation Plan (sub-project A)

> **For agentic workers:** executed natively (superpowers:executing-plans) by the same session that wrote it.
> Ruling (recorded in the ledger): because planner and executor are the same in-session author, this plan
> lists tasks, files, interfaces and the exact tests; the code itself is written test-first straight into the
> source files and lives in the commits, instead of being duplicated here.

**Goal:** Emotions, stroking, annoyance, fetch, shaken windows, parades, idle/day-night/Reduce Motion,
wandering between monitors, and evolution.

**Spec:** `docs/superpowers/specs/2026-09-30-poketoy-pet-life-design.md`

## Global Constraints

- macOS 14+, SwiftPM, Swift 5 mode; tests via `./scripts/test.sh`; `#expect` never wraps a mutating call.
- Playground mutations of a pet go through `PetActor` wrappers (no `pets[i].brain.x(body: &pets[i].body)`).
- New `BrainContext` fields have defaults so existing call sites and tests keep compiling.
- New `PlaygroundEvent` cases are additive; existing event equality tests must keep passing.

## Review Focus

1. Stroking vs. clicking: a click must never count as a stroke, and stroking must not trigger on a pet being dragged. (`StrokeTests.pressedMouseIsNotStroking`)
2. A fetch carrier that gets dragged/knocked/falls must drop the ball — never an invisible or orphaned ball. (`FetchTests.interruptedCarrierDropsTheBall`)
3. Window shake detection must not fire on the 5 Hz step pattern of normal window drags. (`ShakeTests.slowDragKeepsPetsOn`)
4. Indefinite "away" naps must end when the user returns, including after the Mac slept. (`AwayTests.returningUserWakesEveryone`)
5. Evolving must keep the pet's id, friendships and position; unknown/final species offer nothing. (`EvolutionTests.*`, manual)

---

### Task 1: Emotions
- Files: `Sources/PokeToyCore/Emotion.swift` (new), `Playground.swift` (event case, `thrownByUser`), `Playground+Feeding.swift`, `Playground+Collisions.swift`, `Playground+Social.swift`.
- Produces: `enum Emotion: CaseIterable { happy, joyous, sad, angry, surprised, pain, dizzy }` with `portraitNames: [String]` (fallback chain ending "Normal") and `emoji`; `PlaygroundEvent.emotion(petID: UUID, Emotion)`.
- Tests (`EmotionTests`): `portraitFallbacksEndInNormal`, `eatingIsJoyous`, `latecomersAreSad`, `knockedOverHurts`, `hardUserThrowLandsDizzy`, `bestFriendGreetingIsHappy`.

### Task 2: Stroking and getting annoyed
- Files: `PetAnim.swift` (`shoot`), `PetBrain.swift` (`petted(body:)`, `interrupt(with:body:)`, sleep hearts), `Playground.swift` (clock, `lastCursor`), `Playground+Petting.swift` (new).
- Produces: `Playground.stroke(pet:cursorX:)`; click counting inside `handle(.click, pet:)`.
- Tests (`StrokeTests`): `threeReversalsStroke`, `smallWigglesDoNotCount`, `slowStrokesDoNotCount`, `strokingASleeperKeepsItAsleep`, `strokeCooldown`, `pressedMouseIsNotStroking`, `fiveQuickClicksAnnoy`, `clicksWhileAnnoyedAreIgnored`, `slowClicksDoNotAnnoy`.

### Task 3: Fetch
- Files: `ItemArt.swift` (`toyBall` + grid), `Item.swift` (`carried(petID:)`), `Playground.swift` (item handling for toys), `Playground+Fetch.swift` (new).
- Produces: `Playground.dropToy(at:) -> UUID?`, `canDropToy`, `randomFeedingSpot` reused; `PlaygroundEvent.fetched(petID:)`; `Playground.toyLifetime = 300`.
- Tests (`FetchTests`): `nearestPetFetchesAndBringsItBack`, `carriedBallFollowsThePet`, `racersWhoLoseAreSad`, `interruptedCarrierDropsTheBall`, `onlyOneToyBall`, `toyBallsAreNotTreats`, `untouchedToyDisappears`.

### Task 4: Shaken windows
- Files: `Playground+Shake.swift` (new), `Playground.swift` (motion state), `PetBrain.swift` (`look(toward:)`).
- Tests (`ShakeTests`): `shakingAWindowThrowsPetsOff`, `aVeryFastMoveThrowsPetsOff`, `slowDragKeepsPetsOn`, `surfersFaceTheMoveDirection`.

### Task 5: Parades
- Files: `Playground+Parade.swift` (new), `Playground.swift` (`parades`, `inMoment` includes parades), `Playground+Social.swift` (call).
- Tests (`ParadeTests`): `friendsFollowTheLeader`, `followersKeepTheirSpacing`, `paradeEndsAndBuildsFriendship`, `strangersDoNotParade`, `interruptingEndsTheParade`, `noParadesDuringAGame`.

### Task 6: Away, day and night, Reduce Motion
- Files: `PetBrain.swift` (`BrainContext.timeOfDay`, `.reduceMotion`, indefinite naps, `wakeAndGreet`), `Playground.swift` (`userIdleSeconds`, `timeOfDay`, `reduceMotion`, away rule), `Playground+Passing.swift`, `Playground+Parade.swift`.
- Produces: `enum TimeOfDay { morning, day, night }` + `TimeOfDay(hour:)`; `Playground.setUserIdle(_:)`.
- Tests (`AwayTests`, `TimeOfDayTests`, `ReduceMotionTests`): `petsNapWhileTheUserIsAway`, `returningUserWakesEveryone`, `hoursMapToTimesOfDay`, `nightPetsGetSleepyFast`, `morningPetsAreFaster`, `reduceMotionMeansNoRandomJumps`, `reduceMotionWalksSlower`, `reduceMotionTurnsBackInsteadOfHopping`.

### Task 7: Wandering between monitors
- Files: `PetBrain.swift` (`decideNext`).
- Tests (`MonitorWanderTests`): `petsWanderToTheNextScreen`, `petsJumpUpToAHigherNeighbourFloor`, `wildPokemonStayOnTheirScreen`.

### Task 8: Evolution data
- Files: `Evolution.swift` (new: `Evolution.parseChain`, `nextForms`, `isReady`, `treatsNeeded`), `EvolutionStore.swift` (new actor), `Settings.swift` (`PetRecord.treatsEaten`, tolerant decoding), `Playground.swift` (`replaceMetrics(of:with:)`).
- Tests (`EvolutionTests`): `parsesLinearChains`, `parsesBranchingChains`, `finalFormsHaveNoNext`, `readiness`, `storeFetchesAndCaches`, `storeReportsLegendaries`, `petRecordsDecodeWithoutTreatCount`, `replacingMetricsKeepsThePet`.

### Task 9: Portraits
- Files: `SpriteStore.swift` (`portrait(for:emotion:)`).
- Tests (`SpriteStoreTests` additions): `portraitsFollowTheFallbackChain`, `missingPortraitsAreRemembered`, `noPortraitMeansNil`.

### Task 10: App wiring
- Files: `BubbleWindow.swift` (new), `PetWindow.swift` (flash), `PetController.swift` (stroke feed, bubble, flash, sprite swap), `ItemController.swift` (toy ball), `AppModel.swift` (fetch, idle/time/reduce inputs, emotions, treat counts, evolution), `MenuBuilder.swift` (Play Fetch ⌘J, evolve items, progress line).
- Verified by `swift build`, the full suite, and by hand.

### Task 11: README and final verification
- README sections for the new behavior; full suite; bundle build; final whole-branch review.
