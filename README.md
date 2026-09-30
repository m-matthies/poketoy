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

- On first start you choose your partner: **Pikachu**, **Charmander**, **Squirtle** or **Bulbasaur**. More pets only
  come from the catch game (and evolution) — up to 12.
- **Click** a pet to make it happy; **drag** it to pick it up and let go (or throw it — thrown pets knock others over and
  land dizzy). Click one five times in a row and it gets annoyed, glares at you and storms off.
- **Stroke** a pet by rubbing the cursor back and forth over it: hearts. Sleeping pets sleep on, happily.
- Pets show how they feel in little **bubbles** with their Pokémon portrait (happy, joyous, sad, angry, surprised, hurt, dizzy).
- Pets wander along the Dock, the bottom of the screen, the tops of your windows and over to your other monitors — they like
  the active window best and will jump all the way up to it. Moving a window carries them along; **shaking** it throws
  them off.
- They nap when ignored and wake up on their own, get sleepy at night and lively in the morning, and nap while you're away —
  when you come back they wake up and greet you. With *Reduce motion* turned on in macOS they're calmer.
- Pets never walk through each other: they hop over, turn back, start playing — or squeeze past if there's truly no other
  way. Pets that meet greet each other, play tag or play-fight, and friends sometimes march in a **follow-the-leader**
  line. Pairs that play a lot become **friends** and then **best friends**, who seek each other out and nap side by side.
- **Feed** (⌃⌥B — works from any app, no permissions needed) drops an apple or Oran Berry right next to your mouse
  pointer; it falls onto whatever is below and the nearest pet runs over to eat it. Treats can be dragged and thrown too;
  uneaten ones spoil after 90 seconds.
- **Play Fetch** (⌘J in the app menu) drops a ball: pets race for it and the winner brings it back to below your cursor. A game of
  fetch lasts one minute, then the ball fades away.
- **Evolution:** after 15 treats and with a best friend, a pet can evolve — Pets → *name* → **Evolve into …** (one item
  per possible evolution; evolution data comes from [PokeAPI](https://pokeapi.co)).
- **Start Catch Game** (⌘G): a 60-second round where wild Pokémon run — or fly — across the screen. Press, flick and
  release to throw; a dotted arc shows where it will go. Hits score 25, catches 100; **legendaries** (rare) are worth 3×,
  **shinies** (1 in 64, they sparkle) 2×, and consecutive hits build a **combo** (up to 2× points) that upgrades your ball to
  a **Great Ball** after 3 hits and an **Ultra Ball** after 5 (better catch chances) — a miss resets it. Catching with the
  first ball that hit is worth a +50 bonus. **⌃-click** (or right-click) to throw one of your 3 **Razz Berries**: it calms a
  wild Pokémon (slower, unafraid, easier to catch). Afterwards, pick which catches to keep as pets. Esc or the **End**
  button ends the round early.
- Each round brings at least 10 different wild Pokémon, species you don't have yet first; they walk in from the screen
  edges or pop up anywhere on the floor or on top of windows, and one you've caught doesn't come back that round.
- **Daily Challenge**: the same Pokémon and the same round for everyone today, with its own best score (needs a connection).
- **Pokédex…** lists every species you've caught, kept as a pet (current and former) or seen (downloaded), in national dex
  order, each with a short description from PokeAPI (type, category and a line of Pokédex text), ✦ for shinies, and how
  complete your collection is.
- Menu bar paw icon or right-click the Dock icon:
  - **Show / Hide Pets**, **Feed**, **Play Fetch**, **Start / End Catch Game**, **Daily Challenge**,
    **Pokédex…**
  - **Pets** — best friend, evolution progress / Evolve, Release
  - **Cursor** — Off, Follow Cursor, Run from Cursor
  - **Size** — 1×, 2×, 3×
  - **Reset Game…** — after asking, releases every pet and erases the Pokédex, scores, friendships, settings and downloaded
    Pokémon; then you choose a new starter.
- Sprites and portraits download on first use and are cached in `~/Library/Caches/PokeToy`.
- Clicking the Dock icon shows hidden pets, or opens the Pokédex.

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
