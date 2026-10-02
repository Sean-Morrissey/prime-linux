#!/usr/bin/env bash
# Prime hold-to-talk — Super+R RELEASED: stop recording, transcribe, send.
#
# Usage: prime-ptt-up.sh [wav] [recorder-pid]
#   With no args it ends the take recorded in the state file (the normal path,
#   fired by Hyprland's `bindr = $mainMod, R`). prime-ptt-down.sh passes both
#   explicitly when a NEW press displaces a take whose release never arrived.
set -u
source "$(dirname "$0")/prime-ptt-common.sh"

if [ "$#" -ge 1 ]; then
  WAV="$1"
  PID="${2:-}"
  # Only clear the state file if it still points at THIS take — by the time we
  # run, down.sh may already have written a fresh one for the new take.
  if [ -f "$STATE_FILE" ] && [ "$(sed -n 1p "$STATE_FILE")" = "$WAV" ]; then
    rm -f "$STATE_FILE"
  fi
else
  [ -f "$STATE_FILE" ] || exit 0
  WAV="$(sed -n 1p "$STATE_FILE")"
  PID="$(sed -n 2p "$STATE_FILE")"
  rm -f "$STATE_FILE"
fi

# Un-hush the app right away: the next reply has to be audible.
ptt_set_app_mute 0

# arecord finalizes the WAV header on SIGINT — TERM/KILL can leave a headless
# file that STT refuses. The recorder writes its own pid into the state file, and
# the pkill catches it even if the state file raced (placeholder pid) — an orphan
# recorder would hold the mic and keep growing the WAV.
if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
  kill -INT "$PID" 2>/dev/null
  for _ in $(seq 1 30); do
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.1
  done
  kill -KILL "$PID" 2>/dev/null
fi
pkill -INT -f "prime-ptt-record.py $WAV" 2>/dev/null || true
sleep 0.2

if [ ! -s "$WAV" ]; then
  # A tap that captured nothing: he wanted the typing box, not a scolding.
  if [ -x "$HOME/.config/waybar/scripts/prime-bar-input.sh" ]; then
    setsid "$HOME/.config/waybar/scripts/prime-bar-input.sh" >/dev/null 2>&1 &
    ptt_status no-speech "tap — typing box"
    ptt_log "release: tap (no audio) — opened the Hermes text box"
    exit 0
  fi
  ptt_notify "⚠️ Nothing recorded" "Hold Super+R a moment longer" 2500
  ptt_status no-speech "no audio captured"
  ptt_log "release: no audio captured"
  exit 0
fi

# Immediate receipt: releasing must always produce visible feedback, even before
# transcription finishes (send.py replaces this with the outcome).
ptt_close_notify
ptt_notify "📤 Sent" "Transcribing…" 6000

# Peak level tells us, from the log alone, whether the mic actually carried
# audio — the difference between "you were quiet" and "capture is broken".
peak="$(ffmpeg -hide_banner -i "$WAV" -af volumedetect -f null - 2>&1 | grep -o 'max_volume: [^ ]*' | head -1)"
# No intermediate "sent" toast: the outcome bubble (send.py) is the only one that
# follows the listening bubble, so at most one toast is ever on screen.
ptt_log "release — transcribing $WAV (${peak:-level unknown})"
"$VENV_PY" "$SCRIPTS_DIR/prime-ptt-send.py" "$WAV"
status=$?
ptt_log "send finished (exit $status)"
rm -f "$WAV"
exit $status
