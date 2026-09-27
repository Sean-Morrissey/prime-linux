#!/usr/bin/env bash
# macOS-Style Wallpaper Switcher for Hyprpaper

WALLPAPER_DIR="$HOME/.config/hypr/wallpapers"
WALLPAPERS=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.webp" \) -exec basename {} \;)

if [ -z "$1" ]; then
    CHOICE=$(echo "$WALLPAPERS" | "$HOME/.config/prime/rofi-hint.sh" -dmenu -i -p "󰸉 Wallpaper" -theme ~/.config/rofi/prime-spotlight.rasi)
else
    CHOICE="$1"
fi

[ -z "$CHOICE" ] && exit 0

SELECTED="$WALLPAPER_DIR/$CHOICE"

if [ -f "$SELECTED" ]; then
    hyprctl hyprpaper preload "$SELECTED" 2>/dev/null
    hyprctl hyprpaper wallpaper "@MONITOR_2@,$SELECTED" 2>/dev/null
    hyprctl hyprpaper wallpaper "@MONITOR_1@,$SELECTED" 2>/dev/null
    notify-send -i "$SELECTED" "Wallpaper Updated" "$CHOICE"
fi
