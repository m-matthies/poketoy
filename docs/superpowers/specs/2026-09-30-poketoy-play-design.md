# PokeToy Play Features — Design

Date: 2026-09-30
Builds on: `docs/superpowers/specs/2026-09-30-poketoy-design.md`

## Goal

Make PokeToy's pets social and playable: pets interact with each other and form
friendships, the user can feed them treats, and a timed mini game lets the user
throw Poké Balls to catch wild Pokémon.

### What the user asked for / chose

- **Interaction between Pokémon:** all three options —
  random social moments (greet, tag, play-fight, napping together, competing for
  treats), friendship levels between pairs, and physical collisions.
- **Feeding:** treats with no stats — "Feed" drops a treat; pets go for it and eat.
  Treats can also be picked up and thrown.
- **Mini game:** a timed round (option B) — wild Pokémon run across the screen,
  the user throws as many Poké Balls as possible, gets a score, and can keep catches.

### Assumptions

- Item art (apple, Oran Berry, Poké Ball) is drawn in code as pixel art; SpriteCollab
  has no item sprites.
- At most 12 own pets and 3 wild Pokémon on screen at once.

## Architecture

### Simulation moves into PokeToyCore: `Playground`

Today each `PetController` (app target) owns its pet's `PetBrain`, `Body` and
`Animator`. Pets interacting with each other and with items needs one place that
sees everything, so the whole simulation moves into a Core type:

- **`Playground`** owns every simulated actor and runs one tick:
  - `pets: [PetActor]` — own pets and wild Pokémon (`role: .own | .wild`).
  - `items: [Item]` — treats and Poké Balls.
  - `friendships: Friendships`.
  - `game: CatchGame?` — non-nil while a round is running.
  - `tick(dt:world:cursor:cursorMode:)` runs, in order: brain updates → social rules
    → treat rules → game rules → physics for pets and items → collisions →
    animation advance → off-screen recovery. It returns `[PlaygroundEvent]`
    (friendship changed, treat eaten, ball hit, caught, broke free, round ended…) for
    the app to persist or show.
- **`PetActor`**: `id`, `role`, `brain: PetBrain`, `body: Body`, `animator: Animator`,
  `metrics: PetMetrics` (per-`PetAnim` durations and frame sizes, taken from its
  `SpriteSet`), `scale`. Computed: current frame rectangle (for hit tests/overlap).
- The app target only renders: `PetController` keeps the `SpriteSet` and `PetWindow`,
  reads its actor's pose/frame/position from the playground each tick, and forwards
  mouse events (`press`, `click`, `drag…`) to the playground by pet id.
  `ItemWindow` does the same for treats. All existing behavior keeps working and
  existing `PetBrain` tests keep passing.

### PetBrain additions: scripted actions

The playground directs social moments and feeding through one generic mechanism
instead of many new states:

- `PetBrain.perform(_ script: Script, body:) -> Bool` — accepted only when the pet is
  grounded and in `idle`, `walk` or `sleep`, or already running a script of strictly
  lower priority; rejected while dragged, held, falling, jumping, reacting or landing.
  Priorities: treat pursuit 1, social moments 2, catch-game sit/cheer 3.
- `Script`: `anim: PetAnim`, `facing: Direction`, `hearts: Int` (0–2), `moveTo: CGFloat?`,
  `speed`, `end: .animationFinished | .after(seconds) | .arrived`, `priority`.
- New state `.scripted(Script, elapsed)`; when its end condition is met the brain
  returns to `idle`. A click, press or drag always interrupts a script.
