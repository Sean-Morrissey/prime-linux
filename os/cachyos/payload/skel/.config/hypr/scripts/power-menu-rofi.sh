#!/usr/bin/env bash

# Prime OS Power Menu (Rofi)
# Style: Red/Black/Chrome

# Options
shutdown='󰐥 Shutdown'
reboot='󰜉 Reboot'
lock='󰌾 Lock'
suspend='󰤄 Suspend'
logout='󰍃 Logout'

# Rofi Command
rofi_cmd() {
    "$HOME/.config/prime/rofi-hint.sh" -dmenu -p 'Power' \
        -theme-str 'window {width: 250px; border: 2px; border-color: #ff0000; background-color: #1a1a1a;} listview {lines: 5;} element {padding: 8px; text-color: #ffffff;} element selected {background-color: #ff0000; text-color: #ffffff;}'
}

# Selection
chosen="$(echo -e "$shutdown\n$reboot\n$lock\n$suspend\n$logout" | rofi_cmd)"

case $chosen in
    $shutdown)
        systemctl poweroff
        ;;
    $reboot)
        systemctl reboot
        ;;
    $lock)
        hyprlock
        ;;
    $suspend)
        systemctl suspend
        ;;
    $logout)
        hyprctl dispatch exit
        ;;
esac
