#!/usr/bin/env bash
# Prime hold-to-talk — Super+R PRESSED: start recording.
#
# Starts the take, puts ONE live "listening" bubble on screen, and hushes any
# reply the app is currently reading aloud (talking over the user is what makes
# hold-to-talk feel broken).
#
# The take ends on key release (prime-ptt-up.sh) or, if that release is lost,
# after SILENCE_MS of post-speech quiet — the recorder (prime-ptt-record.py)
# watches the level and sends itself when @USER@ stops talking. A pause shorter
# than that window can never cut him off mid-sentence.
set -u
source "$(dirname "$0")/prime-ptt-common.sh"

MAX_TAKE=300     # seconds; hard cap on one take (safety only)
SILENCE_MS=0     # 0 = release-only. He was explicit: the take must not end
                 # because he stopped talking, only because he let go of Super+R.
                 # (The release bind carries the ignore-mods flag now, which is
                 # what makes that event land regardless of which key he lets go
                 # of first — see hyprland.conf.)

# BARGE-IN, FIRST THING: the moment he presses Super+R he may be interrupting a
# reply that is being read aloud, so the app's playback is hushed before anything
# else — ahead of the state checks, the backend probe and the notifications, all
# of which cost time he would hear as "it kept talking over me". (Un-muted again
# in prime-ptt-up.sh, and by the TTS path itself on every new utterance.)
ptt_set_app_mute 0
ptt_set_app_mute 1

# He presses the key only once he has read the reply, so nothing is left to say:
# bring the ducked music straight back up instead of leaving it quiet for the rest
# of a clip he is no longer listening to.
if [ -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/prime-duck.json" ]; then
  /usr/bin/env python3 "${HOME}/.hermes/scripts/prime-duck.py" restore >/dev/null 2>&1 || true
fi

# Stop the reply mid-sentence, for real: prime-speak.py plays the voice itself now,
# so killing its player is an instant, clean cut (no app hush left behind).
if [ -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/prime-speak.player.pid" ]; then
  kill "$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/prime-speak.player.pid" 2>/dev/null)" 2>/dev/null || true
  rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/prime-speak.player.pid"
fi

if [ -f "$STATE_FILE" ]; then
  pid="$(sed -n 2p "$STATE_FILE" 2>/dev/null)"
  age=$(( $(date +%s) - $(stat -c %Y "$STATE_FILE" 2>/dev/null || echo 0) ))
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null && [ "$age" -lt $((MAX_TAKE + 20)) ]; then
    # A live take: do NOT finalize it — @USER@ may still be talking, and a submit
    # here is exactly what "it delivered before I was done" felt like. It ends
    # on its own (silence or the cap).
    ptt_log "press ignored — take already live (pid $pid, ${age}s old)"
    exit 0
  fi
  ptt_log "reclaiming dead take (pid ${pid:-none}, ${age}s old)"
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" 2>/dev/null
    sleep 0.3
    kill -KILL "$pid" 2>/dev/null
  fi
  rm -f "$(sed -n 1p "$STATE_FILE" 2>/dev/null)" "$STATE_FILE"
fi

# The desktop app is the one and only agent surface — bring it up if needed so a
# hotkey press before the app is running still lands somewhere visible.
if ! ptt_backend_port >/dev/null; then
  ptt_log "desktop backend unreachable — launching the app"
  ptt_notify "Prime" "Starting the Hermes desktop app…"
  hyprctl dispatch exec -- "$DESKTOP_BIN" >/dev/null 2>&1
  for _ in $(seq 1 20); do
    sleep 1
    ptt_backend_port >/dev/null && break
  done
fi

WAV="${XDG_RUNTIME_DIR}/prime-ptt-$(date +%s).wav"
rm -f "$WAV"

# Listening indicator lives in Waybar now (scripts/prime-voice.sh); the app is
# already hushed at the top of this script, so just clear stale toasts and mark
# the state.
ptt_close_notify
ptt_status listening

# Placeholder state so a very fast release always finds a claimable take; the
# recorder rewrites it with its own pid as soon as it starts.
printf '%s\n%s\n' "$WAV" "" > "$STATE_FILE"
# Start the heartbeat fresh: the repeat-enabled press bind refreshes it while the
# key is held, and the recorder ends the take when it goes stale.
rm -f "$HOLD_FILE"
ptt_touch_hold

(
  "$VENV_PY" "$SCRIPTS_DIR/prime-ptt-record.py" "$WAV" \
    --state-file "$STATE_FILE" \
    --silence-ms "$SILENCE_MS" \
    --no-speech-timeout 25 \
    --hold-file "$HOLD_FILE" \
    --hold-timeout-ms "$HOLD_TIMEOUT_MS" \
    --max-seconds "$MAX_TAKE" >> "$PTT_LOG" 2>&1

  # The recorder ended by itself (quiet or no speech). Submit unless the release
  # path already claimed the take.
  if [ -f "$STATE_FILE" ] && [ "$(sed -n 1p "$STATE_FILE" 2>/dev/null)" = "$WAV" ]; then
    bash "$SCRIPTS_DIR/prime-ptt-up.sh" "$WAV"
  fi
) &
disown 2>/dev/null || true

ptt_log "recording started ($WAV, silence-stop ${SILENCE_MS}ms)"
