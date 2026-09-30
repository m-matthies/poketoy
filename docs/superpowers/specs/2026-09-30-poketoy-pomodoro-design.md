# PokeToy Pomodoro — Design

Date: 2026-09-30
Request: "make rightclick a pokemon setting a pomodoro timer".

> The design grew in steps, recorded in the sections below in order; where they differ, later sections win. Today:
> every pet can carry its own timer (no single timer, no "Show Timer on This Pet"), work is 💼 (not 🍅), a released
> pet takes its timer with it, and Release isn't in the right-click menu.

- **Pet menu:** right-click (or ⌃-click) one of your pets: its name, the Pomodoro section, then best friend and
  evolution. Release stays out of it (paw menu and Pets window only), away from a quick right-click. The paw menu has the same Pomodoro section (new timers go on the first pet).
- **Timer** (`Pomodoro`, core, persisted in `Settings.pomodoro`): Focus 25 min, Short Break 5 min, Long Break 15 min.
  A finished focus starts its break at once (long after every 4th focus, then the count starts over); a finished break
  waits for the next focus. Pause/Resume, Skip (quietly ends the phase), Stop, and "Show Timer on This Pet". Wall-clock
  based: it keeps running while the app is paused or quit; a phase that ended meanwhile finishes on the next check and
  its break starts then.
- **Pet:** shows a countdown pill above its head (🍅 focus, ☕️ break, ⏸ paused, "🍅 Ready?" when waiting); the
  emotion bubble sits above the pill. Focus done: the pet cheers (joyous); break done: it hops (surprised). Releasing
  the timer's pet moves the timer to another pet, or stops it when none are left.
- **Notifications:** a notification (permission asked when the first timer starts) plus the "Glass" sound, shown even
  while PokeToy is in front.
- **Tests:** durations, countdown, pause/resume, focus→break, every 4th long break and reset, waiting after a break,
  waking long after the end, skipping, persistence and bad data, pets celebrating and nudging.

## Options and attention (added)

- `PomodoroOptions` in `Preferences.pomodoro` (tolerant decoding, clamped): focus 1–120 min (25), short and long break
  1–60 min (5, 15), long break after 2–10 focuses (4), start breaks automatically (on), start the next focus
  automatically (off), pets seek attention (on), notifications (on), sound (on). Changes apply from the next phase.
  When a phase doesn't start automatically the timer waits with `phase` set to the one to start next.
- **Attention:** when a phase ends, the timer's pet and all your other visible pets wake up, follow the pointer (the
  follow cursor mode, jumping up surfaces as needed) and, once there, hop and call out (surprised or joyous) every
  1.6 s. It ends when any of them is clicked or dragged, a pet menu is opened, the timer is started, paused, resumed,
  skipped or stopped, or after 60 s. Seekers don't fall asleep for "user away".
- Preferences window: sections General / Shortcuts & Hiding / Pomodoro (a segmented control; the window fits the
  section shown).

## Evolution needs focus sessions (added)

