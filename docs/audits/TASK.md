# TASK — the whole list

Work in `~/Projects/prime-linux`. **Do not push or merge** — Sean approves merges.
**Never run UI tests on his live desktop** — he works on this machine. Use the VM
(`~/VMs/prime`) or wait until he says the screen is free.

This replaces the earlier, narrower version of this file. It is everything Sean
asked for, grouped by workstream, with the honest current state.

---

## A. Ship what already works on this machine — nothing else counts until a clean install has it

A pristine VM install of the layer passes only **2 of 7** contracts. The fixes
live in `~/.config` and `~/.local/bin` on this machine, not in the product.

| fix | host source | repo target |
|---|---|---|
| notifications with Open/Dismiss actions | `~/.local/bin/prime-notify` | `layer/bin/prime-notify` + update every caller |
| contrast, hover transitions, visible focus ring | `~/.config/prime/addons.d/my-desktop/waybar.css` | `layer/default/waybar/style.css` (fg_faint 0.50, dots 0.50, `transition` on `window#waybar *`, `:focus` ring) |
| GTK3 follows Text size | `~/.local/bin/prime-text-sync` + `prime-text-sync.{service,path}` | `layer/bin/` + `layer/systemd/` |
| plugin rebuild on a Hyprland bump | `prime-hyprpm-doctor.sh --if-version-changed` + `prime-hyprpm-watch.{service,timer}` | `layer/bin/` + `layer/systemd/` |
| dock focus ring + surface-2 grey | `~/.config/prime/theme/dock.css` | `layer/bin/prime-theme` heredoc that generates it |

`install.sh` must enable `prime-text-sync.path` and `prime-hyprpm-watch.timer`, and
put `prime-notify` on `PATH`.

**Acceptance:** `bash ~/VMs/prime/provision-vm.sh` then
`bash ~/VMs/prime/run-suite.sh --fast` → **contracts 7/7 inside the VM**; host
`tests/e2e/run-all.sh --fast` still green; layer tree clean.

---

## B. The whole desktop — "overhaul, luxury, professional, no breaks"

Read `~/Documents/sweep/appearance.md` (measured values, file:line) and finish it:

1. Three surface greys only (`#0a0a0e` / `#0c0c10` / `#14141a`), one accent
   `#34d399`, one white, one secondary grey.
2. Collapse the eight radii to a scale (6/10/14/18); put every surface on an 8 px
   spacing grid; consistent titlebar button rhythm and grey.
3. Menus: real section separators, one soft shadow, stable width so the bar does
   not reflow when a pill changes state.
4. Dock: hover magnification + one soft shadow; it runs under
   `prime-dock.service` — keep it that way.
5. Whiteboard (`~/College/whiteboard/`): finish accent unification, add keyboard
   focus support (the accessibility audit lists it as mouse-only).

**Acceptance:** before/after screenshot per surface; `run-all.sh --fast` green.

---

## C. Accessibility to macOS standard

Read `~/Documents/sweep/accessibility.md`. Then:

1. **Screen reader**: `orca`, `espeak-ng`, `speech-dispatcher`; bind
   `Super+Alt+Escape` to toggle it; verify the Settings window is spoken.
   Installing packages needs Sean's approval — ask, do not assume.
2. **Reduce motion**: switch exists but leaves blur on and has no key.
   Bind `Super+Alt+R`; also set swaync `transition-time: 0`.
3. **Keyboard reachability**: bind the `Menu` key to the desktop context menu;
   verify the bar `:focus` ring; list any surface still mouse-only.
4. **Text scale**: prove one control moves GTK3/GTK4/kitty/dock/lock/titlebars/
   rofi; extend the contract to cover all of them.
5. Cursor 32 px and `QT_ACCESSIBILITY=1` must ship in the layer (they are only in
   his user config today).

**Acceptance:** `text-scale-propagates` and `keyboard-reachability` pass in the
VM; screenshot of the bar with a visible focus ring.

---

## D. Hardware and performance in one place

`~/Projects/prime-control/` exists (GTK3; Overview, Performance, Display, Gaming,
Storage) and renders. It is **not integrated**:

