#!/usr/bin/env bash
# pillbar.sh <percent> <color> — emits an 8-pill bar with N filled segments.
# Usage example: pillbar.sh 42 "#a7f3d0"
percent="${1:-0}"
color="${2:-#e4e4e7}"
dim="#3f3f46"
total=8

# Clamp 0..100
[[ $percent =~ ^[0-9]+$ ]] || percent=0
(( percent > 100 )) && percent=100
(( percent < 0 ))  && percent=0

filled=$(( (percent * total + 50) / 100 ))
(( filled > total )) && filled=$total

out=""
for ((i=0; i<total; i++)); do
    if (( i < filled )); then
        out+="<span color='${color}'>▰</span>"
    else
        out+="<span color='${dim}'>▰</span>"
    fi
done
printf "%s" "$out"
