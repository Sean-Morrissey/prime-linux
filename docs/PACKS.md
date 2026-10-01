# Packs — set your computer up for something, in one step

A **pack** installs the apps for one kind of use *and* sets them up: menu rows,
keyboard shortcuts, sensible settings, and a health check that tells you in
plain words if something isn't right. Packs are built on Prime's add-on system,
so everything here also works for add-ons (like `ai`).

## For users

Open **Prime menu → Settings → Add-ons** (or run `prime-addon pick`) and pick a
pack. Or in a terminal:

```bash
prime-addon                  # list packs and add-ons, and which are on
prime-addon info gaming      # what it would install and add — before you decide
prime-addon enable gaming    # install + set up + switch on (safe to run again)
prime-addon check gaming     # health check (✓ fine, ! suggestion, ✗ needs fixing)
prime-addon disable gaming   # menu, shortcuts and bar items go; apps stay
```

Turning a pack **on** asks for your password once (to install apps) and shows
each step as it goes. Running it again only fills in what's missing.

Turning a pack **off** removes its menu section, shortcuts, bar items and any
lines it added to your shell — the apps stay installed so nothing you made is
lost. It lists them, with the exact command to remove them too.

### Gaming — `Super+Alt+G`

| You get | Details |
|---|---|
| Steam with Proton | Switches on 32-bit software ("multilib") first if needed, with a backup of `/etc/pacman.conf`. Installs the right 32- and 64-bit Vulkan driver for your graphics card in the same step (AMD, Intel, NVIDIA, or NVIDIA's open driver). |
| Proton-CachyOS | On CachyOS: `proton-cachyos-slr`, `cachyos-gaming-meta` (Wine, winetricks, protontricks, umu) and ProtonUp-Qt. Skipped automatically on plain Arch. |
| Heroic, Lutris | From Flathub. Heroic: Epic, GOG, Amazon. Lutris: everything else. |
| GameMode | Installed, and you're added to the `gamemode` group (not an admin group). Per game: Launch Options `gamemoderun %command%`. |
| FPS overlay (MangoHud) | Loaded into games but hidden. `Super+Alt+H` shows it for the next game; `Right Shift+F12` inside a game. Settings in `~/.config/MangoHud/MangoHud.conf` (written once, then yours). |
| Performance mode | `Super+Alt+P` switches the power profile to *performance* and back to what it was. A speedometer shows in the bar while it's on (click to switch off). Uses power-profiles-daemon (or tuned-ppd). |
| Window rules | Tearing allowed for games (lowest input lag), FreeSync/G-Sync in fullscreen, direct scanout, Wine/`.exe` games never trigger the lock screen, Steam's small windows float, Big Picture is fullscreen. Prime's defaults already make Steam games fullscreen and lock-proof. |
| Controllers | Xbox/PlayStation/Switch/Steam pads via Steam's device rules (`steam-devices`). |

Menu: Steam · Heroic · Lutris · Performance mode · FPS overlay · Proton versions · Gaming tips · Check my gaming setup.

### Coding — `Super+Alt+C`

| You get | Details |
|---|---|
| Code - OSS (`code`) | The open-source build of VS Code from the official repos, so tutorials match. Extensions come from Open VSX. `Super+Alt+E` opens it in `~/Projects`. Zed is one click away ("Get Zed"). |
| git, set up kindly | Asks your name and email the first time (or takes them from the first-run interview). Sets only what you haven't chosen: `main` as the default branch, merge-on-pull, auto upstream on first push, `delta` for readable diffs. "Sign in to GitHub" uses `gh` so pushing just works. |
| Languages on request | Prime menu → Coding → Add a programming language: Python, JavaScript/Node (LTS), Go, Rust, Java 21 — installed per user with `mise`, no admin rights. |
| Containers | Rootless **Podman** (no daemon, no admin group; your account gets its sub-ID range). **Docker** only on request ("Docker too"): installed with socket activation; joining the `docker` group is a separate question that warns it is admin-equivalent and defaults to *no*. |
| Projects folder | `~/Projects`, in the file manager's sidebar. "New project…" makes a folder with git and opens it. |
| Terminal niceties | A git-aware prompt (starship), `z` folder jumping (zoxide), Ctrl+R history search (fzf), `ll`/`la`/`tree` (eza), `lg` (lazygit), ripgrep and bat. One marked line in `~/.bashrc`/`~/.zshrc`, or a file in `~/.config/fish/conf.d/` — removed again when the pack is switched off. `PRIME_PROMPT=0` keeps your own prompt. |

### Creator — `Super+Alt+V`

| You get | Details |
|---|---|
| Kdenlive, Blender, Krita, GIMP, OBS Studio, Audacity | From the official repos, with Kdenlive's helpers (MediaInfo, image formats, voice noise suppression). |
| Hardware video encoding | AMD: Mesa's VA-API (already part of the driver). Intel: `intel-media-driver` + `vpl-gpu-rt` (Quick Sync). NVIDIA: NVENC from the driver, plus `libva-nvidia-driver` for decoding. "Check my creator setup" lists exactly which codecs your card encodes and decodes (H.264, HEVC, AV1…). |
| GPU rendering for Blender | A menu row that shows the download size first, then installs HIP (AMD), CUDA (NVIDIA) or oneAPI (Intel) and says where to switch it on in Blender. |
| More apps | "Get more creative apps…": Ardour, Inkscape, HandBrake, darktable, G'MIC filters, OBS virtual camera. |
| OBS | `Super+Alt+R`. Its first-run wizard picks your card's hardware encoder; screen capture uses the PipeWire portal Prime already ships. |

### Student — `Super+Alt+S`

| You get | Details |
|---|---|
| Notes | Obsidian (official repos), opening a vault in `~/Study/Notes` the first time. `Super+Alt+N`. |
| Citations | Zotero from Flathub. |
| Office | LibreOffice with English spell-check; if your system language isn't English, its spell-check and LibreOffice language pack are added. |
| PDFs | Xournal++ to annotate PDFs and handwrite; PDF Arranger to merge, split and reorder. |
| Focus mode | `Super+Alt+F`: 25 minutes (`PRIME_FOCUS_MINUTES`), notifications paused, a countdown next to the clock, a nudge to take a break at the end. Your Do-Not-Disturb setting is restored afterwards. |
| Study folder | `~/Study/` with Notes, Classes, Reading and Assignments, in the file manager's sidebar. |
| AI tutor | `Super+Alt+T` asks the AI add-on (`prime-ask`) with a tutor framing: explains step by step, checks understanding, and guides rather than writes graded work. If the AI add-on is off it says how to switch it on. |

## For contributors: making a pack

A pack is a folder `layer/addons/<name>/`. Only `addon.conf` is required.

```
layer/addons/<name>/
  addon.conf          what it is and what it installs (below)
  bin/prime-<name>    its helper: setup / teardown / check, plus its own commands
  hypr.conf           shortcuts (bindd only — every bind needs a description) and window rules
  menu.json           its Prime menu section (same shape as layer/default/menu.json)
  waybar-top.json     bar modules to insert: {"insert": {"modules-right": {"after": "...", "modules": [...]}}, "modules": {...}}
  waybar.css          styles for those modules (only @accent comes from the theme)
  elements.json       right-click menu rows (see layer/addons/ai)
  *.desktop           app-list entries; @LAYER@ is replaced with the install path
```

### addon.conf

| Field | Meaning |
|---|---|
| `KIND=pack` | Listed under *Packs* (otherwise under *Add-ons*). |
| `TITLE`, `ICON`, `DESCRIPTION` | Name, a Nerd Font glyph, and one plain-language line. |
| `PACKAGES` | Official-repo packages, installed in one `pacman` transaction. |
| `PACKAGES_AMD` / `_INTEL` / `_NVIDIA` / `_NOUVEAU` / `_NONE` | Added to that same transaction for the graphics in this machine (`nvidia` = proprietary driver installed, `nouveau` = NVIDIA without it, `none` = nothing detected, e.g. a VM). Hybrid laptops get both lists. |
| `PACKAGES_IF_AVAILABLE` | Installed only if the repositories have them — for CachyOS-only packages. Skipped ones are named in the output. |
| `FLATPAKS` | Flathub app IDs, installed per user (`--user`, no password). A failed download warns but doesn't block the pack. |
| `NEEDS_MULTILIB=1` | Offer to switch on 32-bit packages first (backup kept, full system update after). |
| `SETUP` | Runs after the packages, e.g. `"bin/prime-<name> setup"`. Must be safe to run again. A failure leaves the pack off. |
| `TEARDOWN` | Runs on disable: undo runtime state and anything written outside the pack (shell lines, bookmarks). Don't delete the user's files or settings. |
| `CHECK` | Prints health lines `ok<TAB>text`, `warn<TAB>text` or `bad<TAB>text` (helpers `ck_ok`/`ck_warn`/`ck_bad`). Say what's wrong and the one command or menu row that fixes it. prime-addon already checks the packages and Flatpaks. |

### Rules of thumb

- **Plain language.** The person reading has never used Linux. Say what it does for them, not what it is.
- **Idempotent.** `enable` runs again after every failure; check before you change, and never append twice (`rc_add` marks its lines).
- **Reversible.** Anything you add outside the pack folder, `TEARDOWN` removes. Apps stay; `disable` lists the ones the pack installed.
- **Never prompt in non-interactive mode.** `PRIME_NONINTERACTIVE=1` (the installer, the interview, tests): `ask` returns its default, so make the default the safe answer.
- **Menu rows must resolve.** Start apps through `prime-addon open 'native-cmd|flatpak.id'` — it runs whichever is installed, or offers to install it — so `prime-menu --check` passes even before the apps are there.
- **Shortcuts** go on `Super+Alt+<letter>`, and `tests/check-packs.sh` fails if two binds collide.
- **No root daemons, no admin groups by default.** If something needs one (Docker), ask separately and say why it matters.
- Verify package names with `pacman -Si` and Flathub IDs with `flatpak remote-info flathub <id>`.

`layer/addons/_lib/pack.sh` has the shared helpers: `say`/`note`/`warn`, `ask`,
`notify`, `nonint`, `gpus`, `ck_*`, `rc_add`/`rc_remove`, `bookmark_add`/`_remove`,
`bar_signal`, `in_group`, and `PACK_STATE` (where prime-addon records what each
pack installed).

### Testing

```bash
tests/packs-in-container.sh                 # fresh Arch container: install Prime, enable/disable every pack
PRIME_GPU=amd tests/packs-in-container.sh   # pretend a graphics vendor
FULL=1 tests/packs-in-container.sh          # really install everything (many GB)
```

The default mode resolves every package (for every GPU vendor) and every Flathub
ID without installing them, then checks the config Hyprland would load, the menu,
the bar, each pack's setup and that `disable` removes it all again.

Hooks for automation: `PRIME_NONINTERACTIVE=1`, `PRIME_GPU`, `PRIME_ADDON_PACKAGES=check|skip|install`,
`PRIME_GIT_NAME`/`PRIME_GIT_EMAIL`, `PRIME_LANGS="python node"` (coding), `PRIME_FOCUS_MINUTES` (student).
