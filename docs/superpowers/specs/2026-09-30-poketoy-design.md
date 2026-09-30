# PokeToy — Design

Date: 2026-09-30

## Goal

A native macOS desktop pet. One or more Pokémon Mystery Dungeon sprites from
[PMDCollab SpriteCollab](https://sprites.pmdcollab.org/) wander across the screen,
float above every application (including full-screen apps, on every Space), and
react to the user. For personal use; not distributed via the App Store.

### What the user asked for

- Native Apple (macOS) app, sprites from sprites.pmdcollab.org.
- Toy travels across the screen and stays on top of every application.
- Interactive: click/pet reactions, drag-and-drop with gravity, cursor
  follow/flee, walking on window tops and the Dock, a Pokémon picker with
  multiple simultaneous pets.
- Show/hide the pets from the menu bar.
- A Dock icon.

### Assumptions

- Personal use; no sandboxing, notarization or App Store constraints.
- Only Command Line Tools are installed (no Xcode), so the app is built with
  Swift Package Manager and bundled into `PokeToy.app` by a script.
- Minimum macOS 14.

## Architecture

Swift package, AppKit, one executable target (`PokeToy`) plus a library target
(`PokeToyCore`) holding all logic that does not need a live screen, so it can be
unit-tested with `swift test`.

The app runs with a regular activation policy (Dock icon) **and** an
`NSStatusItem` in the menu bar. Both surfaces expose the same actions.

Each pet is rendered in its own borderless, transparent, non-activating
`NSPanel` sized to the current sprite frame. The panel moves as the pet moves.
Clicks outside the sprite's panel fall through to underlying apps naturally;
fully transparent pixels inside the panel are also made click-through by
hit-testing against frame alpha.

Panel configuration: `level = .statusBar` (above normal and floating windows),
`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
.ignoresCycle]`, `hasShadow = false`, `isOpaque = false`,
`backgroundColor = .clear`, `hidesOnDeactivate = false`.

A single 60 Hz tick (`CADisplayLink` from `NSScreen`, falling back to `Timer`)
drives every pet: update brain → update physics → advance animation → move
panel and redraw.

## Components

### PokeToyCore (library, unit-tested)

- **`AnimData`** — parses `AnimData.xml`: per animation name → frame width,
  frame height, list of durations (in 1/60 s ticks), optional `CopyOf`.
  Resolves `CopyOf` chains. Provides `resolve(_ name:, fallbacks:)` that returns
  the first animation present, e.g. `Sleep → Idle`, `Hop → Pose → Idle`.
- **`Direction`** — the 8 PMD sheet rows in order: Down, DownRight, Right,
  UpRight, Up, UpLeft, Left, DownLeft. Helper to pick a direction from a
  velocity vector.
- **`SpriteSheet`** — given a `CGImage` sheet and an animation's frame size,
  slices it into `frames[direction][index]`. Sheets with a single row (some
  animations) reuse row 0 for every direction.
- **`CatalogEntry` / `CatalogParser`** — parses SpriteCollab `tracker.json`
  into a flat list of `(id: "0025" or "0025/0001", name, formName)` for
  entries whose sprites exist (`sprite_complete > 0` / non-empty
  `sprite_files`). Subgroups (forms, shiny) are flattened with a readable
  display name.
- **`Surface` / `World`** — a surface is a horizontal segment
  `(minX, maxX, y)` in a single global coordinate space (AppKit, bottom-left
  origin). `World` is built from: each screen's visible-frame bottom (above the
  Dock), each screen's bottom edge, and the top edges of on-screen windows
  (from `CGWindowListCopyWindowInfo`, layer 0 only, excluding our own
  windows, converted from CG top-left to AppKit coordinates, clipped by
  windows in front of them). Queries: `surfaceBelow(point)`,
  `surfaceUnder(point, tolerance)`, `reachableSurfaces(from:, maxJump:)`.
- **`Physics`** — pure step function: position, velocity, grounded surface,
  gravity (~2000 px/s²), terminal velocity. Walking off a surface's end
  ungrounds the pet; landing snaps it to the surface top.
