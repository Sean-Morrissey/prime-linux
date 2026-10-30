#!/usr/bin/env bash
# start both bars (synthetic fixture)
pkill -x waybar
waybar -c ~/.config/waybar/config -s ~/.config/waybar/style.css &
waybar --config ~/.config/waybar/config-sidebar --style ~/.config/waybar/style-sidebar.css &
