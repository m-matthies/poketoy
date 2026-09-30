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
