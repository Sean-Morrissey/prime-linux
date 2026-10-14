# Prime vs Omarchy: gap audit and plan

> **Status note, 2026-10-13.** Written as a loose file in `~`; moved here so it
> survives. Several findings have since been overtaken, and the corrections
> matter more than the original text:
>
> * **"No config layering" is wrong.** `~/.config/hypr/hyprland.conf` is already a
>   stub sourcing `layer/default/hypr/*.conf` with user-owned `monitors.conf`,
>   `hardware.conf` and `keyboard.conf` on top. The layering this asked for exists.
> * **`prime-desktop` is a stale harvest, not the live config.** Reading it is what
>   produced the wrong conclusion above, and three false gaps in the accessibility
>   audit. Read `layer/` instead.
> * **The two delivery paths are now one.** CachyOS + `install.sh` is Prime. The
>   bootc image recipe ships Aurora/KDE with no Hyprland and no supply for it.
> * **The history split is fixed.** The published 41-commit line was replaced by
>   this one on 2026-10-13 and is kept as the tag `published-2026-10-03`.
> * **`tests/vm/run.sh` passes end to end**, which answers "prove it boots".
>
> Still live: collapsing the remaining checkouts, the theme system, a `manual/`
> for users, and release channels.


**The main finding:** `prime-desktop` is the weakest copy of Prime's desktop. `~/Projects/prime-main/layer/` already has an Omarchy-like structure: 65 `prime-*` bins, `default/hypr/*.conf` split into defaults, `migrations/`, `addons/`, and wallpapers. It has 0 home-folder-path hits, 0 ML4W hits, and is checked by `tests/check-portable.sh` in CI (`.github/workflows/desktop-layer.yml`). This harvest bundle reintroduces 314 home-folder-path hits (`grep -rIn`, which includes REPORT.md's own 102). The second problem is that the bootc image ships no Hyprland at all (`prime-main/recipes/recipe.yml:44-51`, base `ghcr.io/ublue-os/aurora` = KDE).

## 1. Top 10 gaps (ranked by how "finished" Prime feels)

1. **No single source of truth.** There are seven checkouts: `prime-main`, `prime-linux`, `.desktop`, `.install`, `.integrate`, `prime-connect`, and `prime-desktop`, which has no commits. Some have diverging `recipes/recipe.yml`. Omarchy is one tree with `version` (4.0.0.alpha) and `bin/omarchy-channel*` / `omarchy-branch*`.
2. **The atomic image doesn't contain the desktop.** The recipe installs waybar, fuzzel and kitty but no Hyprland. Users actually get Prime through CachyOS plus `install.sh` (`prime-main/README.md:5`). Omarchy's equivalent is `install/omarchy-base.packages`, which delivers the whole session.
3. **No config layering.** `install.sh` does `cp -rf --remove-destination` into `~/.config`, so every update overwrites user edits. In Omarchy, `config/hypr/hyprland.lua` loads `/usr/share/omarchy/default/hypr/bootstrap.lua` and then user overrides (`hypr.monitors`, `hypr.bindings`…). `bin/omarchy-refresh-config` restores a single file with a backup.
4. **Settings pinned to Sean's machine.** `hypr/hyprland.conf:103` hardcodes `MESA_VK_DEVICE_SELECT,1002:7590!`, and `:12-13` hardcode the monitors `HDMI-A-1` / `HDMI-A-2`. `hypr/scripts/monitor-fallback.sh` patches this after the fact. Omarchy handles it with `bin/omarchy-hw-*` (17 scripts, including `omarchy-hw-match` and `omarchy-hw-nvidia`), `install/hardware/*`, and a user-owned `config/hypr/monitors.lua`.
5. **Core features depend on files outside the tree.** Examples: `~/.hermes/hermes-agent/venv` (Spotlight, push-to-talk, ledger), `~/hyprland-plugins-local/hyprbars.so`, `~/models`, `~/College`, and 2.4 GB of wallpapers (REPORT §2, MISSING.md). In Omarchy everything is in the tree or a package, and optional stacks are `omarchy-install-*` / `omarchy-remove-ai` / `omarchy-remove-gaming`. Prime already has `layer/addons/{ai,gaming,…}` to put these in.
6. **First boot shows a broken screen.** `hyprland.conf:6` sources `~/.cache/wal/colors-hyprland.conf`, which doesn't exist until pywal has run, so Hyprland shows a config error. There's also no wallpaper and the lock-screen image is broken. Omarchy ships `themes/` (23 themes, each covering every app) and `bin/omarchy-theme-set`.
7. **Cruft.** 10+ `waybar/themes/ml4w-*` dirs, `.bak-*` files, `__pycache__/*.cpython-314.pyc`, and three competing bar layouts (`config-macos`, `config-modern`, `config-sidebar`). The package list includes `responder`, `enum4linux` and `smbmap` (REPORT §4). Omarchy has one bar and package lists split per platform (`install/omarchy-{base,x86_64-only,aarch64}.packages`).
8. **CLI has no shared structure.** The 65 `layer/bin/prime-*` scripts carry no metadata (`grep prime:summary` → 0). The system-side router `files/system/usr/libexec/prime/prime` is separate from them. Omarchy's `bin/omarchy` router reads `# omarchy:summary=`/`args=` headers into groups (`GROUP_DESCRIPTIONS`), and `test/cli` validates it.
9. **No graphical acceptance tests.** The bundle has never been install-tested (REPORT §9). `prime-main/tests/` only does static and container checks. Omarchy's `test/acceptance.d/{session,panels,menu,apps,shell-surfaces}-test.sh` run inside a live VM session over SSH.
10. **End-user docs and keybind bugs.**
    - Omarchy's `manual/` has 52 numbered user pages (hotkeys, monitors, updates, themes).
    - Prime's `docs/` is mostly internal (`REDTEAM-2026-10.md`, `BUILD-STATE-*.md`), plus `USER-GUIDE.md` (250 lines) and `keybinds.md` (77 lines).
    - Keybind bugs: `bindrni = , R` (`:348`) runs a script every time the letter R is released system-wide, and `binde` push-to-talk (`:347`) re-fires on key repeat.

