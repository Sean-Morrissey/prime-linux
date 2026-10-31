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

## Verified against the real binaries (2026-10-29)

Both checks ran with a throwaway `HOME` whose `.local/share/prime-linux` links to this
worktree, so the whole real stack was read: `hyprland.conf` → `prime.conf` → the layer's
`.conf` files → `monitors.conf`, `keyboard.conf`, the theme and the add-ons.

- **0.57.0**: `config ok`, and `$XDG_RUNTIME_DIR/prime-hypr-errors` was written and empty —
  not one line skipped. (The errors file is only written when `XDG_RUNTIME_DIR` exists;
  a missing file proves nothing, so create the directory before trusting it.)
- **0.56.2**: also `config ok`, zero skipped lines. This matters because 0.56.2 *prefers*
  `hyprland.lua` when it exists — the migration changes how the current version reads its
  config too, at the next login, before any upgrade.
- **hyprbars on 0.57**: upstream tagged `v0.57.0` (= `main`, `d2427d4`), so it builds. Built
  against the package's own headers and loaded into a nested 0.57 session: the plugin loads,
  `configerrors` is empty, and Prime's own settings arrive —
  `getoption plugin:hyprbars:bar_height` → `int: 26, set: true`. The three
  `hyprbars-button` lines go through `hl.plugin.hyprbars.add_button` without error.
  Note `--verify-config` alone can *not* test this: with the plugin unloaded the loader
  skips `plugin.*` options by design, so that path only appears in a live session.

To build the plugin against a version that isn't installed, point pkg-config at the
extracted headers (`hyprland.pc` has `prefix=/usr/include`):

```bash
sed "s|^prefix=/usr/include|prefix=$PWD/usr/include|" usr/share/pkgconfig/hyprland.pc > pc/hyprland.pc
PKG_CONFIG_PATH=$PWD/pc make -C hyprbars
```

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

## Clicking a workspace in the bar: broken by 0.57, worked around in prime-bar

Confirmed, not suspected. waybar 0.15.0's `hyprland/workspaces` sends `dispatch workspace N`
on the raw socket; 0.57 replies

```
error: 3 [string "return hl.dispatch(workspace 2)"]:1: ')' expected near '2'
 → Note: dispatch in lua is a shorthand for hl.dispatch(...), your syntax might need to be updated.
```

and waybar ignores the reply, so the click fails silently. It can't be fixed from waybar's
config: that module hardcodes the dispatch and has no `on-click` option. Scrolling,
right-click and Super+1…5 are unaffected — they already go through `prime-hypr`.

Upstream fixed it in [Waybar#5013](https://github.com/Alexays/Waybar/pull/5013) (issue
[#5008](https://github.com/Alexays/Waybar/issues/5008)), merged but **not in any tagged
release** — 0.15.0 (Feb 2026) is still the newest, so the repos don't have it.

`prime-bar` now works around it when building the config, and only then. It reads both
versions and swaps `hyprland/workspaces` for `ext/workspaces` (`on-click: activate`,
the maintainers' suggested alternative) when Hyprland is 0.57+ *and* waybar is 0.15.0 or
older — that module goes over the Wayland ext-workspace protocol instead of Hyprland IPC,
which both 0.56.2 and 0.57 implement. On 0.56 the bar is untouched, and the workaround
retires itself the moment waybar tags the fix, with no migration and nothing to undo. If
either version can't be read, the shipped bar is left alone.

The two things that made the swap look risky both turned out fine, checked on screen
against the real bar rather than reasoned about:

- `ext/workspaces` has a smaller set of `format-icons` states (`active`, `default`, and
  workspace names). Prime's dots only ever use `default`, so they render identically;
  the states that don't carry over are dropped rather than left to read as workspace
  names. The side bar's `button.occupied` rule has no `ext` equivalent, so an occupied
  dot there sits at `@fg_faint` instead of `@fg_dim` — the only visible difference.
- `persistent-workspaces` is hyprland-only. Prime's five dots are real persistent
  workspaces in `hyprland.conf`, so the protocol lists them all; `prime-bar` turns any
  `persistent-workspaces` a config *does* declare (a personal `addons.d` bar, say) into
  real persistent workspaces via `prime-hypr keyword`, which is the same thing by another
  route.
- `ignore-hidden` stays at its default of `true`, which was worth checking rather than
  assuming: "hidden" means the compositor's own workspaces, not empty ones. Setting it
  `false` to make sure an empty desktop kept its dot was unnecessary — a persistent
  desktop is never hidden — and it drew a `special:minimized` chip among the dots the
  moment anything was minimised.

`tests/check-bar-workspaces.sh` covers all of it: swapped on 0.57+old waybar, untouched on
0.56, untouched again on waybar 0.16, and the persistent-workspaces translation.

## Not yet tested / open

- shellcheck wasn't run locally (it's not installed); CI runs it.
- ~~prime-doctor doesn't read `prime-hypr-errors` yet.~~ It does now: Check and fix names
  the settings that were dropped, says so when none were, and catches the case where the
  Lua loader never ran at all (`tests/check-doctor-hypr-errors.sh`).
- `prime.lua:119` (`exec_rules`): `[float false]` yields the string `"false"`, which is
  truthy, via the Lua `and`/`or` idiom. Unreachable with real hyprlang syntax — exec rules
  are flags — so it was left alone rather than churn a merging branch.