- Wild personality: `PetBrain(seed:personality:)` with `.pet` (today's behavior) or
  `.wild` (1.6× speed, never sleeps, always flees the cursor within 220 pt, jumps more
  often, and after its lifetime walks off the nearest screen edge).

### New pet animations

`PetAnim` gains kinds; each falls back like today, ending in `Idle`/`Walk`:

| Kind | Candidates | Loops |
|------|-----------|-------|
| `eat` | Eat, Nod, Idle, Walk | yes |
| `greet` | Nod, Pose, Hop, Idle, Walk | no |
| `attack` | Attack, Swing, Hop, Walk | no |
| `sad` | Cringe, Pain, Hurt, Idle, Walk | no |
| `sit` | Sit, Idle, Walk | yes |
| `cheer` | Hop, Pose, Idle, Walk | no |

The bundled Pikachu gains the extra sheets (Eat, Nod, Attack, Cringe, Sit, Swing,
Pain as available).

### Items

- `Item`: `id`, `kind` (`.apple`, `.oranBerry`, `.pokeBall`), `body: Body` (same
  `Physics` — falls, lands on Dock/window tops, rides windows, bounces off screen
  sides), `state` (`.free`, `.held`, `.flying`, `.wobbling(…)`, `.fading`).
- `ItemArt` (Core): each kind is a small pixel grid (≈12×12) defined as text rows with
  a palette, rendered to a `CGImage` + `AlphaMask` (testable, no asset files).
- Treats are shown in their own floating panels (`ItemWindow`, same level/behavior as
  pet panels) and can be pressed, dragged and thrown with the same mouse handling as
  pets. Poké Balls are drawn by the game overlay.

## Feeding

- **Feed** (menu bar menu, Dock menu, main menu ⌘B) drops a random treat (apple or
  Oran Berry) from the top of the screen under the cursor, at the cursor's x.
  At most 10 treats exist; Feed is disabled at the cap.
- Each tick, for each grounded, free treat, every *eligible* own pet goes for it:
  grounded, in `idle` or `walk` (sleeping pets ignore treats), not in a social moment,
  and either on the same surface or able to jump to the treat's surface.
  Pets walk (or jump) toward the treat with `Script(anim: .walk, moveTo: treat.x, end: .arrived)`.
- The first pet within 16 pt of the treat eats it: the treat is removed, the eater
  plays `eat` for 2.5 s then a ♥ (`greet` pose with 1 heart). Other pets that were
  heading for it play `sad` once. Each pair of pets that were both near the treat
  (within 150 pt) when it was eaten gains +1 friendship.
- A treat being held/dragged is ignored until dropped. A thrown treat lands and is
  then fair game.
- During a catch-game round treats are frozen (not targeted).

## Interaction between Pokémon

### Encounters

- Checked every tick for each pair of own pets. A pair *meets* when both are grounded
  on the same surface, both in `idle` or `walk`, horizontally within
  `60 pt + their half-widths`, and the pair's cooldown has expired.
- On meeting, with probability 0.5 per second of contact, a moment starts; then the pair
  cooldown is 20 s (10 s for best friends). A pet is in at most one moment at a time.
- The moment is chosen by weights depending on the pair's friendship level:

| Level | greet | tag | play-fight |
|-------|-------|-----|-----------|
| stranger | 60 | 15 | 25 |
| friend | 40 | 30 | 30 |
| best friend | 30 | 35 | 35 |

### Moments

- **Greet:** both face each other and play `greet` (strangers: no heart; friends: 1 ♥;
  best friends: 2 ♥).
- **Tag (5 s):** a random chaser runs toward the other (1.4× speed) while the other
  runs away (1.4×), staying on the surface; if the chaser gets within 20 pt the roles
  swap once. Ends with both idle.
- **Play-fight:** the attacker faces the other and plays `attack`; when it finishes,
  the defender plays `sad` and hops back 30 pt (small impulse away). No damage.
- **Nap together:** when an own pet falls asleep, each friend or best friend of it that
  is idle on the same surface walks next to it (within 40 pt) and sleeps too
  (best friends always, friends with probability 0.5).
- **Best-friend following:** when an idle own pet decides where to wander and a best
  friend is on the same surface, it walks to a spot beside that friend half the time.

Each completed moment gives the pair +1 friendship.

### Friendship

- `Friendships`: points per unordered pair of pet ids, persisted in `Settings` as
  `friendships: [String: Int]` keyed `"<uuidA>+<uuidB>"` with the two UUID strings sorted.
- Levels: stranger 0–2, friend 3–9, best friend ≥ 10.
- Removing a pet removes its pairs. Unknown/malformed keys are dropped on load.
- The Pets submenu shows each pet's best friend (if any) as a disabled line
  "Best friend: <name>".

### Collisions

- **Knock-over:** a pet in `fall(thrown: true)` whose frame rectangle overlaps another
  own pet that is not dragged/held gets knocked: the other pet is launched away
  (dx = ±220, dy = 380, direction away from the thrower) and enters `fall(thrown: true)`
  (so it lands with `land`/Hurt); the thrown pet's horizontal velocity is reversed and
  halved. A pair can knock each other at most once per 0.5 s.
- **Bump:** two own pets walking toward each other on the same surface whose frame
  rectangles overlap (and not starting a moment) both turn around: each walks 60 pt
  back the way it came.
- Wild Pokémon and own pets don't collide (they pass each other) — keeps the game
  readable.

## Catch game (timed)

### Flow

1. **Start Catch Game** (menu bar menu, Dock menu, main menu ⌘G). Disabled while a round
   runs; the menus then show **End Catch Game**.
2. **Loading (≤ 10 s):** pick 8 random catalog entries and fetch their sprites in
   parallel. Entries that fail are skipped. If fewer than 3 load (e.g. offline), fill
   the roster with random already-cached or bundled Pokémon (Pikachu is always
   available). A small HUD shows "Getting wild Pokémon…".
3. **Countdown:** "3 · 2 · 1 · Go!" (3 s).
4. **Round (60 s):** wild Pokémon enter from the left/right edge of a random screen onto
   its floor, at most 3 at a time, a new one every 4–7 s. Each stays 12–20 s, then runs
   off the nearest edge. Own pets sit (`sit`) and watch, playing `cheer` on every catch.
5. **End:** when time runs out (or End Catch Game / Esc), pending wobbles resolve
   immediately (using the pre-rolled result), wild Pokémon run away, the HUD shows the
   final score, and a results window opens.

### Throwing

- While a round runs, a transparent full-screen overlay window per screen (above pet
  panels) captures the mouse, so clicks go to the game, not to other apps. Esc ends the
  round.
- Press anywhere → a Poké Ball appears in the "hand" at the cursor; drag and release →
  thrown with the release velocity (same flick sampling as pets, capped at 2200 pt/s).
  Releasing without movement drops it. Unlimited balls; at most 8 in flight.
- Balls fly under gravity, land on surfaces, bounce off screen sides, and disappear
  1.5 s after landing if they hit nothing.

### Hits and catches

- A ball hits a wild Pokémon when the ball's center is inside the wild's current frame
  rectangle shrunk by 20% (sprites have padding). Hits are only checked while the ball
  is flying and the wild is on screen and not already captured.
- On hit: +25 points. The wild disappears into the ball (brief red flash), the ball
  stops, drops, lands and wobbles 1–3 times (0.6 s each). The catch outcome is rolled
  at the moment of the hit with the game's seeded RNG: caught with probability 0.6.
- **Caught:** +100 points, the ball "clicks" (stars), the Pokémon joins the round's
  catch list; own pets cheer.
- **Broke free:** the wild reappears at the ball, the ball vanishes, and the wild flees
  at 2× speed for 2 s.

### HUD and results

- HUD (drawn by the overlay on the main screen, top-center): time left, score, catches.
- Results window: final score, best score (and "New best!"), and the list of caught
  Pokémon with a **Keep** checkbox each (all checked by default), buttons
  **Keep Selected** and **Release All**. Kept Pokémon become own pets (spawned where
  they were caught). Keeping is limited by the 12-pet cap; excess rows are disabled
  with a note.
- Best score is persisted as `Settings.bestCatchScore`.

## Sprite loading changes

- `SpriteStore.spriteDirectory(for:)`: when the network fetch fails and the cached
  directory is incomplete but has `AnimData.xml` plus an `Idle` or `Walk` sheet, return
  it anyway (new animations then fall back). This keeps already-cached pets working
  offline after the new animations raise the required-file set.
- `SpriteStore.cachedSpritePaths() -> [String]`: paths of usable cached or bundled
  sprite directories, used to fill the game roster offline.
- `SpriteStore.spriteDirectory(for:timeout:)` variant used by the game loader (10 s).

## Settings changes

`Settings` gains `friendships: [String: Int]` (default empty) and `bestCatchScore: Int`
(default 0), decoded tolerantly like the existing fields.

## Menus

Menu bar, Dock and main menus gain **Feed** and **Start Catch Game** / **End Catch Game**.
The Pets submenu shows "Best friend: …" lines.

## Error handling

- Game loading with zero usable Pokémon (should not happen given the bundled Pikachu):
  show "Couldn't load wild Pokémon" in the HUD for 3 s and end.
- A wild Pokémon's sprites failing mid-round: it is simply not spawned.
- Settings with malformed friendship keys: those entries are dropped.
- Removing a pet during a social moment ends the moment for its partner (partner returns
  to idle).

## Testing

`./scripts/test.sh` unit tests in PokeToyCore:

- `ItemArt`: every kind renders to a non-empty image and mask of the declared size.
- Items: fall, land, ride windows, bounce, fade after landing (balls).
- Scripted actions: accepted/rejected by state, end conditions, interruption by
  click/drag, return to idle.
- Feeding: nearest eligible pet reaches and eats; late pets play `sad`; sleeping and
  scripted pets ignore treats; held treats ignored; friendship +1 for nearby pairs.
- Encounters: pair detection (same surface, distance, states), cooldowns, moment choice
  by friendship level with a seeded RNG; greet/tag/play-fight/nap-together sequences;
  best-friend following; friendship gains; removal of a pet mid-moment.
- `Friendships`: levels, key normalization, removal, tolerant decoding.
- Collisions: thrown pet knocks another over, rate limit, walking bump turns both
  around, wild/own pets don't collide.
- `CatchGame`: phases and timers, spawn pacing and caps, wild lifetime/exit, hit test,
  seeded catch roll, break-free behavior, scoring, end-of-round resolution, results and
  the 12-pet cap, best score.
- `SpriteStore`: offline fallback to an incomplete cache, `cachedSpritePaths`.
- Bundled Pikachu has the new sheets.

Manual verification in the app: treats drop/drag/throw and get eaten; pets meet and
greet/tag/play-fight/nap; best friend lines in the menu; throwing a pet into another;
the full catch round (loading, countdown, throwing, hits, wobbles, HUD, results, keep).

## Out of scope

Hunger or other stats, sounds, own pets as catch targets, pets interacting with wild
Pokémon beyond cheering, walking between monitors, online leaderboards.

## Additions requested during planning

### Complete sprites only (default)

- SpriteCollab's `sprite_complete` is 0 (none), 1 ("Exists": ~13 required animations,
  usually no Eat/Nod/Sit…) or 2 ("Full": ~34–36 animations). In the current tracker 684
  entries are Full and 2,546 are Exists.
