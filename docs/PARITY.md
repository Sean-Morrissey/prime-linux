# Prime Linux vs Omarchy — capability parity

**Source:** Omarchy's repository (`basecamp/omarchy`, default branch `quattro`),
read on 2026-10-01 through the GitHub API: the full list of `bin/omarchy-*`
commands (~430), `install/omarchy-base.packages`, and the scripts for
migrations, idle, night light, web apps and screen recording. Where a row says
what Omarchy does, it is from those files, not from memory. "Standard desktop"
rows are things any Mac/Windows user expects whether or not Omarchy has them.

Status: **have** — Prime does it · **better** — Prime does it in a way that
suits a beginner more · **built** — added in this round (2026-10-01) ·
**pack** — belongs in an optional pack, not the core · **missing** — not yet.

## Summary

| | Count |
|---|---|
| Rows | 63 |
| have / better (before this round) | 27 |
| built this round | 25 |
| pack (by design) | 5 |
| missing | 7 (incl. hide-bar toggles, not planned) |

The ones still missing are listed at the bottom with an owner.

## Launching and finding things

| Capability | Omarchy | Prime | Status |
|---|---|---|---|
| App launcher | walker / quickshell | Spotlight (Super+Space): apps, files, maths, web | have |
| One menu for everything | `omarchy-menu` (Super+Alt+Space) | Prime menu (Super+Alt+Space), declarative `menu.json`, add-ons extend it | have |
| Keybinding cheat sheet | `omarchy-menu-keybindings` | Super+/ reads live `hyprctl binds`; every bind has a description (tested) | have |
| Right-click menus on the bar | — | every bar element has one (`elements.json`) | better |
| File search | walker files | Spotlight (fd + plocate) | have |
| Calculator | walker calc / omacalc | Spotlight maths + GNOME Calculator (menu, XF86Calculator key) | built |
| Emoji picker | `omarchy-menu-emoji` (Super+Ctrl+E) | `prime-emoji` (rofimoji: types + copies), Super+Ctrl+E | built |
| Clipboard history | walker clipboard | Super+V (cliphist, text + images, survives app close) | have |
| Web apps | `omarchy-webapp-install/remove` (Chromium `--app`) | `prime-webapp`: pick WhatsApp/YouTube/Gmail… or any URL; default browser's app mode, Firefox-only falls back to a window; icon fetched | built |
| TUI apps as apps | `omarchy-tui-install` | — | pack (coding) |

## Capture

| Capability | Omarchy | Prime | Status |
|---|---|---|---|
| Screenshot region/window/screen + annotate | grim/slurp/satty | `prime-snip` (Print, Shift/Super/Alt+Print), satty | have |
| Screen recording with bar indicator | gpu-screen-recorder + indicator | `prime-record` (Super+Shift+R region, Super+Ctrl+Shift+R screen with sound), red ● timer on the bar, click to stop; gpu-screen-recorder with wf-recorder fallback (VMs) | built |
| Colour picker | hyprpicker | `prime-colour` (Super+Shift+C), copies hex, shows swatch | built |
| Text from screenshot (OCR) | `omarchy-capture-text` (tesseract) | — | missing |
| QR scan | `omarchy-capture-qr` | — | missing |
| Webcam overlay in recordings | yes | — | pack (creator) |

## Quick switches (Omarchy `omarchy-toggle-*`)

| Capability | Omarchy | Prime | Status |
|---|---|---|---|
| Night light | hyprsunset toggle | `prime-toggle nightlight` (Super+Ctrl+N), remembered across logins, bar icon | built |
| Idle / stay awake | `toggle-idle` | `prime-toggle idle` (Super+Ctrl+I), bar icon while on, never persists | built |
| Do not disturb | `toggle-notification-silencing` | `prime-toggle dnd` (Super+Shift+K), swaync, bar bell shows it | built |
| Animations | `toggle-animations` | `prime-toggle-animations` | have |
| Toggle section in the menu | Menu → Toggle | Menu → Quick switches (+ live-state picker `prime-toggle menu`) | built |
| Hide the bar / gaps / transparency | yes | — | missing (low value for beginners) |
| Touchpad/touchscreen on/off | yes | — | missing |

## Audio, network, Bluetooth

| Capability | Omarchy | Prime | Status |
|---|---|---|---|
| Volume/brightness OSD | swayosd (`omarchy-osd`) | swayosd via `prime-osd`; keys still work if the popup service is down | built |
| Output/input device switcher | `audio-output-switch`, wiremix TUI | `prime-sound`: click the volume pill → speakers/headphones/mics list → full mixer | built (GUI, not TUI) |
| Wi-Fi picker | impala (iwd) | `prime-wifi`: click the bar icon → networks by strength → password prompt; NetworkManager (what CachyOS uses — impala needs iwd) | built |
| Bluetooth picker | bluetui | `prime-bluetooth`: paired devices one click to (dis)connect; blueman for first pairing | built |
| Advanced network (VPN, static IP) | nmtui-ish | nm-connection-editor (menu + right-click) | have |
| Media keys / now playing | yes | yes + bar media controls | have |

