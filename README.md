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

- **Click** a pet to make it happy; **drag** it to pick it up and let go (or throw it).
- Pets wander along the Dock, the bottom of the screen and the tops of your windows, and fall asleep when ignored.
- Menu bar paw icon or right-click the Dock icon:
  - **Show / Hide Pets**
  - **Add Pokémon…** — any Pokémon or form on SpriteCollab (downloaded on first use, then cached in `~/Library/Caches/PokeToy`)
  - **Pets** — remove a pet
  - **Cursor** — Off, Follow Cursor, Run from Cursor
  - **Size** — 1×, 2×, 3×
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
