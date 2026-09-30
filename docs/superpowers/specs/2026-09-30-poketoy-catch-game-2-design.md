# PokeToy Catch Game 2.0 — Design (sub-project B)

Date: 2026-09-30
Builds on: `2026-09-30-poketoy-play-design.md` (catch game), `2026-09-30-poketoy-pet-life-design.md`

## Goal

Give the timed catch game depth and a reason to come back: rare and shiny Pokémon, a Pokédex,
better balls earned by combos, berries, scoring bonuses, flying and window-hopping wilds, an
aiming arc, and a daily challenge.

## Agreed defaults (from the sub-project split)

- Legendary/mythical Pokémon appear in about 5% of spawns and are worth 3× points; shinies are
  1 in 64 and worth 2×; only Pokémon with a shiny sprite on SpriteCollab can be shiny.
- Daily challenge: the same roster and game seed for everyone each day (from the date), its own
  best score, a separate menu item next to Start Catch Game.

## Rarity

- `Legendaries.isLegendary(dex:)`: a built-in list of legendary and mythical national dex numbers
  (Gen 1–9). Offline-safe; no PokeAPI call needed.
- `WildSpec` gains `isLegendary: Bool` and `shinyPath: String?` (SpriteCollab `<dex>/0000/0001`
  when the catalog has it; its sprites are loaded with the roster).
- Roster: 7 regular complete Pokémon plus 1 legendary (random complete legendary), when available.
- Spawning: a legendary with probability 0.05 (if the roster has one), otherwise a random regular.
  Each spawn is shiny with probability 1/64 when its spec has a shiny path.
- `PlaygroundEvent.wildSpawned` gains `shiny: Bool` so the app shows the shiny sprites; shinies
  sparkle (✦) when they appear.
- Points: hit 25, catch 100, × 3 for legendaries, × 2 for shinies (× 6 for a shiny legendary).

## Balls, combos and berries

- Ball tiers: **Poké Ball** (catch chance 0.6), **Great Ball** (0.75), **Ultra Ball** (0.9), each
  with its own pixel art.
- A combo counts consecutive hits. After 3 in a row the next balls are Great Balls; after 5, Ultra
  Balls. A ball that lands without hitting anything resets the combo and the tier to Poké Ball.
- Combo multiplier on points: × (1 + 0.25 × (combo − 1)), capped at × 2.
- **First-throw bonus:** catching a Pokémon with the first ball that hit it (it never broke free) +50.
- **Razz Berries:** 3 per round. Holding ⇧ Shift while releasing a throw throws a berry instead of a
  ball. A berry that hits a wild calms it for 8 s: it moves at half speed, stops fleeing the cursor,
  and gets +0.15 catch chance. A calmed wild shows a 😊 bubble. The HUD shows berries left.

## Flying and window-hopping wilds

- `WildSpec.canFly` from PokeAPI types (`pokemon/{dex}` has type `flying`), fetched with the roster
  (3 s budget; unknown → false) and cached by `EvolutionStore`.
- A flying wild doesn't walk: it glides across the screen at a random height between 150 pt above
  the floor and 70% of the screen height, bobbing ±40 pt, turning around at screen edges, and leaves
  by flying off an edge. No gravity until it breaks out of a ball (then it drops and dashes like
  others).
- Walking wilds prefer window tops: their random jump chance rises to 0.5, preferring window
  surfaces over floors.

## Aiming arc

- While a ball is held and the mouse is moving, the overlay draws a dotted arc: the ball's predicted
  path for the current flick velocity under gravity (dots every 0.05 s for up to 1.2 s), fading out.

## Daily challenge

- `DailyChallenge.seed(for date:)` = yyyymmdd; `DailyChallenge.roster(from catalog:seed:)` picks 7
  regular + 1 legendary deterministically from the complete catalog entries sorted by path.
- The game RNG uses the same seed, so spawn order and catch rolls match for everyone: the roster is
  sorted by path, and spawns, placement and catch rolls draw from separate streams that always consume
  the same number of values (whether or not a Pokémon has a shiny sprite or can fly).
- The day is the Gregorian date in the local time zone, fixed when the round starts.
- The daily challenge needs its full roster; if any of it can't be loaded (offline), it doesn't start
  (no substitutes from the cache, no daily best).
- `Settings.dailyBest: [String: Int]` keyed `yyyy-MM-dd`; results show "Daily best" for daily runs.
- Menu: **Daily Challenge** next to Start Catch Game (menus and the app menu).

## Pokédex

- `Settings.pokedex: [String: PokedexEntry]` keyed by species dex path (`0025`): `displayName`,
  `firstCaught: Date`, `count`, `shinyCaught: Bool`. Recorded for every catch at the end of a round
  (kept or released), tolerant decoding.
- `Pokedex.completion(caught:catalog:)` = distinct species caught / distinct species in the catalog
  with complete sprites.
- **Pokédex…** window (menus): completion %, then a list of species (Normal portrait, name,
  first-seen date, times caught, ✦ if a shiny was caught), newest first; it refreshes while open.

## Architecture

- Core: `Legendaries`, `DailyChallenge`, `Pokedex`/`PokedexEntry`, `WildSpec` fields, `BallTier`,
  combo/bonus scoring and berries in `CatchGame`, flying movement and berry effects in
  `Playground+Game`, `ItemKind` greatBall/ultraBall/razzBerry with art, `Settings` fields,
  `EvolutionStore.types(of:)`.
- App: roster building (legendary, shiny sprites, flying), spawn sprite choice, overlay aiming arc and
  Shift-berry throws, HUD (tier, combo, berries), Daily Challenge item, Pokédex window, results
  daily best, Pokédex recording.

## Testing

Unit tests for: legendary list lookups; spawn weighting (legendary ≈5%, shiny ≈1/64 with a seed,
never shiny without a path); scoring multipliers (legendary, shiny, combo, cap, first-throw bonus);
ball tiers from combos and reset on a miss; catch chance per tier and berry bonus; berries (limit 3,
calming effect and duration, no fleeing, half speed); flying wilds (no gravity, height band, bobbing,
leave via an edge, fall after breaking free); window-hop preference; daily seed and deterministic
roster; Pokédex recording and completion; settings decoding. Manual: arc, HUD, shiny sparkle,
Pokédex window, daily run.

## Out of scope

Online leaderboards, trading, item shops, sound.

### Pokédex includes pets (added)

- Species also enter the Pokédex when they become pets: adopted from the picker, kept from a catch
  round, or evolved into; current pets are recorded at launch. `PokedexEntry.everOwned` marks them;
  the window shows "current pet" / "former pet" and catch counts, and pets count toward completion.

### Review fixes (added)

- A ball that lands inside a wild Pokémon's hit area is a hit, not a miss.
- Catch points use the combo multiplier from the moment the ball hit.
- Calmed wilds also dash and leave at half speed; flying wilds leave 1.5× faster and show their walk
  animation while gliding.
- ⇧ with no berries left throws a ball.
- Shiny pets remember they are shiny (`PetRecord.isShiny`) and evolve into the shiny form when
  SpriteCollab has it.
