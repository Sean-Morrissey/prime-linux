#!/usr/bin/env bash
# snapshot.sh — tarball the current working Waybar + Hyprland config.
set -euo pipefail

stamp=$(date +%Y%m%d_%H%M%S)
out="$HOME/.config-backups/${stamp}_waybar-hypr-working.tar.gz"
mkdir -p "$HOME/.config-backups"

cd "$HOME"
tar -czf "$out" \
    .config/waybar/config-macos \
    .config/waybar/style-macos.css \
    .config/waybar/config-sidebar \
    .config/waybar/style-sidebar.css \
    .config/waybar/scripts/pillbar.sh \
    .config/waybar/scripts/audio-pill.sh \
    .config/waybar/scripts/gpu-monitor.sh \
    .config/waybar/scripts/updates-count.sh \
    .config/waybar/scripts/restart-bars.sh \
    .config/waybar/scripts/doctor.sh \
    .config/waybar/scripts/snapshot.sh \
    .config/waybar/scripts/prime-voice.sh \
    .config/waybar/scripts/prime-pill.py \
    .config/waybar/scripts/prime-bar-input.sh \
    .config/waybar/scripts/spotify-pill.py \
    .config/rofi/prime-bar.rasi \
    .config/waybar/RECOVERY.md \
    .config/prime/elements.json \
    .config/prime/prime-context.sh \
    .config/rofi/prime-menu.rasi \
    .config/hypr/hyprland.conf

printf "Snapshot saved: %s\n" "$out"
ls -1t "$HOME/.config-backups/"*waybar-hypr-working*.tar.gz | head -5
