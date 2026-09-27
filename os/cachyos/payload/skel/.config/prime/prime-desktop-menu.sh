#!/usr/bin/env bash
# prime-desktop-menu.sh — opens the Prime context menu for the desktop itself.
# A wrapper because a Hyprland `bindm` rejects a command with arguments.
exec @HOME@/.config/prime/prime-context.sh desktop
