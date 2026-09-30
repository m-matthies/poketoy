# PokeToy Pomodoro — Design

Date: 2026-09-30
Request: "make rightclick a pokemon setting a pomodoro timer".

- **Pet menu:** right-click (or ⌃-click) one of your pets: its name, the Pomodoro section, then its usual items
  (best friend, evolution, Release…). The paw menu has the same Pomodoro section (new timers go on the first pet).
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
