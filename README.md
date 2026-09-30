# PokeToy

A macOS desktop pet: Pokémon Mystery Dungeon sprites from
[PMDCollab SpriteCollab](https://sprites.pmdcollab.org/) walk, jump and nap on top of every app.

## Build & run

Requires macOS 14+ and the Swift toolchain (Xcode Command Line Tools are enough).

```bash
./scripts/build-app.sh
open build/PokeToy.app
```

Copy `build/PokeToy.app` to `/Applications` to keep it.

## Using it

- **Click** a pet to make it happy; **drag** it to pick it up and let go (or throw it — thrown pets knock others over).
- Pets wander along the Dock, the bottom of the screen and the tops of your windows, nap when ignored and wake up on their own.
- Pets never walk through each other: they hop over, turn back, or start playing. Pets that meet greet each other, play tag or play-fight. Pairs that play a lot become **friends** and then **best friends**,
  who seek each other out and nap side by side (Pets → *name* shows a pet's best friend).
- **Feed** (⌘B) drops an apple or Oran Berry above the cursor (or above the nearest pet if none can reach it); the nearest pet runs
  over to eat it. Treats can be dragged and thrown too; uneaten ones spoil after 90 seconds.
- **Start Catch Game** (⌘G): a 60-second round where wild Pokémon run across the screen. Press, flick and release to throw
  Poké Balls. Hits score 25, catches 100. Afterwards, pick which catches to keep as pets. Esc or the **End** button ends
  the round early.
- Menu bar paw icon or right-click the Dock icon:
  - **Show / Hide Pets**, **Add Pokémon…**, **Feed**, **Start / End Catch Game**
  - **Pets** — best friend and Remove
  - **Cursor** — Off, Follow Cursor, Run from Cursor
  - **Size** — 1×, 2×, 3×
- **Add Pokémon…** lists Pokémon with complete sprite sets; tick **Show all Pokémon** for every entry on SpriteCollab.
  Sprites download on first use and are cached in `~/Library/Caches/PokeToy`. Up to 12 pets.
- Clicking the Dock icon shows hidden pets, or opens the picker.

## Development

```bash
./scripts/test.sh    # PokeToyCore unit tests (wraps `swift test`)
swift build         # debug build of the app executable
```

`Sources/PokeToyCore` holds all testable logic (sprite parsing, world geometry, physics, behavior,
settings, downloads). `Sources/PokeToy` is the AppKit layer.

## Credits

Sprites and portraits: PMDCollab SpriteCollab contributors, licensed
[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). Pokémon is © Nintendo / Creatures Inc. / GAME FREAK inc.
This is a non-commercial fan project.
