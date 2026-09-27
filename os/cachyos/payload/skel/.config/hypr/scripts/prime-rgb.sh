#!/usr/bin/env bash
# PRIME OS - RGB Sync Script
# Synchronizes Mouse and PC to Slow Red Pulse

# 1. Sync Mouse (Logitech G203)
ratbagctl warbling-mara led 0 set mode breathing && \
ratbagctl warbling-mara led 0 set color ff0000 && \
ratbagctl warbling-mara led 0 set duration 5000

# 2. Sync PC Internals (OpenRGB)
# Note: Requires the kernel unlock in /etc/modprobe.d/i2c-piix4.conf
openrgb --mode breathing --color FF0000 --speed 20 > /dev/null 2>&1 &
