#!/usr/bin/env bash
# Build three mastering variants of the same line so @USER@ can pick the direction
# by ear instead of me guessing. Outputs three mp3s for inline playback.
set -u
LINE="Hey, this is how your assistant sounds. Pick the one that feels right in the mix."
OUT=@HOME@/.hermes/cache/prime-ab
mkdir -p "$OUT"
printf '%s\n' "$LINE" > "$OUT/line.txt"
RAW="$OUT/raw.mp3"
EDGE="$HOME/.hermes/hermes-agent/venv/bin/edge-tts"
"$EDGE" -f "$OUT/line.txt" -v en-US-BrianNeural --write-media "$RAW" >/dev/null 2>&1

V=1.8
# A — broadcast (current pro chain)
ffmpeg -y -loglevel error -i "$RAW" -af \
 "volume=$V,highpass=f=80,bass=g=2:f=110:w=0.6,equalizer=f=250:t=q:w=1:g=-2,equalizer=f=3500:t=q:w=1:g=1.5,treble=g=1.5:f=9000:w=0.5,acompressor=threshold=0.125:ratio=3:attack=10:release=100:makeup=1.2,aecho=0.8:1.0:12|24|38|55|80:0.18|0.14|0.10|0.07|0.05,alimiter=limit=0.891" \
 "$OUT/A-broadcast.mp3"

# B — warm & round (less presence, more low-mid body, softer, roomier)
ffmpeg -y -loglevel error -i "$RAW" -af \
 "volume=$V,highpass=f=80,bass=g=3:f=140:w=0.7,equalizer=f=250:t=q:w=1:g=-1,equalizer=f=3500:t=q:w=1:g=0.5,acompressor=threshold=0.2:ratio=2:attack=15:release=130:makeup=1.2,aecho=0.8:1.0:16|32|48|72|96:0.22|0.18|0.14|0.10|0.07,alimiter=limit=0.891" \
 "$OUT/B-warm.mp3"

# C — smooth & airy (minimal, bright, gentle, a touch of space)
ffmpeg -y -loglevel error -i "$RAW" -af \
 "volume=1.6,highpass=f=90,equalizer=f=250:t=q:w=1:g=-1.5,treble=g=2:f=7000:w=0.6,acompressor=threshold=0.15:ratio=2:attack=20:release=150:makeup=1.1,aecho=0.8:1.0:20|40|70:0.15|0.10|0.06,alimiter=limit=0.891" \
 "$OUT/C-airy.mp3"

ls -la "$OUT"/*.mp3
