#!/usr/bin/env bash
# RETIRED (2026-09-19) — do NOT re-enable hermes-voice.service.
#
# This used to keep a second Hermes CLI warm inside tmux "prime-voice" as the
# push-to-talk target. Two agent processes on one session is what made voice
# unusable: the CLI printed "another Hermes process is using this session" and
# split/doubled every voice turn against the desktop app.
#
# The hotkey now records with arecord and submits into the DESKTOP app's own
# session — see prime-ptt-down.sh / prime-ptt-up.sh / prime-ptt-send.py.
# Left here only so the history is readable; safe to delete.
#
# Keeps a warm Hermes CLI session alive inside tmux so a system-wide hotkey
# (see prime-ptt.sh, bound to Super+R in Hyprland) can put the agent into
# listening mode instantly. The agent is already booted, so there is no
# process-start penalty on a hotkey press.
#
# Voice mode (/voice on) is kept enabled so the record key is live, and the
# wake word is intentionally OFF — Super+R is the trigger.
#
# Attach to watch/type:  tmux attach -t prime-voice     (detach: Ctrl-b d)
set -u

SESSION="prime-voice"
HERMES_BIN="${HOME}/.local/bin/hermes"
export PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

log() { printf '[prime-voice] %s\n' "$*"; }

voice_mode_on() {
  tmux capture-pane -t "$SESSION" -p 2>/dev/null | grep -qE "Voice mode|● REC|Transcribing"
}

# The status bar renders "🎤 Voice mode | TTS on  —  ctrl+o to record" only
# when spoken replies are enabled, so it is a reliable read of _voice_tts.
voice_tts_on() {
  tmux capture-pane -t "$SESSION" -p 2>/dev/null | grep -q "TTS on"
}

if ! command -v tmux >/dev/null 2>&1; then log "tmux not found"; exit 1; fi
if [ ! -x "$HERMES_BIN" ]; then log "hermes not found at $HERMES_BIN"; exit 1; fi

start_session() {
  tmux new-session -d -s "$SESSION" -x 120 -y 40 "$HERMES_BIN"
  log "started tmux session '$SESSION'"
}

if tmux has-session -t "$SESSION" 2>/dev/null; then
  if ! tmux list-panes -t "$SESSION" -F '#{pane_dead}' 2>/dev/null | grep -q '^0$'; then
    log "pane dead — rebuilding session"
    tmux kill-session -t "$SESSION" 2>/dev/null
    start_session
  else
    log "session '$SESSION' already live — supervising"
  fi
else
  start_session
fi

sleep 20   # let the CLI boot

# Keep voice mode enabled so the push-to-talk key is always live, and keep
# spoken replies on.  TTS is toggled with /voice tts, so it is only sent when
# the status bar says TTS is off — re-sending it blindly would turn it back off.
while tmux has-session -t "$SESSION" 2>/dev/null; do
  if ! voice_mode_on; then
    log "enabling voice mode"
    tmux send-keys -t "$SESSION" "/voice on" Enter
    sleep 3
  fi
  if voice_mode_on && ! voice_tts_on; then
    log "enabling TTS"
    tmux send-keys -t "$SESSION" "/voice tts" Enter
  fi
  sleep 30
done

log "session '$SESSION' ended — exiting for systemd restart"
exit 1
