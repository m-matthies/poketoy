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
| Shortcuts (global, Carbon hot keys) | Feed, Start/End Catch Game, Show/Hide Pets; each recordable or cleared; must include ⌃ or ⌥ (⌘ combinations belong to apps) | ⌃⌥B, ⌃⌥G, ⌃⌥H |
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

## Menus and the Dock

PokeToy is a menu-bar-only app (`LSUIElement`, `.accessory` activation policy): no Dock icon, so everything is in the
paw menu — including Pets… and Preferences…. Menu items show the configured global shortcuts.

## Testing

Core unit tests: preference defaults, decoding (old/bad data), shortcut display and validity, auto-hide decisions,
pet speed scaling walking only, nap timing (incl. never and night), pet nickname/joined decoding and `name`, frame pacing.
Manual: preferences window, recording shortcuts, auto-hide with a full-screen app and an excluded app, launch at login,
Pets window rename, battery switch, lock screen.

## Review fixes

- Shortcuts need ⌃ or ⌥; while recording, ⌘ combinations (⌘W, ⌘Q…) cancel and do their usual thing, only keys typed
  into the Preferences window are recorded, and recording stops when the window loses focus. Shortcuts stay off while
  recording even if other preferences change.
- Show / Hide acts on what's visible: showing pets while auto-hide hides them keeps them visible until another app
  comes to the front (`AutoHideState`).
- Full-screen windows below a camera notch count as full screen.
- Menus: About and Release… (with confirmation) in the paw menu; shortcuts on Space, arrows and F-keys show in menus;
  Undo/Redo work in text fields. Feeding with the pointer on a screen pets don't use drops the treat on one they do.
- Battery saver also pauses during fast user switching. Naps "never" still lets pets doze while the user is away.

## Screen sharing (added)

- `Preferences.hideFromScreenSharing` (on by default), "Keep pets out of screen sharing and screenshots":
  - every overlay window (pets, bubbles, countdowns, treats, task editor, Poké Ball animations, catch-game overlays) is
    marked not capturable (`sharingType = .none`, `CapturePolicy`), so screen sharing and screenshots leave it out;
  - as a backup (capture exclusion may not be honoured by every capture method), pets auto-hide while a listed app
    (Zoom, Teams, Webex, …) shows a floating window above the normal layer that isn't a menu bar icon — its sharing
    toolbar (`AutoHide.isSharingScreen`). Showing pets anyway works as for the other auto-hide rules.
