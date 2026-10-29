# Hyprland 0.57 (Lua config) port — handoff

Branch `feat/hyprland-lua`, worktree `~/Projects/prime-lua`. Not pushed or merged yet.

## Why

On 2026-10-29 the nightly update installed Hyprland 0.57.0. It dropped `hyprland.conf`
(hyprlang) and only reads `~/.config/hypr/hyprland.lua`, writing a default one if
none exists. The desktop came up as bare Hyprland: no bar, dock, shortcuts or
wallpaper. It also changed `hyprctl dispatch` to take Lua (`'hl.dsp.window.close()'`)
and removed `hyprctl keyword` (use `hyprctl eval 'hl.config({...})'`).

Stopgap on Sean's desktop: hyprland + hyprpm downgraded to 0.56.2-4.1 and pinned with
`IgnorePkg = hyprland hyprpm` in `/etc/pacman.conf` (backup `/etc/pacman.conf.bak-hypr057`).

## What the branch does

- `layer/default/hypr/prime.lua` reads hyprlang `.conf` files and makes the same
  settings with `hl.*`, so no `.conf` was rewritten. One `D` table maps classic
  dispatcher names to `hl.dsp.*`. Bad lines are skipped and reported in
  `$XDG_RUNTIME_DIR/prime-hypr-errors` plus a notification.
- `layer/seed/hypr/hyprland.lua`: the entry file (dofile prime.lua → `prime.load_conf("~/.config/hypr/hyprland.conf")`).
  Seeded by install.sh; existing installs get it from migration `layer/migrations/1793297266.sh`.
- `layer/bin/prime-hypr dispatch|keyword|run-bind|lua`: passes classic syntax through on
  <0.57 and evals `prime.dispatch/prime.set/prime.run_bind` on 0.57+. All scripts,
  waybar scroll, hypridle, hyprbars buttons and elements.json use it.
- `tests/check-hypr-lua.sh` (in CI, 34 checks): real .conf files through the loader with a stand-in `hl`.

## 0.57 facts learned (verified against the real binary)

- `hl.config({["general.gaps_in"]=6})` dotted keys work. Integer options reject numeric
  *strings*; gradients must be `{colors={...}, angle=N}`. Bad keys are recorded as
  config errors and don't throw at load time.
- Lua is 5.5: for-loop variables are const.
- `hyprctl binds -j` shows `"dispatcher": "HL.Dispatcher(exec_cmd)"` with an opaque
  `arg`; `getoption -j` gives `"bool"` instead of `"int"`.
- exec-once → `hl.on("hyprland.start", fn)`. hyprbars: `hl.config({plugin={hyprbars=…}})` + `hl.plugin.hyprbars.add_button{…}`.
- The API stubs are `/usr/share/hypr/stubs/hl.meta.lua` in the 0.57 package.

## Testing against 0.57 without installing it

```bash
mkdir -p /tmp/h057 && cd /tmp/h057 && bsdtar -xf /var/cache/pacman/pkg/hyprland-0.57.0-1.1-x86_64_v4.pkg.tar.zst
# config check only (safe):
./usr/bin/Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
```

To check a whole config, use a throwaway HOME whose `.local/share/prime-linux` links to
this worktree. For a live check, run a nested `Hyprland -c test.lua` inside the session
with a test.lua that ignores `hl.on("hyprland.start")`, so exec-once can't touch real
services. Drive it with `./usr/bin/hyprctl -i <instance>`.

## Left to do, in order

1. Review, then push `feat/hyprland-lua` and open a PR. Merge to main, then run `prime-update` on the desktop.
2. Switch Sean's personal scripts from `hyprctl dispatch/keyword` to
   `~/.local/share/prime-linux/layer/bin/prime-hypr`: `~/.config/prime/addons.d/my-desktop/bin/`
   (minimise, minimise-watch, restore-minimised, send-to-workspace, open-on-workspace,
   prime-checkup-extra), `~/.config/hypr/scripts/monitor-fallback.sh` (keyword workspace),
   and `~/.hermes/scripts/{desktop-restart,prime-ptt-down}.sh`. Only after step 1, or they break.
3. Remove the `IgnorePkg` line, `sudo pacman -S hyprland hyprpm`, then log out and back in.
4. Check after upgrading: `cat $XDG_RUNTIME_DIR/prime-hypr-errors` (should be empty),
   `hyprctl configerrors`, that the bar, dock and shortcuts work, and that the title bars rebuild.

## Not yet tested / open

- The hyprbars build on 0.57 (prime-titlebars should rebuild it).
- Clicking a workspace in waybar: its hyprland/workspaces module sends the old dispatch over IPC.
- shellcheck wasn't run locally (it's not installed); CI runs it.
- prime-doctor doesn't read `prime-hypr-errors` yet.
