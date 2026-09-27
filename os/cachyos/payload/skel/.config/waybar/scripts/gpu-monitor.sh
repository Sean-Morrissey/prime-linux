#!/usr/bin/env bash
# GPU load for the system cluster: percentage only, temp in the tooltip.
# The JSON class drives the colour in style-macos.css (normal / warning / critical).
usage_path="/sys/class/drm/card1/device/gpu_busy_percent"
temp_path="/sys/class/drm/card1/device/hwmon/hwmon1/temp1_input"

usage=0
temp=0
[[ -f "$usage_path" ]] && usage=$(<"$usage_path")
[[ -f "$temp_path" ]]  && temp=$(( $(<"$temp_path") / 1000 ))

if   (( usage >= 90 )); then cls="critical"
elif (( usage >= 75 )); then cls="warning"
else                        cls="normal"
fi

printf '{"text":"%s%%","class":"%s","tooltip":"GPU %s%%  ·  %s°C  ·  AMD RX 9060 XT"}\n' \
    "$usage" "$cls" "$usage" "$temp"
