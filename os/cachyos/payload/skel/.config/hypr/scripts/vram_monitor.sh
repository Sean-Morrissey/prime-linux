#!/usr/bin/env bash
# RX 9060 XT VRAM Monitor — uses sysfs (rocm-smi not available on RDNA4)

vram_used=$(cat /sys/class/drm/card1/device/mem_info_vram_used 2>/dev/null)
vram_total=$(cat /sys/class/drm/card1/device/mem_info_vram_total 2>/dev/null)

if [ -z "$vram_used" ] || [ -z "$vram_total" ]; then
    echo "N/A"
    exit 0
fi

used_gb=$(echo "scale=1; $vram_used / 1073741824" | bc)
total_gb=$(echo "scale=1; $vram_total / 1073741824" | bc)
percent=$(( (vram_used * 100) / vram_total ))

echo "${used_gb}G / ${total_gb}G (${percent}%)"
