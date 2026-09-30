# PokeToy App Polish — Design (sub-project C)

Date: 2026-09-30
Scope agreed at the sub-project split: preferences, auto-hide, launch at login, a Pets window, battery saver.
(Distribution features — notarization, updates — stay out of scope.)

## Preferences (`Settings.preferences`, tolerant decoding; reset by Reset Game)

| Setting | Values | Default |
|---|---|---|
| Pet speed | 0.5…2.0 (× walking speed of own pets; jumps unchanged) | 1.0 |
| Naps | often (30 s) · normal (60 s) · rarely (3 min) · never — time left alone before napping; a third of it at night | normal |
| Screens | all screens · main screen only | all |
| Shortcuts (global, Carbon hot keys) | Feed, Start/End Catch Game, Show/Hide Pets; each recordable or cleared; must include ⌘, ⌃ or ⌥ | ⌃⌥B, ⌃⌥G, ⌃⌥H |
| Hide in full screen | on/off | on |
| Hide while in front | list of apps (bundle IDs) | Zoom, Microsoft Teams (both), Webex, FaceTime, Keynote |
| Battery saver | on/off | on |

Launch at login is not stored: `SMAppService.mainApp` is the source of truth (the window shows when macOS wants approval).

## Auto-hide

`AutoHide.shouldHide(frontmost:isFullScreen:preferences:)`: hide when the frontmost app is in the list, or is full screen
and hiding in full screen is on. PokeToy itself never triggers it. Checked with the 5 Hz world update (full screen =
a normal-layer window of the frontmost app covering a whole screen). Auto-hide is separate from the user's Show/Hide:
pets show again when the condition ends, and nothing is hidden during a catch round.

## Pets window

One row per pet: portrait, editable name (`PetRecord.nickname`, kept through evolution; `PetRecord.name` = nickname or
species name), species (✦ shiny), together since (`PetRecord.joined`, new; unknown for older pets), treats eaten,
best friend, evolution progress, and a Release button. Refreshes when pets change.

## Battery saver

On battery power the tick runs at 30 fps instead of 60 (`FramePacing.interval`); while the screen is locked or the
displays sleep, ticking pauses (the first tick after resuming uses a normal frame time).

## Menus

App menu: Preferences… (⌘,), Pets… Status/Dock menu: Pets…, Preferences…. Menu shortcuts show the configured keys.

## Testing

Core unit tests: preference defaults, decoding (old/bad data), shortcut display and validity, auto-hide decisions,
pet speed scaling walking only, nap timing (incl. never and night), pet nickname/joined decoding and `name`, frame pacing.
Manual: preferences window, recording shortcuts, auto-hide with a full-screen app and an excluded app, launch at login,
Pets window rename, battery switch, lock screen.