- `CatalogEntry` gains `isComplete` (`sprite_complete == 2`). `Catalog.filter` gains
  `completeOnly: Bool`.
- The picker has a **"Show all Pokémon"** checkbox, off by default, so the list shows only
  complete Pokémon unless ticked. The status line shows the visible count.
- The catch game picks its random wild Pokémon from complete entries only (falling back
  to all entries if none are complete).

### Pets wake up on their own

- A sleeping pet wakes by itself after a random nap of 30–120 s (seeded RNG): it plays
  `wake` (candidates Wake, Idle, Walk; non-looping) and then goes idle.
- Waking resets the "time since interaction", so it stays awake about a minute before it
  can fall asleep again. Clicking, dragging or a cursor mode still wake it immediately as
  before. Wild Pokémon never sleep, so this only affects own pets; pets napping together
  wake independently.

### Pets prefer the active window

- `World` gains `activeWindowID: Int?`: the frontmost on-screen window of the frontmost
  application (nil when PokeToy itself is frontmost or nothing qualifies). `WorldMonitor`
  fills it from `NSWorkspace.frontmostApplication` and the window list (front to back).
- When an own pet decides where to wander and the active window's top is a surface it is
  not on, then with probability 0.6 it heads there instead of wandering randomly:
  - active window top reachable by a jump → jump onto it;
  - active window above but out of reach → walk to the spot under it (then jump next time);
  - active window below (pet is on a higher window) → walk off that window's nearer edge
    toward it and drop down.
