# PokeToy Pomodoro — Design

Date: 2026-09-30
Request: "make rightclick a pokemon setting a pomodoro timer".

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
