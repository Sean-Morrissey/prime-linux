# What people reach for without thinking

A desktop is judged on the things nobody writes down. Nobody files "I want a
trash can" — they delete a file, go looking for it, and quietly decide the
computer is strange. This file is the list of those reflexes, what Prime does
about each, and what is still missing.

It exists because the gaps cannot be gathered by asking. They are invisible
until someone tries the thing and it is not there. So they get **tested** against
instead: take what a Mac or Windows user does by habit, try it, and write down
what happened.

First pass: 2026-10-13.

| mark | meaning |
|---|---|
| ✅ | works |
| 🟡 | works, but not the way the reflex expects |
| ❌ | absent |

---

## Closed

| Reflex | What happens now |
|---|---|
| ✅ Icons on the desktop | `pcmanfm-qt --desktop` draws a layer-shell surface under the windows and renders `~/Desktop`. |
| ✅ Right-click the desktop | Plain right-click, no modifier. It needed Super before only because there was no desktop surface to hit. |
| ✅ Delete a file and get it back | Trash, in the menu, through gvfs. |
| ✅ Plug in a USB stick | `udiskie` mounts it and says so. `udisks2` was already installed with nothing driving it. |
| ✅ Add a printer | Settings → Printers. Driverless printers on the network are discovered; `prime-printer` does the two steps that need a password. |
| ✅ Drag a window to the screen edge | `prime-snap`, on drag release. Only fires in an edge, so ordinary drags are untouched. |
| ✅ Volume and brightness keys | Already worked — `prime-osd`, bound in `bindings.conf`. It read as missing because the first audit was run against a stale harvest of the config rather than the layer. |
| ✅ Minimise and get the window back | Already worked. A window in `special:minimized` stays a mapped client and the dock keeps listing it; `Super+Backspace` also shows them. |
| ✅ Make everything bigger on a 4K screen | Already worked — `nwg-displays` writes the scale factor (the trailing number on each `monitor =` line). The menu hint never said so, which is why it felt absent. |
| ✅ Lose the title-bar buttons after an update | `prime-hyprpm-watch.timer` (every 10 min) runs the doctor with `--if-version-changed`, which compares Hyprland's commit hash and exits in 0.02 s unless the compositor actually moved; when it moved, stale plugin headers are rebuilt in place. `prime-hyprpm-doctor.service` still covers login, and both disable hyprbars rather than half-load it if a rebuild fails. |
| ✅ Click the whiteboard icon and get nothing | `prime-board.sh` launched with the pre-0.57 `hyprctl dispatch exec -- …` form, which 0.57's Lua parser rejects **silently**, so the script waited out its timeout and then said it could not open. It now launches app-mode on its own profile through `hl.dsp.exec_cmd`, and logs `board opened at 0x…` in `$XDG_RUNTIME_DIR/prime-board.log` — check that log to tell "service down" from "launch failed". |
| ✅ Minimise a window and lose it | `custom/windows` pill in the top bar. `special:minimized` is deliberately excluded from the workspace dots, so the pill is the only entry point: left restores the newest, middle restores all, right opens a rofi list. |
| ✅ The wallpaper not meeting the bar | The bar strip sits over the top 34 px; `prime-emblem-baraligned.png` pads any image by that much, so the image starts exactly where the bar ends. |

Two lessons from that right-hand column: **three of the nine were not missing at
all**, and the audit said otherwise because it was run against the wrong tree.
Check against `layer/`, which is what actually runs.

The other lesson: icons on the desktop and right-click on the desktop looked
like two complaints and were one cause. Worth asking, for anything below, whether
two gaps share a root.

---

## Open

**In flight — the 2026-11-09 sweep.** Five workstreams over the whole desktop:
infrastructure (plugin/header coverage), appearance, accessibility, settings, and
an interface test harness. Plan and measured machine state live in
`docs/audits/SWEEP-2026-11-09.md`; the four audits land beside it. Two items are
already closed because of it — see above.

**Look and feel of what already works.** Search, the dock, Start, the title-bar
buttons, Alt+Tab, Super+Q, the file manager, clipboard history, screenshots,
notifications, the lock screen, Wi-Fi and Bluetooth from the bar — all present,
all worth a pass for how they *feel*. This needs a running session and a person,
not a config read. Per item, decide which is wrong: the look (spacing, colour,
icon quality) or the behaviour (too slow, wrong default, one keypress too many).
The second matters more.

**Not yet tried.** The list below has never been tested, and that is the point of
writing it down — each is a reflex somebody has:

- Drag a file from the file manager onto the desktop, and onto a dock icon
- Rename with a slow double-click, or F2
- Select several files with a rubber-band drag on the desktop
- Plug in a second screen mid-session and expect windows to stay sane
- Plug in headphones and expect sound to follow
- Open a file with a different app once, without changing the default
- Copy a file and watch progress, cancel it halfway
- Search inside a document from the file manager
- Undo a move in the file manager (Ctrl+Z)
- Close the lid and open it again

## How to add to this file

Try the thing on a real session. Write what happened, not what should happen. If
it works, say so — knowing something is already fine is as useful as finding a
gap, and three of the nine above were exactly that.