- While standing on the active window a pet no longer strolls off its edges on purpose and
  only rarely (3%) jumps to another surface; it keeps wandering along it.
- If the active window moves, pets ride it as before; if another window becomes active,
  pets drift over to it on their next decisions. Wild Pokémon ignore the active window.

### Pets don't walk through each other (replaces the "Bump" rule)

- A pet walking on a surface that is about to touch another pet of the same role (own/own
  or wild/wild) standing ahead of it on that surface is *blocked*. Own pets and wild
  Pokémon still pass through each other.
- Own pets that are both free (not in a game, not scripted, not in a moment) turn the
  bump into play with probability 0.3: a playful chase (tag) or play-fight, 50/50.
- Otherwise the walker picks one of two rules at random (50/50):
  - **hop over:** a small jump landing just past the other pet on the same surface, after
    which it carries on with its walk or script (only if its goal lies beyond the other
    pet and the landing spot is on the surface);
  - **turn back:** it walks 60 pt back the way it came.
- A pet running a script (treat, friend, tag…) always hops when its goal is beyond the
  other pet and the landing fits; otherwise it stops right there (its walk "arrives").
- Tag counts as caught when the chaser is within both half-widths plus 10 pt.

### Feeding: closest treat, one pet per treat (revised)

- Each tick, eligible pets and reachable treats are paired closest-first; each pet chases at
  most one treat and each treat has at most one chaser, so pets go for their nearest treat
  (not the first one dropped) and never race each other for the same one. Pets switch when a
  closer treat appears or someone closer takes theirs.
