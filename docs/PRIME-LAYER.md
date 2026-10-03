# The Prime layer on CachyOS — install script, design, roadmap

**Status (2026-10-01):** the desktop layer installs onto a stock CachyOS with
one command and is tested in a clean container as a stranger's account.
Owner decisions this follows: Prime OS = CachyOS + the Prime layer (2026-09-26),
and ship it as an **install script first** — install CachyOS with its own
installer, then add Prime — which sidesteps the Calamares/boost blocker on the
custom ISO (2026-10-01). The ISO can run the same script later.

## Install

```bash
# on a fresh CachyOS (any edition), as your normal user:
curl -fsSL https://raw.githubusercontent.com/sean-morrissey/prime-linux/main/boot.sh | bash
# or from a checkout:
bash install.sh            # --dry-run to see what it would do
```

Log out, choose **Hyprland** on the login screen (after the first *Update everything* it is
listed as **Prime**). Undo: `prime-uninstall`.

## How it is put together

```
layer/
  bin/          every prime-* command (bar widgets, menus, theme, doctor, update…)
  default/      Prime's defaults — hypr/, waybar/, rofi/, swaync/, kitty/,
                menu.json (Prime menu), elements.json (right-click menus)
  seed/         files copied into ~/.config ONCE (the user's own from then on)
  systemd/      user services: bars, clipboard history (prime-session.target)
  system/       pacman hook: save desktop settings before every package change
  addons/<n>/   optional extras (addons/ai today; packs next — see roadmap)
  wallpapers/   original CC0 set (tools/make-wallpapers.py)
os/arch/packages.txt   official-repo packages only — no AUR needed
install.sh  boot.sh  tests/
```

Three layers, so customisation stays unlimited and updates never fight the user:

| Layer | Where | Who changes it |
|---|---|---|
| Defaults | `~/.local/share/prime-linux/layer/default` | `prime-update` (git pull) |
| Add-ons / packs | `layer/addons/<name>`, enabled in `~/.config/prime/addons` | `prime-addon`, later Prime itself |
| Personal add-ons | `~/.config/prime/addons.d/<name>` (same format; `prime-import` makes one from a pre-Prime desktop — [MIGRATING.md](MIGRATING.md)) | the user — never shipped, never overwritten |
| The user's own | `~/.config/hypr/hyprland.conf`, `~/.config/kitty/kitty.conf`, `~/.config/waybar/user.css`, `~/.config/prime/menu.json` | the user — never overwritten |

Hyprland sources defaults first and the user's lines last, so the user always
wins. The bar is assembled at start-up (`prime-bar`) from the default config +
add-on fragments, with a stylesheet chain theme colours → default → add-ons →
`user.css`. Colours live in one generated file per app under
`~/.config/prime/theme/` (`prime-theme`), so a theme change never edits the
user's files and status colours (warning red, amber) never collide with the accent.

Safety rails already in place: desktop settings saved before every pacman
transaction (`prime-desktop-backup`, newest 20, restore from the menu); a quiet
login check that repairs what it safely can (`prime-doctor --login`); the AI key
stored `0600` and never in a config file; no kitty remote-control socket;
nothing in the layer runs as root except the backup hook, which drops to each
user with `runuser`.

## The desktop's standard, and how it is held

Every surface is judged against one bar: it feels like macOS, never needs a terminal,
is discoverable from the bar or a menu, speaks plain language, says Prime, works
from the keyboard with a name on every control, has no hardcoded font size, and never
carries state in colour alone. `tests/check-static.sh` enforces it (no container
needed); `tests/install-in-container.sh` repeats it on a real install.

| Rule | How it is met |
|---|---|
| No terminal | Prime's own tasks (health check, updates, About, add-ons, update list, undo an update, the AI answer) run in a **Prime window** (`prime-panel`): progress and results as rows that say *OK*, *Fixed*, *Needs you*, with buttons for the fix. A password is asked for in a Prime box (`prime-askpass`, used by `sudo -A`). Wi-Fi is a picker (`prime-wifi`), the processor/memory/graphics readouts open **Activity** (`prime-activity`). Menu rows use `kind: "panel"` (the old `"term"` means the same and never opens a terminal); `prime-float` remains only as a shim for old custom rows. |
| One text size | Theme → **Text size** (Small / Default / Large / Larger, `prime-theme --set-text`) is the only font size. It sets the system font; the bar, notifications, Prime Search and Prime windows size text in `rem` from it, and `prime-theme` writes `fonts.rasi` (menus), the lock-screen, title-bar and terminal sizes from the same base. |
| Keyboard | `Super+Alt+B` lists every bar item and opens its menu (the same as right-clicking it); `Ctrl+Shift+Esc` opens Activity; every bind has a description (`Super+/`). |
| Names | Every bar item has a worded tooltip; Prime windows and Prime Search give every row and control an accessible name. (rofi pickers have no screen-reader support — a known gap.) |
| Not colour alone | Muted sound says *Muted*; the lock screen says *Caps Lock is on* and *Wrong password*; title-bar buttons carry ✕ − +; Activity says *idle / light / busy*; update and notification tooltips say the state. |

Previews of each surface: `layer/branding/previews/` (re-render with
`layer/branding/src/preview-desktop.sh`; the lock screen and title bars are mocks
from the same values, because only Hyprland can draw them).

## A fresh install comes up as Prime

- **Install script** (CachyOS + `install.sh`): unchanged; the first *Update everything*
  adds the **Prime** session to the login screen (`layer/system/wayland-sessions`).
- **ISO**: a bootable installer image was explored and is parked (CachyOS's own
  installer can't currently be rebuilt). It lives in the repository's history.

## Roadmap — what makes it "Prime sets it up for you"

Order matters: each step uses the one before.

1. **Packs** (on the add-on system). `gaming` — Steam, Proton-GE helper,
   GameMode, MangoHud, a performance toggle. `coding` — editor, git, containers,
   language toolchains on request. `creator` — Kdenlive, Blender, Krita, OBS with
   hardware encode. `student` — notes, citations, PDF stack, the tutor. Each pack
   = `addon.conf` (packages, setup) + menu rows + binds + doctor checks.
2. **Nightly updates for everyone.** Ship `prime-pc` (live on the reference
   machine since 2026-09-26: check → snapshot → apply → health → rollback, never
   reboots) as part of the install, default policy from the interview.
3. **Conversational customisation.** The AI add-on gets a fixed toolbox instead
   of a shell: `theme`, `addon/pack`, `bind`, `setting`, `update`, `doctor`,
   `restore`. Every call is checked against `templates/capability-ladder.yaml`
   (destructive and secrets always ask; Prime can't raise its own level),
   written to an audit log, and undoable through the desktop backups.
4. **Security defaults.** Firewall on (ufw/firewalld, LAN-friendly profile),
   automatic security updates via step 2, signed releases of the layer.
5. **First-run interview**
   as the front door: picks packs, theme, autonomy level and update policy, so
   someone who has never used Linux answers questions instead of editing files.
