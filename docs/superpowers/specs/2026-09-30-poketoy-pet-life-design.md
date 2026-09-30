# PokeToy Pet Life — Design (sub-project A)

Date: 2026-09-30
Builds on: `2026-09-30-poketoy-design.md`, `2026-09-30-poketoy-play-design.md`

## Goal

Give pets more personality and more ways to play: stroking, emotion bubbles, getting
annoyed, fetch, reacting to windows being shaken, follow-the-leader lines, napping while the
user is away, a day/night rhythm, wandering between monitors, Reduce Motion, and evolution.

Sub-projects B (catch game 2.0) and C (preferences, auto-hide, pets window…) follow later.

## Decisions (agreed)

- Emotion bubbles use SpriteCollab portraits (`portrait/<path>/<Emotion>.png`), downloaded on
  demand and cached, with an emoji fallback.
- Evolution data comes from PokeAPI, fetched once per species and cached. A pet is ready after
  15 treats and having a best friend; an **Evolve into …** item appears in its Pets submenu (one
  per branch, e.g. every Eevee evolution), so the user chooses when and which. Evolving plays a
  white flash. (Refinement of the agreed "random branch": offering the branches is friendlier.)

Checked data: every one of SpriteCollab's 1,026 species has a `Normal` portrait; `Happy`,
`Sad`, `Angry`, `Surprised`, `Pain`, `Joyous` exist for ~72–78%. PokeAPI
`pokemon-species/{n}` links `evolution_chain.url`; chains nest `evolves_to` with species URLs
ending in the national dex number (= SpriteCollab's 4-digit id).

## Emotions

- `enum Emotion { happy, joyous, sad, angry, surprised, pain, dizzy }` with SpriteCollab file
  names and a fallback chain ending in `Normal` (joyous→happy, dizzy→pain→sad, surprised→Normal…)
  and an emoji (😊 😄 😢 😠 😮 😣 😵).
- `PlaygroundEvent.emotion(petID:, Emotion)` is emitted on:

| Trigger | Emotion |
|---|---|
| eats a treat | joyous |
| a nearby pet ate the treat (sad) | sad |
| knocked over by a thrown pet | pain |
| lands hard after the user threw it | dizzy |
| annoyed (see below) | angry |
| stroked | happy |
| greets a best friend | happy |
| brings the fetch ball back | joyous |
| shaken off a window | surprised |
| evolves | joyous |
| greets the user coming back | happy |

- The app shows a round bubble with the portrait (or emoji) above the pet for 2 s; a newer
  emotion replaces an older one. Portraits come from `SpriteStore.portrait(for:emotion:)`,
  cached in `~/Library/Caches/PokeToy/portrait/…`; a missing portrait (404) is remembered so it
  isn't requested again.

## Stroking

- Moving the cursor back and forth over a pet's opaque pixels (no button pressed) is stroking.
  Three direction reversals, each at least 6 pt apart, within 1.5 s → stroked.
- A stroked awake pet stops, plays `greet` with 2 hearts and shows *happy*; a stroked sleeping
  pet stays asleep, shows 2 hearts, and its nap lasts at least 30 s more. Stroking counts as
  interaction (resets the sleep timer). At most once per 3 s per pet.
- Core: `Playground.stroke(pet:cursorX:)` fed with the cursor x while it hovers the pet; the
  playground detects reversals.

## Getting annoyed

- Five clicks on the same pet within 4 s: it turns to face the cursor, plays `shoot`
  (candidates Shoot, Charge, Attack, Idle, Walk; non-looping) and shows *angry*, then storms
  off: walks 250 pt away from the cursor at 1.6× speed (clamped to its surface). Clicks during
  that don't count; the counter resets after.

## Fetch

- **Play Fetch** (menus; ⌘J in the main menu) drops a toy ball (new item kind `toyBall`, its
  own pixel art) from the top of a random screen with pets, like Feed. At most one toy ball.
  It can be picked up, dragged and thrown like a treat.
- Once it lies on a surface, every free own pet within sight (800 pt) races for it (same routes
  as treats: walk, leap up, walk off an edge). The first within 16 pt picks it up: the ball is
  carried (drawn at the pet's head, `Item.State.carried(petID:)`) while the pet walks back
  toward the cursor's x on its surface, then drops it there, plays `cheer` and shows
  *joyous*. Others that raced play `sad`. The dropped ball can be thrown again.
- If the carrier is dragged, knocked or falls, it drops the ball where it is.
- The ball is not a treat: it never spoils and doesn't count toward the treat cap; it
  disappears after 5 minutes lying untouched.

## Shaken windows

- The playground tracks each window's horizontal velocity from successive `windowOrigins`.
- A window that reverses direction twice within 0.8 s with moves of at least 30 pt, or moves
  faster than 1,800 pt/s, shakes off the pets standing on it: each is knocked (up 350, sideways
  in the move direction 250) and shows *surprised*.
- Slower moves keep carrying pets (surfing); while their window moves a pet faces the move
  direction.

## Follow-the-leader

- Every 45 s, with probability 0.4, the pets get 10 s to find a moment when an own pet and at least
  two of its friends (level ≥ friend) are free on the same surface; then a **parade** starts: the leader walks to the far end
  of the surface (the end with more room) at 0.8× speed; each friend follows the pet ahead,
  keeping `halfWidths + 6` pt behind it. It lasts until the leader arrives or 12 s pass. Each
  follower gains +1 friendship with the leader. Interrupting any participant ends the parade
  for all.
- Parades don't start during a catch game; pets in a parade are not free for moments.

## When the user is away

- The app reports seconds since the last keyboard/mouse input
  (`CGEventSource.secondsSinceLastEventType`) every tick.
- After 5 minutes idle, free own pets fall asleep (naps last until the user returns).
- When input resumes after ≥ 5 minutes idle, sleeping own pets wake (`wake`), turn toward the
  cursor and greet with `greet`, 1 heart and *happy*.

## Day and night

- The app passes the local hour. Night (22:00–06:00): pets fall asleep after 20 s alone and nap
  2–5 minutes. Morning (06:00–10:00): 1.2× walk speed and +0.1 jump chance. Otherwise unchanged.
- `BrainContext.timeOfDay: TimeOfDay { morning, day, night }` (default `.day`).

## Wandering between monitors

- When deciding where to wander on a screen floor, with probability 0.15, if another screen's
  floor touches this floor's left or right end (within 2 pt), the pet heads there: it walks off
  the end if the neighbour floor is at the same height or lower, or jumps to it if higher and
  reachable. Wild Pokémon don't.

## Reduce Motion

- The app passes `NSWorkspace.accessibilityDisplayShouldReduceMotion`. With it on: no random
  jumps (jumps only for treats, fetch and the active window), walk speed 0.7×, blocked walkers
  turn back instead of hopping, no parades. User-caused motion (throws, knock-overs) is
  unchanged.
- `BrainContext.reduceMotion` (default false); `Playground.reduceMotion`.

## Evolution

- `PetRecord` gains `treatsEaten: Int` (tolerant decoding, default 0); the app increments it on
  `treatEaten`. Ready = `treatsEaten ≥ 15` and the pet has a best friend.
- `EvolutionStore` (actor, PokeToyCore) fetches `pokemon-species/{n}` and its
  `evolution-chain`, caches both JSON files, and answers `nextForms(of dexNumber) -> [Int]`.
  `Evolution.parseChain(json:)` and `Evolution.nextForms(in:after:)` are pure and unit-tested.
- The Pets submenu shows, for a ready pet, **Evolve into <Name>** per next form that exists in
  the catalog (base form path `%04d`). Evolving: downloads the new sprites, keeps the pet's id,
  position and friendships, renames it to the new species, resets `treatsEaten`, plays a white
  flash over the pet (0.8 s) and shows *joyous*. Not-ready pets show "Evolves after N more
  treats" (or "…and a best friend") as a disabled line; final forms show nothing.
- PokeAPI unreachable: the Evolve items don't appear (no error dialogs).

## Architecture

- **PokeToyCore** additions: `Emotion`; `PlaygroundEvent.emotion`, `.stroked`, `.fetched`;
  stroke detection, annoyance, fetch, shake, parade, idle and time-of-day rules in `Playground`
  extensions; `PetBrain` context fields (`timeOfDay`, `reduceMotion`), longer/indefinite naps,
  `PetAnim.shoot`; `ItemKind.toyBall`, `Item.State.carried`; `Evolution` parsing; `EvolutionStore`;
  `SpriteStore.portrait(for:emotion:)`; `PetRecord.treatsEaten`.
- **App** additions: `BubbleWindow` (emotion bubbles), stroke hover feed-in from
  `PetController`, Play Fetch menu items, idle/time/reduce-motion inputs to the tick, evolve menu
  items and flash, `treatsEaten` bookkeeping.

## Testing

Unit tests (Swift Testing, `./scripts/test.sh`) for: emotion mapping and fallbacks; every
emotion trigger; stroke detection (reversals, spacing, timing, cooldown, sleeping pets); annoyed
after five quick clicks; fetch (race, pickup, carry position, return to cursor x, drop on
interruption, ball lifetime); shake detection (reversals, fast move, slow surfing); parades
(start conditions, spacing, end, friendship, interruption); idle napping and the welcome-back
greeting; night/morning behavior; walking to a neighbouring screen; Reduce Motion; evolution
chain parsing and next forms (linear, branching, final); readiness; portrait caching incl.
missing ones; `PetRecord.treatsEaten` decoding.

Manual checks in the app for the bubbles, stroking feel, fetch, shaking windows, parades,
evolve menu and flash.

## Out of scope

Sounds, stats beyond treats eaten, reverting evolutions, mega/form changes.