## 2. Phases

**Quick wins (under a day each)**
- Delete the ML4W themes, `.bak-*` files and `__pycache__`. Pick one waybar layout.
- Change the push-to-talk binds to `bind` / `bindr` on `SUPER+R` only.
- Ship a default `colors-hyprland.conf` in the tree and source pywal's output only if present.
- Move `monitor=` and GPU env into a user-owned `monitors.conf` / `envs.conf` generated by the existing `files/system/usr/libexec/prime/hw-probe.sh`.
- Remove the security, 3D-printing and Arduino packages.
- Add `# prime:summary=` headers and have `prime help` list them, using Omarchy's router logic.
- Run `prime-main/tests/check-portable.sh` against this bundle as the pass/fail gate.

**Structural (1–2 weeks)**
- Make `prime-main/layer/` the only payload. The bootc `files` module copies it to `/usr/share/prime`; the CachyOS installer uses the same tree.
- Source Hyprland from a maintained COPR or a build stage, as the recipe itself notes. Add a session `.desktop`.
- Use a `~/.config/hypr/hyprland.conf` stub that sources `/usr/share/prime/default/hypr/*.conf` and then user files. Port `omarchy-refresh-config`.
- Run `prime-migrate` as a systemd **user** unit on login, with per-migration state in `~/.local/state/prime/migrations`.
- Move Hermes, the local-model features and hyprbars into `layer/addons/ai` with clean "not installed" fallbacks.
- Extend `tests/vm/desktop-checks.sh` to cover Omarchy's acceptance categories and run it in CI on the built image.

**Longer-term**
- A theme system modeled on `themes/<name>/` with `theme-set` across Hyprland, waybar, rofi, kitty and swaync, replacing pywal as a dependency.
- Image variants for NVIDIA (`bazzite-nvidia` / `bluefin-nvidia` bases), which the recipe already flags.
- Release channels, pinned base tags, and signed releases (`tools/release-sign.sh` exists).
- A `manual/` written for users. Move developer docs elsewhere.
- One first-run flow that disables Aurora's own welcome so it doesn't race `prime-firstboot.service`.

## 3. Where the analogy breaks

**Transfers directly, and fits bootc better than Arch:**
- Read-only defaults in `/usr/share/prime` with user overrides in `~/.config`.
- Migrations: bootc updates `/usr` atomically but never touches `$HOME`, which is exactly what migrations are for.
- The namespaced CLI with metadata, the numbered manual, and VM acceptance tests.

**Must be re-invented:**
- **Package lists → `recipe.yml` modules and per-hardware base images.** Optional features become flatpaks, brew packages or toolbox containers, not host `dnf`.
- **`install/hardware/*.sh` → build-time files.** Hardware fixes become `/usr/lib/bootc/kargs.d`, `modprobe.d` and udev rules baked into the image. Only true per-machine detection (monitors, GPU selection) stays at runtime and writes to `/etc` or `~/.config`.
- **`omarchy-update` → staged `bootc upgrade` plus a user-level migration on next login.**
- **snapper/limine → bootc deployments for `/usr`.** `/etc` and `/home` still need btrfs snapshots (`backend-btrfs.sh`).

**Deliberately don't copy:**
- Runtime mutation of the host package set.
- `curl | sh` installs at build time (`recipe.yml` installs `uv` this way, unpinned).
- Omarchy's bundled commercial web apps and keybinds (HEY, Basecamp).
- High-churn migrations that `sed` user files (165 in Omarchy). Prefer layering, so most changes need no migration.
- Keeping two delivery paths (CachyOS installer and image) indefinitely. Pick one as primary.

## 4. Best weekend

1. **Collapse to `prime-main`.** Diff this bundle against `layer/` and port only what's genuinely newer (`monitor-fallback.sh` logic, the push-to-talk fix). Archive `prime-desktop` and the other five checkouts. This removes gaps 1, 5 and 7 in one move.
2. **Put the desktop in the image.** Source Hyprland, have the `files` module install `layer/` to `/usr/share/prime`, and seed a stub `hyprland.conf` plus `monitors.conf`.
3. **Prove it boots.** Build the image, boot it in `tests/vm/`, and assert:
   - `hyprctl configerrors` is empty
   - waybar and swaync are running
   - `hyprctl monitors` matches `monitors.conf`
   - the launcher opens
   - no home-folder paths exist under `/usr/share/prime`

   Gate CI on it.
