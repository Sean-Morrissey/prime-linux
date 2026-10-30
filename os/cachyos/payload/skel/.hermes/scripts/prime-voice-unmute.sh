#!/usr/bin/env bash
# Guard against a stuck "I can't hear you at all".
#
# The barge-in hushes the app's own playback when Super+R goes down, and the
# release path un-mutes it again. If a take ends badly (killed recorder, app
# restart mid-take, a release event that never lands) that mute can stick — and
# nothing else ever clears it, so replies go silent.
#
# Runs from a 5s systemd timer: whenever NO take is live, the app's stream must
# not be muted.
set -u

STATE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/prime-ptt.state"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
DUCK_STATE="$RUNTIME_DIR/prime-duck.json"

if [ -f "$STATE" ]; then
  pid="$(sed -n 2p "$STATE" 2>/dev/null)"
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    exit 0  # a take is live: a mute here is the intended barge-in
  fi
fi

# Same guard for the ducking: if a restore timer dies with the app (restarts do
# that), other audio would stay quiet for good. A duck older than two minutes is
# stale by definition — the longest reply clip is well under a minute.
if [ -f "$DUCK_STATE" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$DUCK_STATE" 2>/dev/null || echo 0) ))
  if [ "$age" -gt 120 ]; then
    /usr/bin/env python3 "${HOME}/.hermes/scripts/prime-duck.py" restore >/dev/null 2>&1 || true
  fi
fi

PS1=''  # keep the sourced helpers quiet
# shellcheck source=/dev/null
source "${HOME}/.hermes/scripts/prime-ptt-common.sh"

ptt_set_app_mute 0
exit 0
