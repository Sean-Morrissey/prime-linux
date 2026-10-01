#!/usr/bin/env bash

# snap.sh - A simple script to simulate Windows-like Aero Snap for Hyprland floating windows

DIRECTION=$1

# First, ensure the active window is floating so we can position it exactly
hyprctl dispatch setfloating ""

case $DIRECTION in
    left)
        # Move to top left (relative to active monitor)
        hyprctl dispatch movewindowpixel "exact 0 0,activewindow"
        # Resize to left half
        hyprctl dispatch resizewindowpixel "exact 50% 100%,activewindow"
        ;;
    right)
        # Move to top right
        hyprctl dispatch movewindowpixel "exact 50% 0,activewindow"
        # Resize to right half
        hyprctl dispatch resizewindowpixel "exact 50% 100%,activewindow"
        ;;
    up)
        # Move to top
        hyprctl dispatch movewindowpixel "exact 0 0,activewindow"
        # Resize to top half
        hyprctl dispatch resizewindowpixel "exact 100% 50%,activewindow"
        ;;
    down)
        # Move to bottom
        hyprctl dispatch movewindowpixel "exact 0 50%,activewindow"
        # Resize to bottom half
        hyprctl dispatch resizewindowpixel "exact 100% 50%,activewindow"
        ;;
esac
