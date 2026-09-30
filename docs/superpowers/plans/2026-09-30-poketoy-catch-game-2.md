# PokeToy Catch Game 2.0 Implementation Plan (sub-project B)

> Executed natively by the same session that wrote it. As in sub-project A (ledgered ruling): tasks, files,
> interfaces and tests are listed here; the code is written test-first straight into the sources.

**Spec:** `docs/superpowers/specs/2026-09-30-poketoy-catch-game-2-design.md`

## Global Constraints
- Same as sub-project A (SwiftPM, Swift 5 mode, `./scripts/test.sh`, `PetActor` wrappers, additive events).
- Rosters use base forms only (paths without `/`); shiny variants come from `<dex>/0000/0001`.
- Catch chance: Poké 0.6, Great 0.75, Ultra 0.9, +0.15 when calmed by a berry; tests may override.

## Review Focus
1. Combo/tier reset exactly on a miss (a ball landing without a hit) — not on berries, not on wobbling balls.
2. Flying wilds must always leave (off an edge) and be hittable; after breaking free they fall like others.
3. Daily roster must be deterministic for a given date and catalog, independent of cache state.
4. Pokédex recording must count each catch once, including catches resolved at round end.
5. Scoring multipliers compose correctly (legendary × shiny × combo cap, first-throw bonus once).

### Task 1: Data — `Legendaries`, `DailyChallenge`, `Pokedex`, settings, PokeAPI types
- Files: `Legendaries.swift`, `DailyChallenge.swift`, `Pokedex.swift` (new); `Settings.swift`; `Evolution.swift` (`EvolutionStore.types(of:)`).
- Tests (`CatchDataTests`): `knowsLegendaries`, `dailySeedAndKeyFollowTheDate`, `dailyRosterIsDeterministic`, `dailyRosterHasOneLegendaryAndBaseFormsOnly`, `pokedexRecordsCatches`, `pokedexCompletion`, `settingsDecodePokedexAndDailyBest`, `storeFetchesTypes`.

### Task 2: `CatchGame` — rarity, shinies, tiers, combos, berries, scoring
- Files: `CatchGame.swift`, `ItemArt.swift` (greatBall, ultraBall, razzBerry).
- Tests (`CatchGame2Tests`): `legendariesSpawnRarely`, `shiniesNeedAShinyPath`, `shinyRate`, `comboRaisesTheBallTier`, `aMissResetsTheCombo`, `catchChanceFollowsTheTierAndCalm`, `pointsMultiply`, `comboMultiplierIsCapped`, `firstThrowBonus`, `threeBerriesPerRound`.

### Task 3: Playground — tiered throws, misses, berries, shinies, first-throw, flying, window hopping
- Files: `Playground+Game.swift`, `Playground.swift`, `PetBrain.swift` (calm, wild window-hop preference).
- Tests (`GameTwoTests`): `throwsUseTheCurrentTier`, `landingBallsResetTheCombo`, `berriesCalmWilds`, `shinySpawnsAreReported`, `catchesRecordShinyAndBonus`, `flyingWildsGlideAndLeave`, `flyingWildsCanBeCaughtAndFallAfterBreakingFree`, `wildsPreferWindowTops`.

### Task 4: App
- Roster building (base forms, 1 legendary, shiny sprites, flying types), spawn sprite choice, HUD (tier, combo, berries), aiming arc, ⇧-berry throws, wild bubbles, Daily Challenge item + daily best, Pokédex window + recording, README.

### Task 5: Final verification and whole-branch review.