- **`PetBrain`** — state machine with states `idle`, `walk(target)`, `sleep`,
  `jump`, `fall`, `dragged`, `react`, `landing`. Inputs: elapsed time, world,
  cursor position, cursor mode, events (click, drag start/end). Output: desired
  animation name, facing direction, horizontal velocity, jump impulse. Uses an
  injectable random source so tests are deterministic.
  - Wander: idle 2–6 s → walk to a random x on the current surface (or hop to
    a reachable window top ~25 % of the time) → after ~60 s without
    interaction, sleep until clicked or dragged.
  - Follow mode: walks toward the cursor's x; hops to a higher reachable surface
    when the cursor is above it.
  - Flee mode: when the cursor is within 150 px, runs the opposite way (and
    jumps off edges if needed).
  - Click: `react` (plays `Hop` → `Pose` → `Idle`, with a ♥ emote) for one
    animation cycle.
  - Drag: `dragged` (plays `Hurt` if present, else `Idle`, facing Down) while
    held; on release → `fall`; on landing → brief `landing` (`Hurt` once) →
    `idle`.
- **`Settings`** — codable model persisted in `UserDefaults`: active pets
  (list of catalog IDs + saved positions), hidden flag, cursor mode
  (off / follow / flee), scale (1× / 2× / 3×).

### PokeToy (executable, AppKit)

- **`SpriteStore`** — downloads `tracker.json`, `AnimData.xml` and required
  `*-Anim.png` files from
  `https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/…` and
  caches them in `~/Library/Caches/PokeToy/`. Bundled fallback: Pikachu
  (`0025`) sprite files are shipped in the app bundle's resources.
- **`PetController`** — owns one pet: its brain, physics body, loaded sprite
  set, and `PetWindow`.
- **`PetWindow` / `PetView`** — the `NSPanel` + view that draws the current
  frame with nearest-neighbor scaling, handles mouse down/drag/up (drag moves
  the panel; a press without movement counts as a click), and does alpha
  hit-testing for click-through.
- **`WorldMonitor`** — refreshes `World` from the window list ~2 Hz and on
  screen-configuration changes.
- **`MenuBarController`** — status item menu:
  - Show Pets / Hide Pets
  - Add Pokémon…
  - Active pets submenu (each with Remove)
  - Cursor: Off / Follow / Flee
  - Size: 1× / 2× / 3×
  - Quit PokeToy
- **Dock** — app icon generated from the Pikachu portrait
  (`portrait/0025/Normal.png`) at build time into `AppIcon.icns`. The Dock menu
  (`applicationDockMenu`) mirrors Show/Hide, Add Pokémon…, and Cursor mode.
  Clicking the Dock icon (`applicationShouldHandleReopen`) shows pets if hidden,
  otherwise opens the picker.
- **`PickerWindow`** — a regular window with a search field and a table of
  catalog entries; choosing one downloads the sprite (progress indicator) and
  adds a pet at the top of the current screen, where it falls into place.

## Data flow

1. Launch → load `Settings` → load cached catalog (refresh in background) →
   for each saved pet, load sprites (cache → bundle → network) → create
   `PetController`s.
2. Tick → `WorldMonitor.world` + cursor position → each `PetBrain.update` →
   `Physics.step` → animation frame advance → panel frame update.
3. Menu/Dock actions mutate `Settings` and the set of `PetController`s;
   settings are saved on change.

## Error handling

- Offline: cached or bundled sprites are used; the picker shows
  "Couldn't reach SpriteCollab" and a retry button.
- Malformed/missing sprite data: that pet is skipped and the error logged via
  `os.Logger`; the picker shows the failure for that entry.
- Window list unavailable: `World` contains only screen floors and Dock tops.
- A pet ending up off every screen (e.g. monitor unplugged) is respawned at the
  top of the main screen.

## Testing

- `swift test` (Swift Testing) for PokeToyCore: AnimData parsing incl. `CopyOf`
  and fallbacks, sheet slicing, catalog parsing (fixture trimmed from real
  `tracker.json`), `World` surface queries incl. occlusion and coordinate
  conversion, `Physics` steps (fall, land, walk off edge), `PetBrain`
  transitions with a seeded RNG.
- Manual verification by running the built app: pet floats over apps and a
  full-screen app, click-through outside the sprite, click reaction, drag and
  drop with fall, walking on window tops, follow/flee, multiple pets, hide/show
  from menu bar and Dock, Dock icon present.

## Out of scope (for now)

- Launch at login, sounds, pets interacting with each other, per-pet cursor
  modes, portraits/speech bubbles beyond the ♥ emote.
