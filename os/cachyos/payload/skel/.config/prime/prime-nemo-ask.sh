#!/usr/bin/env bash
# prime-nemo-ask.sh — "Ask Prime" for the file manager (nemo actions).
#
#   prime-nemo-ask.sh <path> [<path>...]   ask about the selected files/folders
#   prime-nemo-ask.sh --area               ask about a screen region (cursor)
#
# Wired to ~/.local/share/nemo/actions/*.nemo_action so Prime sits in the same
# right-click menu as Cut / Copy / Paste / New Folder — the Windows layout @USER@
# asked for, with Prime added.
set -u

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$RUNTIME"
[ -n "${WAYLAND_DISPLAY:-}" ] || export WAYLAND_DISPLAY="$(ls "$RUNTIME" 2>/dev/null | grep -m1 '^wayland-[0-9]*$' || echo wayland-1)"

PILL_PY="$HOME/.hermes/hermes-agent/venv/bin/python3"
BAR_PY="$HOME/.hermes/scripts/prime-bar.py"
CONTEXT="$HOME/.config/prime/prime-context.sh"

if [ "${1:-}" = "--area" ]; then
    exec "$CONTEXT" bar.snip --run ask_area
fi

[ "$#" -gt 0 ] || exit 0

describe() {                      # one line per path: size · type · where
    local p="$1" size type
    if [ -d "$p" ]; then
        size="$(du -sh "$p" 2>/dev/null | cut -f1)"
        printf '%s — folder (%s, %s items)' "$p" "${size:-?}" "$(find "$p" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)"
    else
        size="$(du -h "$p" 2>/dev/null | cut -f1)"
        type="$(file -b --mime-type "$p" 2>/dev/null)"
        printf '%s — %s (%s)' "$p" "${type:-unknown}" "${size:-?}"
    fi
}

body=""
img=""
for p in "$@"; do
    [ -e "$p" ] || continue
    body+="$(describe "$p")"$'\n'
    mime="$(file -b --mime-type "$p" 2>/dev/null || echo '')"
    if [ -z "$img" ] && [ -f "$p" ]; then
        case "$mime" in image/*) img="$p" ;; esac
    fi
done
[ -n "$body" ] || exit 0

count="$#"
[ "$count" -gt 1 ] && noun="these $count items" || noun="this file"
question="I right-clicked $noun in my file manager and chose Ask Prime:
$body
What is it, and what should I do with it?"

if [ -n "$img" ]; then
    setsid nohup "$PILL_PY" "$BAR_PY" ask "$question" --image "$img" >/dev/null 2>&1 &
else
    setsid nohup "$PILL_PY" "$BAR_PY" ask "$question" >/dev/null 2>&1 &
fi
disown 2>/dev/null || true
