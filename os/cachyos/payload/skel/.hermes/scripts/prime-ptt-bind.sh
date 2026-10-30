#!/usr/bin/env bash
# Instrumented entry point for every Prime hold-to-talk Hyprland bind.
#
#   prime-ptt-bind.sh press    -> start the take, or (on key repeat, while the
#                                 key is still held) refresh the hold heartbeat
#   prime-ptt-bind.sh release  -> R came up: stop + submit
#   prime-ptt-bind.sh superup  -> Super came up: stop + submit
#
# Why the heartbeat: Hyprland's release bind does not always fire for a
# modifier chord — it depends on which key registered first — so "did he let go"
# cannot rest on that event alone. The press bind carries the `e` (repeat) flag,
# so while the key is held it fires ~25x/second; pointing those repeats at a
# timestamp file gives the recorder an independent "still held" signal, and the
# take ends when that heartbeat stops (see prime-ptt-record.py --hold-file).
set -u
source "$(dirname "$0")/prime-ptt-common.sh"

LABEL="${1:-unknown}"

if [ "$LABEL" = "press" ] && [ -f "$STATE_FILE" ]; then
  # A take is already running: this is either a repeat (heartbeat) or a genuine
  # second press that we deliberately ignore. Refresh the heartbeat, stay quiet.
  ptt_touch_hold
  exit 0
fi

printf '%s bind fired: %s\n' "$(date '+%H:%M:%S')" "$LABEL" >> "${XDG_RUNTIME_DIR}/prime-ptt-bind.log" 2>/dev/null || true

case "$LABEL" in
  press) exec bash "$SCRIPTS_DIR/prime-ptt-down.sh" ;;
  *)     exec bash "$SCRIPTS_DIR/prime-ptt-up.sh" ;;
esac
