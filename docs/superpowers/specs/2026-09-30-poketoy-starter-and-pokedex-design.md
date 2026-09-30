# PokeToy Starter, Pokédex and Reset — Design

Date: 2026-09-30

## Requests

1. Pokédex ordered by Pokémon id, with a minimal description of all downloaded Pokémon.
2. No more adding Pokémon from a list.
3. On first start, choose Pikachu, Charmander, Squirtle or Bulbasaur as the first Pokémon.
4. A game reset that completely resets settings and Pokémon.
5. Play Fetch limited to one minute.

## Decisions

- **Pokédex rows** (`Pokedex.rows`): every species in the Pokédex (caught or owned) plus every species with downloaded
  or bundled sprites (any form collapses to its species), sorted by national dex number. Downloaded-only species show
  as "seen" with a faded portrait; completion still counts caught/owned species only.
- **Description** (`PokemonDescription`, `EvolutionStore.description(of:)`): types, the English genus ("Mouse
  Pokémon") and the newest English flavor text from PokeAPI `pokemon-species`, cleaned of game line breaks; cached on
  disk with the other PokeAPI documents; loaded lazily as rows scroll into view.
- **Adding removed:** the picker window, its menu items and ⌘N are gone. Pets come from the starter, catches and evolution.
- **Starter** (`Starters.all`, `Settings.starterChosen`): fresh settings have no pets and `starterChosen = false`; the
  starter window opens at launch until one is chosen (menus offer "Choose Your First Pokémon…" meanwhile). Settings saved
  before this change decode with `starterChosen = true`, so existing players aren't asked.
- **Reset Game…** (menus; not during a round): confirmation alert, then close results windows, remove every pet and item,
  new `Playground`, `Settings.default`, delete downloaded sprites and portraits (`SpriteStore.clearDownloads`; the bundled
  Pikachu, the catalog and PokeAPI caches stay), then the starter window.
- **Fetch:** `Item.playTime` counts every second since the ball appeared; at `Playground.fetchLength` (60 s) a carrier
  drops it and it fades out (replacing the old 5-minute "untouched" lifetime).

## Later changes

- **Starters bundled:** Pikachu, Charmander, Squirtle and Bulbasaur ship in `Resources/Sprites` (the sheets PokeToy uses)
  and `Resources/Portraits` (every emotion-bubble portrait); `scripts/bundle-starters.py` (now `bundle-sprites.py`) refreshes them. `SpriteStore`
  serves bundled portraits and never downloads portraits for a bundled species.
- **Daily Challenge removed:** with rosters that favour species the player hasn't got yet, a shared fixed roster no
  longer fits. `DailyChallenge`, `Settings.dailyBest` and the menu items are gone (old settings still load); the roster
  size lives in `CatchGame.rosterRegulars` (12).

## The complete collection is bundled (added)

- All 200 species SpriteCollab marks fully complete ship with the app (~26 MB sprites, ~9 MB portraits; only the
  sheets and emotion portraits PokeToy uses), refreshed by `scripts/bundle-sprites.py`, which also writes
  `Resources/Sprites/names.json` and `Resources/CREDITS.md` (source, CC BY-NC 4.0, and each Pokémon's artists by name —
  never their Discord ids).
- Offline on a first start the bundled Pokémon are the catalog (`SpriteStore.catalog` falls back to `names.json`), so
  catch rounds work without a connection.
- The Pokédex's "seen" is now downloads (`SpriteStore.downloadedSpritePaths`, bundled ones excluded) plus wild Pokémon
  met in catch rounds (`Settings.seen`); bundled species don't all show as seen from the start.
- Licensing is stated in the README (Credits & licenses), LICENSE (the MIT license covers the code only), the About
  window (`Credits.html`), `CREDITS.md` in the app, and the app's copyright line.
