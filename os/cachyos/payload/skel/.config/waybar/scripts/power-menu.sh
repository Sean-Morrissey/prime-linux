#!/usr/bin/env bash
# Power menu for the waybar power pill.
#
# Rebuilt 2026-09-25: the old ML4W-derived version force-SIGTERMed every
# Hyprland client before acting (losing whatever was open) and passed rofi
# 1.x / wrong wofi flags, so picking an entry looked like it did nothing.
# This one: rofi box themed like the rest of the bar, universal hint line,
# a Yes/No confirmation before anything that ends the session, and plain
# logind/systemd calls after it.
set -u

THEME="$HOME/.config/rofi/prime-bar.rasi"

pick() {  # pick <prompt> <hint> <item>...
    local prompt="$1" hint="$2"; shift 2
    if command -v rofi >/dev/null 2>&1; then
        printf '%s\n' "$@" | ROFI_HINT="$hint" \
            "$HOME/.config/prime/rofi-hint.sh" -dmenu -i -no-custom \
            -theme "$THEME" -p "$prompt"
    else
        printf '%s\n' "$@" | wofi --show dmenu --insensitive \
            --prompt "$prompt" --width 240 --height 260 --hide-search --matching fuzzy
    fi
}

confirm() {  # confirm "restart" → 0 if the user picked Yes
    local what="$1" ans
    ans=$(pick "Really $what?" "↑↓ move  ·  Enter confirm  ·  Esc cancel" "Yes" "No")
    [ "$ans" = "Yes" ]
}

choice=$(pick "󰐥 power" \
    "↑↓ move  ·  Enter pick  ·  Esc cancel  ·  nothing happens until you confirm" \
    "Lock Screen" "Suspend" "Shut Down" "Restart" "Log Out" "Cancel") || exit 0

case "$choice" in
    "Lock Screen") hyprlock ;;
    "Suspend")     systemctl suspend ;;
    "Shut Down")   confirm "shut down" && systemctl poweroff ;;
    "Restart")     confirm "restart"   && systemctl reboot ;;
    "Log Out")     confirm "log out"   && hyprctl dispatch exit ;;
    *)             exit 0 ;;
esac
