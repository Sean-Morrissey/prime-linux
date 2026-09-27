#!/usr/bin/env bash
# doctor.sh — check + repair the four known Waybar/Hyprland failure modes.
# Safe to re-run. Prints a brief report.
set -u

c_ok="\033[32m✓\033[0m"
c_fix="\033[33m→\033[0m"
c_err="\033[31m✗\033[0m"

say() { printf "%b %s\n" "$1" "$2"; }

# ─── 1. JetBrains Mono Nerd Font installed ───────────────────────
if fc-list | grep -qi 'jetbrainsmono nerd\|jetbrains mono nerd'; then
    say "$c_ok" "Font: ttf-jetbrains-mono-nerd present"
else
    say "$c_fix" "Font missing — installing ttf-jetbrains-mono-nerd"
    sudo pacman -S --noconfirm ttf-jetbrains-mono-nerd >/dev/null
    fc-cache -f >/dev/null
fi

# ─── 2. Waybar (not kded6) owns StatusNotifierWatcher ────────────
watcher_pid=$(busctl --user list 2>/dev/null \
    | awk '$1=="org.kde.StatusNotifierWatcher"{print $2; exit}')
if [[ -n "${watcher_pid}" ]] && ps -p "$watcher_pid" -o comm= 2>/dev/null | grep -q '^waybar$'; then
    say "$c_ok" "Tray watcher: owned by Waybar (PID $watcher_pid)"
else
    say "$c_fix" "Tray watcher not owned by Waybar — killing kded6 and restarting Waybar"
    pkill -f kded6 2>/dev/null || true
    pkill waybar 2>/dev/null || true
    sleep 1
    nohup waybar \
        -c "$HOME/.config/waybar/config-macos" \
        -s "$HOME/.config/waybar/style-macos.css" \
        >/tmp/waybar.log 2>&1 & disown
    say "$c_fix" "Restart any tray-only apps (Discord, etc.) so they re-register"
fi

# ─── 3. Hyprland layerrule for blur present and parses ───────────
if grep -qE '^layerrule[[:space:]]*=[[:space:]]*blur[[:space:]]+waybar' \
        "$HOME/.config/hypr/hyprland.conf"; then
    say "$c_ok" "Hyprland blur rule: present (correct space-separated syntax)"
else
    say "$c_fix" "Adding 'layerrule = blur waybar' to hyprland.conf"
    {
        echo ""
        echo "# Frosted-glass blur for waybar layer (added by doctor.sh)"
        echo "layerrule = blur waybar"
    } >> "$HOME/.config/hypr/hyprland.conf"
fi

errors=$(hyprctl configerrors 2>/dev/null | grep -c '^Config error' || true)
if [[ "$errors" -eq 0 ]]; then
    say "$c_ok" "Hyprland config: no errors"
else
    say "$c_err" "Hyprland config has $errors error(s) — run: hyprctl configerrors"
fi

# ─── 4. nm-applet not running (duplicate of network module) ──────
if pgrep -f 'nm-applet' >/dev/null; then
    say "$c_fix" "nm-applet running (duplicate tray icon) — killing"
    pkill -f nm-applet
else
    say "$c_ok" "nm-applet: not running"
fi
if grep -qE '^exec-once[[:space:]]*=[[:space:]]*nm-applet' \
        "$HOME/.config/hypr/hyprland.conf"; then
    say "$c_fix" "Removing nm-applet autostart from hyprland.conf"
    sed -i -E '/^exec-once[[:space:]]*=[[:space:]]*nm-applet/d' \
        "$HOME/.config/hypr/hyprland.conf"
fi

# ─── Final reload ────────────────────────────────────────────────
hyprctl reload >/dev/null 2>&1
pkill -SIGUSR2 waybar 2>/dev/null
echo
echo "Done. If the bar still looks wrong, restore the latest snapshot:"
echo "  ls ~/.config-backups/*waybar-hypr-working*.tar.gz"
echo "  tar -xzf <newest> -C ~"
