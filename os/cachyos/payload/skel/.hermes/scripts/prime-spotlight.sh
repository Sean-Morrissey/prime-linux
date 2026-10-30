#!/usr/bin/env bash
# Prime Spotlight launcher — what the Super+Space bind runs.
#
# One instance at a time: pressing the key again while the box is open restarts
# it rather than stacking overlays (the old one is killed, and the bracket in the
# pattern keeps this script from matching its own command line).
#
# stdout/stderr go to $XDG_RUNTIME_DIR/prime-spotlight.out, so a box that fails
# to appear can be explained ("closed after 0.2s" / a traceback) instead of just
# being invisible.
set -u

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
        [ -S "$sock" ] || continue
        WAYLAND_DISPLAY="$(basename "$sock")"; export WAYLAND_DISPLAY
        break
    done
fi

OUT="${XDG_RUNTIME_DIR}/prime-spotlight.out"
SCRIPT="@HOME@/.hermes/scripts/prime-spotlight.py"

pkill -f "prime-[s]potlight.py" 2>/dev/null && sleep 0.08

{
    echo "--- $(date '+%F %T') launching (WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset})"
    # PRIME_SPOTLIGHT_ARGS lets the headless modes (--selftest/--query) ride the
    # real launcher, so its env discovery and logging can be tested without a
    # single pixel appearing on screen.
    exec /usr/bin/python3 "$SCRIPT" ${PRIME_SPOTLIGHT_ARGS:-}
} >>"$OUT" 2>&1 &
