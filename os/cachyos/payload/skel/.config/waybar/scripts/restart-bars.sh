#!/usr/bin/env bash
# restart-bars.sh — relaunch BOTH waybar instances:
#   1. the top bar        (config-macos   / style-macos.css)
#   2. the left sidebar   (config-sidebar / style-sidebar.css)  ← workspaces + window icons
# Run it from the graphical session (hyprctl dispatch exec -- …), not from a
# bare agent shell, so the bars inherit WAYLAND_DISPLAY.
set -u

LOGDIR="${XDG_RUNTIME_DIR:-/tmp}/waybar-logs"
mkdir -p "$LOGDIR"

killall waybar 2>/dev/null
sleep 0.4

waybar -c "$HOME/.config/waybar/config-macos"   -s "$HOME/.config/waybar/style-macos.css"   >>"$LOGDIR/topbar.log"    2>&1 &
waybar -c "$HOME/.config/waybar/config-sidebar" -s "$HOME/.config/waybar/style-sidebar.css" >>"$LOGDIR/sidebar.log"  2>&1 &

exit 0