- When a treat is eaten, other free pets within sight of it that weren't after another treat
  look sad.
- Feed's shortcut is ⌘B (⌘F is the system Find shortcut).

### Random treat drops and big jumps to the active window (revised)

- Feed drops the treat from a random spot along the top of a random screen that has own pets
  on it (any screen when there are none), instead of at the cursor.
- A pet heading for the active window jumps up to it whatever its height, once it is within
  normal horizontal jump reach (it walks underneath first when further away). Other jumps keep
  the 320 pt limit.
- The same applies to treats: a treat lying on the active window can be reached from anywhere
  within sight range (800 pt) with one leap of any height; treats elsewhere keep the normal
  jump limits.

### Treats on any surface (revised)

- Pets go for treats on any surface within sight range (800 pt), not just their own surface or
  a normal jump away: a treat higher up (on any window) is reached with one leap of any
  height; a treat lower down or level (another window, the floor, the next screen's floor) is
  reached by walking off the current surface's edge toward it and continuing from where the
  pet lands. Treats beyond sight range are ignored and eventually spoil.
- **Passing when absolutely needed:** a pet may walk through another for 1.5 s when (a) it is on
  its way somewhere past the other pet but there is no room to hop and land beyond it, or (b) it
  has been blocked three times within 6 s (stuck going back and forth).

### Feeding shortcut and spot (revised again)

- Feed is **⌃⌥B**, registered as a system-wide Carbon hot key (no Accessibility permission; the
  combination is reserved for PokeToy). The treat appears right next to the mouse pointer (24 pt to
  its right) and falls onto whatever is below. Fetch keeps the random spot on a screen with pets.
