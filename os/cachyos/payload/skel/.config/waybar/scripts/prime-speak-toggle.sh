#!/usr/bin/env bash
# Waybar button (next to "snip"): silence / un-silence Prime's spoken replies.
#
# Gates prime-speak.py, the service that reads assistant messages aloud. The
# flag is persistent, so "off" survives a reboot; the mic listener
# (hermes-voice.service) is deliberately NOT touched - this is output only.
set -u

FLAG="${HOME}/.hermes/prime-speak.muted"
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PIDFILE="$RUNTIME/prime-speak.player.pid"

if [ -f "$FLAG" ]; then
  rm -f "$FLAG"
  notify-send -r 9910 "🔊 Voice on" "Prime will read replies aloud again." 2>/dev/null &
else
  touch "$FLAG"
  # Cut anything already mid-sentence so muting is instant.
  if [ -f "$PIDFILE" ]; then
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
  pkill -f 'prime-sidechain\.py' 2>/dev/null || true
  notify-send -r 9910 "🔇 Voice off" "Prime stays quiet. Mic still listens." 2>/dev/null &
fi
exit 0
