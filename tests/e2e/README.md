# Prime Linux interface tests

Three layers, cheapest first. Run them all with:

```bash
bash ~/Projects/prime-linux/tests/e2e/run-all.sh
```

`--fast` skips the journey layer (no windows are opened). `--layer journeys` runs
one layer. Every layer prints a PASS/FAIL table, writes its own log and
screenshots under `results/<timestamp>/`, and exits non-zero on failure.

Nothing here edits the desktop, restarts a bar or service, or needs sudo.
Layer 3 opens its own windows and closes them again, including when it fails.

## Why three layers

The first version of this suite only checked that the desktop was *assembled*:
services running, JSON parsable, menus resolving. It passed while a real person
could not open the whiteboard, because a script was calling a `hyprctl` verb that
Hyprland 0.57 silently ignores. Structure is not use.

| layer | question it answers | how it can fail |
|---|---|---|
| **structural** | is the desktop assembled correctly? | a service dead, a config error, a bar module pointing at a script that does not exist, the doctor reporting "needs you" |
| **contracts** | are the promises still true? | a notification lost its click action, a contrast token dropped under 4.5:1, text size stopped reaching GTK3/rofi, the shipped tree went dirty, a hostname leaked into a shipped JSON |
| **journeys** | can a person actually do the thing? | the typing box takes 3 s, the menu opens but nothing is typed into it, the board never appears, a minimised window cannot be restored |

A failure in layer 1 makes layer 3 meaningless, so `run-all.sh` does not stop —
it runs everything and reports per layer, because a journey failure with a green
structure is exactly the bug class this suite exists for.

## Latency budgets

Journeys assert time, not just presence. These are the budgets and the measured
numbers they were set from (2026-11-09, idle machine, 1920x1080):

| step | budget | measured | why this number |
|---|---|---|---|
| typing box appears after the pill's on-click | **400 ms** | 203 ms | GTK3 start-up dominates; above 400 ms it reads as "nothing happened" and people click twice |
| typing box disappears on Escape | **300 ms** | — | must feel like dismissal, not a close animation |
| Prime menu open | **2000 ms** | ~700–1300 cold, 5–160 warm | the default menu precomputes the Apps section's app count synchronously (enumerates ~99 desktop files + resolves each icon); rofi itself paints in a few ms once that is cached |
| menu closes on Escape | **300 ms** | — | |
| board window appears (cold Chrome, own profile) | **6000 ms** | ~440–1000 ms warm | a cold Chrome start is the worst realistic case; the budget is for the cold path |
| minimise → pill reflects it | **1500 ms** | — | the pill polls at 1 s, so anything under 1.5 s is one poll |
| restore → window on a workspace | **1500 ms** | — | same poll |

Budgets live in the journey script next to the assertion that uses them, so
changing one is a one-line diff and the reason sits beside it.

## Contract tests (layer 2)

These encode incidents that actually happened, so they cannot silently return:

- **notifications carry actions** — `prime-notify` must send a non-empty actions
  array; a bare `notify-send` must not (that difference is the "clicking a
  notification does nothing" bug).
- **contrast budget** — every text token that paints the bar is composited over
  `#0c0c10` and its WCAG ratio computed from the real CSS, including the
  `@define-color` overrides in `~/.config/prime/addons.d/my-desktop/waybar.css`.
  `fg_faint` at 0.32 was 2.59:1 and shipped for months; it is 4.70:1 now and this
  test is why it stays there.
- **text scale propagates** — the one Text-size control must reach fonts.rasi,
  kitty, dock.css, gsettings *and* `gtk-3.0/settings.ini`, and the three rofi
  themes must resolve `var(prime-font-body)` rather than hardcoding a size.
- **shipped tree clean** — `~/.local/share/prime-linux` is a git checkout that
  `prime-update` overwrites; a dirty tree means local fixes vanish at the next
  update. User changes belong in `~/.config/prime/`.
- **no portability leaks** — shipped JSON must not contain `/home/sean/`,
  `card1`, or this machine's GPU model.
- **plugin version gate** — the stamped Hyprland commit must match the running
  one and `prime-hyprpm-watch.timer` must be active, or a mid-session Hyprland
  bump will take the titlebar buttons away until the next login.

## Adding a journey

One function, one budget, one cleanup trap entry. Keep it to things a person
does, assert what they would see, and never assert on internals you would not
look at yourself — a test that only reads internals is how the first harness
passed while the board button was broken.
