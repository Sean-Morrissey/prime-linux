#!/usr/bin/env bash
# Shared helpers for Prime hold-to-talk (Super+R).
#
#   press   -> prime-ptt-down.sh : start recording, show the indicator, hush
#                                  any reply that is being read aloud
#   release -> prime-ptt-up.sh   : stop, transcribe locally, submit the text
#                                  into the DESKTOP app's live session
#
# The desktop app is the ONLY agent process. Its backend runs the turn, so both
# the transcript and the agent's work appear in the chat window @USER@ is
# watching, and spoken replies come from the app's own "read replies aloud".
#
# NEVER reintroduce a second agent process on the same session: the old design
# drove a Hermes CLI inside tmux "prime-voice", which fought the desktop app for
# the session ("another Hermes process is using this session") and split /
# doubled every voice turn.
set -u

export PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls "${XDG_RUNTIME_DIR}/hypr/" 2>/dev/null | head -1)}"

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_REPO="${HOME}/.hermes/hermes-agent"
VENV_PY="${HERMES_REPO}/venv/bin/python"
DESKTOP_BIN="${HERMES_REPO}/apps/desktop/release/linux-unpacked/Hermes"

# line 1 = wav path, line 2 = recorder pid
STATE_FILE="${XDG_RUNTIME_DIR}/prime-ptt.state"

# "He is still holding the key" heartbeat. Refreshed ~25x/second by the
# repeat-enabled press bind; the recorder ends the take when it goes stale, which
# is what makes release detection work even when Hyprland drops the key-up event.
HOLD_FILE="${XDG_RUNTIME_DIR}/prime-ptt.hold"
HOLD_TIMEOUT_MS=1000   # > the 600ms key-repeat delay, so repeats keep it fresh

ptt_touch_hold() {
  touch "$HOLD_FILE" 2>/dev/null || true
}

# State for the Waybar module (scripts/prime-voice.sh) and for post-mortems:
# "<kind> <epoch> [note]" — e.g. "sent 1789834590 hello there".
STATUS_FILE="${XDG_RUNTIME_DIR}/prime-ptt.status"
ptt_status() { # ptt_status <kind> [note]
  printf '%s %s %s\n' "$1" "$(date +%s)" "${2:-}" > "$STATUS_FILE" 2>/dev/null || true
}

# One notification bubble for the whole take: it is REPLACED (same id) at every
# stage, so the toast never stacks up — listening -> sent -> delivered.
PTT_NOTIFY_ID=5150

# One bubble for the whole take. swaync does NOT replace by id, so the id the
# daemon ACTUALLY assigned (notify-send -p) is remembered and reused: each new
# toast replaces the previous one, and ptt_close_notify drops it by that same id.
# Without this every stage left its own toast behind — @USER@ ended up staring at
# three "Listening" bubbles at once.
PTT_NOTIFY_ID_FILE="${XDG_RUNTIME_DIR}/prime-ptt.notifyid"

ptt_notify() { # ptt_notify <summary> <body> [expire_ms] [icon]
  command -v notify-send >/dev/null 2>&1 || return 0
  local prev="" assigned=""
  [ -f "$PTT_NOTIFY_ID_FILE" ] && prev="$(cat "$PTT_NOTIFY_ID_FILE" 2>/dev/null)"
  assigned="$(notify-send -p ${prev:+-r "$prev"} -t "${3:-2500}" ${4:+-i "$4"} "$1" "$2" 2>/dev/null)"
  if [ -n "$assigned" ]; then
    printf '%s' "$assigned" > "$PTT_NOTIFY_ID_FILE" 2>/dev/null || true
  fi
}

# Close the bubble outright (by the daemon's own id).
ptt_close_notify() {
  local id=""
  [ -f "$PTT_NOTIFY_ID_FILE" ] && id="$(cat "$PTT_NOTIFY_ID_FILE" 2>/dev/null)"
  [ -n "$id" ] || return 0
  if command -v gdbus >/dev/null 2>&1; then
    gdbus call --session --dest org.freedesktop.Notifications \
      --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.CloseNotification "$id" \
      >/dev/null 2>&1 || true
  fi
  rm -f "$PTT_NOTIFY_ID_FILE" 2>/dev/null || true
}

# One rotating log line per event, so a press that misbehaves is diagnosable
# after the fact (there is no terminal attached to a hotkey press).
PTT_LOG="${XDG_RUNTIME_DIR}/prime-ptt.log"
ptt_log() {
  printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$PTT_LOG" 2>/dev/null || return 0
  if [ "$(wc -l < "$PTT_LOG" 2>/dev/null || echo 0)" -gt 400 ]; then
    tail -200 "$PTT_LOG" > "${PTT_LOG}.tmp" 2>/dev/null && mv -f "${PTT_LOG}.tmp" "$PTT_LOG"
  fi
}

# Echo the desktop backend's port when it is up and answering; non-zero exit
# otherwise. The port is random per launch (serve --port 0), so read the one the
# app logged at boot and probe it rather than trusting the last line.
ptt_backend_port() {
  local log="${HOME}/.hermes/logs/desktop.log" port
  [ -r "$log" ] || return 1
  port="$(grep -o 'HERMES_BACKEND_READY port=[0-9]*' "$log" 2>/dev/null | tail -1 | cut -d= -f2)"
  [ -n "${port:-}" ] || return 1
  curl -s --max-time 2 -o /dev/null "http://127.0.0.1:${port}/" || return 1
  printf '%s' "$port"
}

# Sink-input indexes belonging to the desktop app (Chromium/Electron playback).
ptt_app_streams() {
  command -v pactl >/dev/null 2>&1 || return 0
  pactl -f json list sink-inputs 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for stream in data:
    props = stream.get("properties") or {}
    binary = str(props.get("application.process.binary") or "").lower()
    app = str(props.get("application.name") or "").lower()
    if binary in {"hermes", "chromium"} or app == "chromium":
        print(stream.get("index"))
' 2>/dev/null
}

# Talking while the user talks is the one thing that makes hold-to-talk feel
# broken: hush the app's playback for the duration of the take. Only the app's
# own streams are touched (Spotify, Chrome, the whiteboard keep playing).
ptt_set_app_mute() { # $1 = 1 mute | 0 unmute
  command -v pactl >/dev/null 2>&1 || return 0
  local idx
  for idx in $(ptt_app_streams); do
    pactl set-sink-input-mute "$idx" "$1" 2>/dev/null || true
  done
}
