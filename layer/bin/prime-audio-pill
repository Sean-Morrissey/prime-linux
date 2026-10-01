#!/usr/bin/env bash
# Audio volume for the system cluster: level glyph + percentage.
# Clean monochrome readout (the CSS colours it); class drives the muted tint.
#
#   click         pavucontrol
#   right-click   mute toggle
#   scroll        ±5 %
read -r vol_raw muted < <(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null \
    | awk '{print int($2*100), ($3=="[MUTED]")?1:0}')
vol=${vol_raw:-0}
muted=${muted:-0}

if (( muted )); then
    glyph="󰝟"
    cls="muted"
else
    if   (( vol >= 66 )); then glyph="󰕾"
    elif (( vol >= 33 )); then glyph="󰖀"
    else                        glyph="󰕿"
    fi
    cls="normal"
fi

desc=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
    | awk -F'"' '/node.description/ {print $2; exit}')

tip="${desc:-Audio} · ${vol}%"
(( muted )) && tip="${tip} · muted"

printf '{"text":"%s  %s%%","class":"%s","tooltip":"%s"}\n' \
    "$glyph" "$vol" "$cls" "$tip"