## Laptop

| Capability | Omarchy | Prime | Status |
|---|---|---|---|
| Battery on the bar | yes | waybar battery (hidden automatically on desktops) | built |
| Low-battery warning | `notification-battery` | `prime-battery-alert` user service (15% and 5%, not while charging) | built |
| Power profiles | `powerprofiles-*` | `prime-power-profile`: click the battery, or Menu → Quick switches | built |
| Brightness keys | brightnessctl + OSD | same, via `prime-osd` | built |
| Lid / suspend → lock | `system-lid-close`, sleep lock | logind suspends; hypridle locks before sleep | have |
| Clamshell / external monitor | `hyprland-monitor-clamshell` | — | missing |
| Touchpad gestures | yes | 3-finger swipe = workspaces; tap-to-click, natural scroll | have |
| Hibernation setup | `hibernation-setup` | — | pack (later; needs swap sizing) |
| Hybrid GPU switch, per-vendor hw fixes | many `hw-*` scripts | GPU env written per vendor at install (`hardware.conf`) | have (basic) |

## Settings a beginner reaches without a terminal

| Capability | Omarchy | Prime | Status |
|---|---|---|---|
| Keyboard layouts | edit input.conf | `prime-keyboard` searchable list, Super+Ctrl+Space switches, bar shows layout when 2+; installer copies the layout chosen in the CachyOS installer | better |
| Displays | `hw-display`, edit monitors.conf | nwg-displays (GUI) | better |
| Default apps / browser | `default-browser` etc. | `prime-default-apps` | have |
| Printers | cups + system-config-printer | same; installer turns printing on | built |
| Timezone | `menu-timezone`, tzupdate | set by the CachyOS installer | have (no menu row) |
| Fonts switcher | `font-set` | — | pack (style) |
| Themes (whole desktop, one switch) | `theme-set` (+ browser, editors…) | `prime-theme`: wallpaper + accent drive bar, lock, notifications, menus, GTK accent | have (fewer app integrations) |
| Lock screen | hyprlock | hyprlock with theme | have |
| Login screen | SDDM | SDDM (installed + enabled if none) | built |
| Boot splash | plymouth | Brand teammate | have/elsewhere |
| App Store (GUI) | none — `pkg-install` TUI | GNOME Software + Flathub | better |
| Fingerprint / FIDO2 | `setup-security-*` | — | missing → Security owner |
| Firewall | ufw | — | missing → Security owner (roadmap item 4) |
| Passwords for apps (keyring) | gnome-keyring | gnome-keyring + libsecret | built |
| Phones / USB drives / network shares | gvfs-mtp/smb, udiskie | gvfs, gvfs-mtp, gvfs-smb, udisks2 in Nemo | built |
| PDF / images / video / archives | evince, imv, mpv | Papers, Loupe, Celluloid, File Roller (GUI-first) | built |

## Keeping it working

| Capability | Omarchy | Prime | Status |
|---|---|---|---|
| One command to update all | `omarchy-update` | `prime-update` (+ bar count, menu) | have |
| Snapshot before update, boot-menu rollback | limine + snapper | same (CachyOS default) + desktop-settings backup on every pacman run | better |
| Migrations for existing installs | `omarchy-migrate`, state in `~/.local/state/omarchy/migrations` | `prime-migrate`, `layer/migrations/<unix-time>.sh`, state `~/.config/prime/migrations` | built |
| Release channels | `channel-set` (stable/edge/dev) | git tags + branch per channel (docs/RELEASE.md) | built (docs) |
| Health check / repair | `omarchy-debug`, `refresh-*` | `prime-doctor` (Super+H, quiet check at login) | have |
| Reset a config to default | `refresh-config` | defaults never edited (layer), user files separate | better |
| Uninstall | — (it's the OS) | `prime-uninstall` restores configs, theme, services; `--packages` | better |
| Installer progress, log, resume | ISO installer | `install.sh`: [n/8] steps, log file, resumes, accurate `--dry-run`, preflight | built |
| Factory reset | `system-factory-reset` | — | pack (later) |

## Packs, by design not in the core

Steam/Lutris/RetroArch/Xbox controllers (gaming), dev environments via mise,
Docker, editors (coding), OBS/Kdenlive/Pinta (creator), 1Password, Spotify,
Signal, Dropbox, Tailscale (services), AI agents — Omarchy installs most at
first run or offers them in Install; Prime keeps them in packs
(`layer/addons/gaming|coding|creator|student|ai`) so the base stays small.

## Still missing — and who it goes to

| Gap | Why it matters | Owner |
|---|---|---|
| OCR from a screenshot, QR scan | handy, not essential | Assistant (fits `prime-snip --action`) |
| Clamshell mode (lid shut on an external monitor) | laptop + dock users | Release/QA, next round |
| Touchpad on/off toggle | laptops with a mouse | Release/QA, next round |
| Fingerprint / FIDO2 login | laptops with readers | Updates & Security |
| Firewall default | security baseline | Updates & Security |
| Hide-bar / gap toggles | power users | not planned |
