# Waybar / Hyprland Recovery Playbook

The setup that works after the 2026‑04‑28 fixup. Use this if a CachyOS update
breaks the bar again.

## One‑shot fix

    bash ~/.config/waybar/scripts/doctor.sh

It checks every known failure mode and repairs whatever it finds.

## What the bar depends on

| Thing | Why | How it can break |
|---|---|---|
| `ttf-jetbrains-mono-nerd` package | Provides the Nerd Font glyphs (icons) used in the bar | An update may drop it; icons render as boxes / wrong glyphs |
| `kded6` **not** owning `org.kde.StatusNotifierWatcher` on D‑Bus | Tray apps (Discord, etc.) register with whoever owns the Watcher; only Waybar shows what's registered with it | After a `plasma-workspace` update kded6 starts faster than Waybar and grabs the name first → tray empty |
| `layerrule = blur waybar` (space‑separated) in `hyprland.conf` | Frosted‑glass blur on the bar | Hyprland 0.54 removed the comma form (`blur, waybar`) and dropped `ignorezero/ignorealpha` for layer rules |
| `nm-applet` **not** running | Waybar's `network` module already shows wifi; the applet was a duplicate red tray icon | Some default autostart can re‑add it |

## Known failure modes & how to diagnose

### 1. Background app icons (Discord etc.) missing from the bar

    busctl --user list | grep StatusNotifierWatcher

If the watcher's PID belongs to `kded6` instead of `waybar`, kded6 won the race.

**Fix:** kill kded6, restart Waybar. Already automated in `hyprland.conf`:

    exec-once = pkill -f kded6; waybar -c ~/.config/waybar/config-macos -s ~/.config/waybar/style-macos.css

If a tray app was already running when the swap happened, **restart that app** so
it re‑registers with the new watcher (apps only register once at launch).

### 2. Icons are missing / wrong / boxes

    fc-list | grep -i 'jetbrains mono nerd'

Empty output = font missing.

**Fix:**

    sudo pacman -S --noconfirm ttf-jetbrains-mono-nerd
    pkill -SIGUSR2 waybar

### 3. Bar has no blur / Hyprland reports `Config error … invalid field blur`

Check:

    hyprctl configerrors

In Hyprland 0.54+ the syntax is space‑separated and `ignorezero`/`ignorealpha`
are no longer valid layer rules. The line in `hyprland.conf` must be exactly:

    layerrule = blur waybar

### 4. WiFi icon shows red / appears far‑right of the bar

That's `nm-applet --indicator` running as a duplicate tray icon. The Waybar
`network` module already covers wifi. Make sure `nm-applet` is **not** in
`hyprland.conf`'s `exec-once` list.

    pkill nm-applet

## File map

    ~/.config/hypr/hyprland.conf                       — kded6 kill + waybar launch + layerrule blur
    ~/.config/waybar/config-macos                      — modules, formats (Pango markup), pill bars
    ~/.config/waybar/style-macos.css                   — visual theme (Linear/Vercel palette)
    ~/.config/waybar/scripts/pillbar.sh                — generic 8‑segment pill bar generator
    ~/.config/waybar/scripts/audio-pill.sh             — audio module (icon + pill bar, scroll volume)
    ~/.config/waybar/scripts/gpu-monitor.sh            — GPU module (pill bar, color by load)
    ~/.config/waybar/scripts/doctor.sh                 — auto‑repair script
    ~/.config-backups/*_waybar-hypr-working.tar.gz     — dated snapshots of the above

## Restore from snapshot

    cd ~
    ls .config-backups/                                # pick the newest
    tar -xzf .config-backups/<file>.tar.gz
    hyprctl reload && pkill -SIGUSR2 waybar

## Make a new snapshot (after you've made changes you like)

    bash ~/.config/waybar/scripts/snapshot.sh