- A pet evolves after 15 treats, `PomodoroOptions.focusSessionsToEvolve` finished focus sessions (default 50, 1–1000,
  set in Preferences → Pomodoro) and a best friend. `PetRecord.focusSessions` counts focuses that ran to the end while
  that pet carried the timer (skipped ones don't count); it starts over after evolving, like the treat count.

## Sessions, a timer per pet, tasks (added)

- **Sessions** (`SessionPreset`, `PomodoroOptions.sessions`): the built-ins Focus (work), Short Break and Long Break
  (relax) drive the automatic cycle — renamable and resizable, not removable, kind fixed; the player adds their own
  named work or relax sessions (1–180 min). A work session finishing counts as a focus (long-break rhythm, evolution),
  a relax one as a break. The timer shows the session's name (`Pomodoro.label`). Older preferences (only lengths) load
  into the built-ins; bad entries are fixed or dropped.
- **A timer per pet** (`Settings.timers`, one per pet; a saved single timer carries over): each pet's right-click menu
  and its entry in the paw menu control its own timer; the paw menu's Pets entries show each countdown. A released pet
  takes its timer with it. When a session ends only that pet comes to get attention; opening its menu or using its
  timer stops it.
- **Tasks** (`Pomodoro.task`): "Name a Task…" opens a small field right above the pet (Return saves, Esc cancels,
  clicking elsewhere saves; it doesn't take focus from the user's app). The task shows beside the countdown and in the
  notifications, stays for the next sessions until renamed or cleared, and naming one on a pet without a timer gives it
  a timer waiting for its first focus.

## Poké Balls (added)

- `PetRecord.inBall`: a pet resting in its Poké Ball is kept but not on screen (not added to the playground at launch;
  `Playground.stowPet` removes it without forgetting its friendships). Its evolution progress and timer carry on (a
  timer ending still notifies; there's no pet to react). Toggles: "Return to Poké Ball" in the pet's right-click menu,
  "Return to Poké Ball / Let Out of Poké Ball" in its paw-menu entry (◓ marks pets in their ball; the Pets header says
  how many are out, with Return All / Let All Out), and a button per row in the Pets window. Letting a pet out brings it
  back where it was, with a flash and a happy bubble. Pets in their ball still count towards the 12-pet limit.

## Icons (changed)

- Work is 💼 (was 🍅, which read as an apple), relax ☕️, paused ⏸ — defined once as `SessionPreset.Kind.icon` /
  `Pomodoro.Phase.icon`.

## Adjustable task time (added)

- The editor above the pet has the task's name and a minutes field with a stepper (1–180). With no timer, or a focus
  waiting to start, Return starts a work session of that length on the task (`Pomodoro.startFocus(minutes:)`, named
  like the focus). While a session runs or is paused the field shows the minutes left, and changing it sets the time
  left (`setRemaining`). With a break up next only the name is shown.
- Menus: "Add 5 Minutes" and "Take Off 5 Minutes" (when more than 6 minutes are left) for running or paused sessions
  (`Pomodoro.adjust(by:)`; at least a minute always stays). The editor item reads "Start a Task…", "Edit Task & Time
  Left…" or "Name a Task…" depending on the timer.

## Poké Ball animations (added)

- `BallAnimation` (core, a pure timeline, tested): **recall** (1.1 s) — a ball pops up beside the pet (on the side with
  room), the pet turns red and shrinks into it, the ball wobbles twice and fades; **release** (1.0 s) — a ball drops
  in and bounces at the pet's spot, bursts open in a white flash, the pet grows out glowing white, the ball fades.
- `BallAnimationWindow` draws it over the spot with the pet's current sprite (recall) or its idle sprite (release) and
  the Poké Ball pixel art. The pet leaves the playground at once when recalled, and joins it when the release
  animation ends. Return All / Let All Out stagger the pets by 0.18 s. No animation while pets are hidden.

## While PokeToy is closed (added)

- Timers keep counting while the app isn't running (the default, `PomodoroOptions.keepRunningWhileClosed`); a phase
  that ended meanwhile finishes when the app starts again. Optionally ("Pause timers while PokeToy is closed") they
  pause instead: `Settings.lastAlive` is noted on quit and every 30 s while a timer exists (covering crashes and power
  loss), and at launch `Pomodoro.resumed` gives running timers the time they had left then.
- A task still being typed in the editor above a pet is saved when PokeToy quits.

## Holding still (added)

- `Playground.hold(_:)` / `letGo(_:)`: a held pet stands still, facing the way it faced, under a script of priority 9
  (above every behaviour: treats, fetch, social moments, cursor following, attention seeking, the catch game). A
  sleeping pet sleeps on; a pet in mid-air holds once it lands.
- A pet is held from the right-click until its menu closes, and while its task editor is open (from either menu),
  so it can't wander off while its timer or task is being set.

## Review fixes (added)

- The task editor remembers what it was opened on (`TaskEditSnapshot`); saving (`TaskEdit.apply`) keeps the name
  always, but changes the time only if the minutes were changed and the timer is still in the same phase; only
  Return starts a focus — clicking elsewhere, quitting or pets auto-hiding just keep the name (and a blank editor
  with no timer makes none). The arrows reach past 180 when a timer already has more left; a valid typed number wins.
- Screen-sharing detection only looks at Zoom, Teams and Webex (`AutoHide.sharingApps`, not the hide list): a
  see-through border window covering a screen, or a short, wide floating toolbar — not dialogs, pop-up menus, help
  tags, invisible windows, menu bar icons (per-screen menu bar height, taller with a notch) or mini meeting windows.
  App lookups are cached between refreshes and skipped when the option is off.
- While PokeToy can't tick (screen locked with battery saver, or quit with timers running) the session ends are
  scheduled with macOS; when it ticks again they're cancelled, and an end macOS already showed isn't posted twice.
- Notifications for pets in their Poké Ball point to the paw menu; waiting timers show the current session name;
  pets don't come looking for you during a catch round.
- Letting a pet out that can't be shown (offline, not downloaded) puts it back in its ball; a reset or evolution
  during the release animation is respected.
- Releasing a pet from its Poké Ball forgets its friendships; timers of pets that no longer exist are dropped on load.
- Catch results: Return does nothing while nothing is ticked; "Release All" asks first when a shiny was caught.
- Preferences sessions: a name being typed is committed before the list changes and found by the session's id.
- Notifications are skipped for a bare debug executable (no app bundle).