1. Review against the ask: every value live, every control works or says why not.
2. Install LACT (`lactd`) so GPU clocks/power/fan are controllable rather than
   read-only; wire Prime Control to it (needs approval to install).
3. Add a menu row and a keybind in the layer.
4. One place for: display mode/refresh/scale (delegate to `nwg-displays`), CPU
   governor/EPP, GPU power profile, RAM/swap, storage health, and a
   quiet / balanced / gaming performance switch.

**Acceptance:** each tab screenshotted with live values; switching a profile shows
in `cpupower`/`powerprofilesctl`; the menu row opens it.

---

## E. Gaming

`~/Documents/sweep/gaming/` has the audit.

1. **Dark and Darker (2016590)** still fails with `[AppId: 0] Client API
   initialized 0`. The existing Proton log predates the failure — capture a fresh
   `PROTON_LOG=1` run, find the real cause, fix it. This is the game he wants.
2. Apply per-appid launch options from `launch-options.md` (never a global Proton
   default), with MangoHud/gamemode/gamescope choices.
3. Ship `prime-gaming-check` in the layer with a menu row.

**Acceptance:** Dark and Darker reaches its menu; checker prints a clean report;
no global Proton default changed.

---

## F. Switching from Windows or macOS

Nothing exists for this, and he asked for it explicitly.

1. A first-run "Coming from Windows/macOS?" page: import browser bookmarks, map
   shortcuts (Ctrl vs Cmd), per-task app equivalents (Explorer → file manager,
   Spotlight → Prime Spotlight, Task Manager → Prime Control), import
   `~/Documents` / `~/Pictures` from a mounted drive.
2. A keybind parity table, printable and viewable in Settings.

**Acceptance:** page exists, opens from the menu, every action works or is
clearly labelled unavailable.

---

## G. Virtual machines

1. Formalise `~/VMs/prime/` into `tests/vm/` in the repo: `start-vm.sh`,
   `provision-vm.sh`, `run-suite.sh`, README.
2. **Blocker**: Hyprland will not start in the guest — DRM master refused,
   virtio-gpu GBM dumb buffers fail, nested-on-sway lacks protocols. Try in
   order: virt-manager + virgl (needs approval), QEMU `egl-headless,gl=on` with an
   emulated connector, headless wlroots harness. Until then journeys stay
   host-only.
3. The Windows GPU-passthrough plan (`~/Documents/windows-vm-plan.md`) stays
   parked — never touch the Windows partition.

**Acceptance:** journeys run in the VM, or a written explanation of the exact
display path required.

---

## H. Reverse engineering ("rea")

Add a menu section for the toolchain from the `reverse-engineer-anything` skill:
ghidra, rizin/radare2, binwalk, strace, ltrace, wireshark — each row launches it
or says what to install. For his own binaries and hardware only.

**Acceptance:** section exists; every row launches or names the package.

---

## I. Tests and CI

`tests/e2e/` has structural (21), contracts (7), journeys (7 with latency
budgets). Add:

1. `make check` (or `prime-doctor --tests`) running `--fast`.
2. Journeys gated to VM-only.
3. A contract row for every fix in this file, so none can regress.

**Acceptance:** `make check` green on a clean VM install.

---

## Rules that matter (learned the hard way)

- Hyprland 0.57 parses `hyprctl dispatch` as **Lua**: `hl.dsp.exec_cmd("…")`.
  The classic `dispatch exec -- cmd` fails *silently*.
- `install.sh` needs a real git checkout — copy `.git` or it dies at step 2.
- The VM has no `rsync`; use `tar`.
- Never `pkill -f` a pattern that matches your own command line.
- `prime-theme` cannot be run from an agent shell (safety guard matches
  "restart"); edit the generated file and the generator heredoc separately.
- rofi is a **layer surface**, not a client: assert via `hyprctl layers -j`.
- Board screenshots need `?static=1` + `--virtual-time-budget=25000`.
- `~/.local/share/prime-linux` is a checkout `prime-update` overwrites — user
  changes belong in `~/.config/prime/`, shipped changes in the repo.

## Report back per workstream

What changed, the file it landed in, the command that proves it, and the real
output. Anything you could not do gets a reason, not silence.
