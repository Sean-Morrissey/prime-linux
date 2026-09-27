#!/usr/bin/env bash
# Click target for the Hermes waybar pill (custom/hermes).
#
#   prime-bar-input.sh                type a prompt -> chat on screen
#   prime-bar-input.sh --new          type a prompt -> a fresh chat
#   prime-bar-input.sh --popup        show the last reply (read-only)
#   prime-bar-input.sh --screen       drag a region, then ask about it
#   prime-bar-input.sh --screen-full  whole desktop, then ask about it
#   prime-bar-input.sh --ask-shot P   ask about an existing capture (prime-snip)
#   prime-bar-input.sh --board-shot P work an existing capture out on the whiteboard
#
# Waybar has no text-entry widget, so the input is a slim rofi line anchored just
# under the bar. Submitting is detached: rofi closes instantly and the pill spins
# while prime-bar.py does the routing and watches for the reply.
set -u

MODE="ask"
case "${1:-}" in
  --new)         MODE="new" ;;
  --popup)       MODE="popup" ;;
  --screen)      MODE="screen" ;;
  --screen-full) MODE="screen_full" ;;
  --ask-shot)    MODE="ask_shot" ;;
  --board-shot)  MODE="board_shot" ;;
esac
GIVEN_SHOT="${2:-}"

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[ -d "$RUNTIME" ] || RUNTIME="/run/user/$(id -u)"
export XDG_RUNTIME_DIR="$RUNTIME"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  WAYLAND_DISPLAY="$(ls "$RUNTIME" 2>/dev/null | grep -m1 '^wayland-[0-9]*$' || true)"
  [ -n "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY
fi

PILL_PY="$HOME/.hermes/hermes-agent/venv/bin/python3"
BAR_PY="$HOME/.hermes/scripts/prime-bar.py"
THEME="$HOME/.config/rofi/prime-bar.rasi"
LOG="$RUNTIME/prime-bar-input.log"

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOG" 2>/dev/null || true; }
notify() { notify-send -a Prime -t "${3:-5000}" "$1" "$2" >/dev/null 2>&1 || true; }
launch_bg() { setsid nohup "$@" >/dev/null 2>>"$LOG" & disown 2>/dev/null || true; }

if [ ! -x "$PILL_PY" ] || [ ! -f "$BAR_PY" ]; then
  notify "⚠️ Prime bar" "Backend missing: $BAR_PY"
  log "backend missing"
  exit 1
fi

command -v rofi >/dev/null 2>&1 || { notify "⚠️ Prime bar" "rofi is not installed"; exit 1; }

# ── text entry ──────────────────────────────────────────────────────────────
# prime-entry.py: a GTK box with a real right-click menu (Cut/Copy/Paste/Select
# All) and a paste path that works on Wayland. rofi's entry has neither — its
# 2.0.0 Wayland backend asks for "text/plain" while modern apps offer only
# "text/plain;charset=utf-8", so Ctrl+V into a rofi box silently inserts
# nothing. Keep rofi as the fallback for a machine without GTK bindings.
ENTRY="$HOME/.config/waybar/scripts/prime-entry.py"
entry_text() {  # $1 = prompt; prints the text, non-zero if cancelled
  if [ -x "$ENTRY" ] && /usr/bin/python3 -c 'import gi' >/dev/null 2>&1; then
    /usr/bin/python3 "$ENTRY" -p "$1"
  else
    "$HOME/.config/prime/rofi-hint.sh" -dmenu -i -theme "$THEME" -p "$1" \
         -theme-str 'listview { lines: 0; }' </dev/null
  fi
}

# ── read-only: last reply ───────────────────────────────────────────────────
if [ "$MODE" = "popup" ]; then
  reply="$("$PILL_PY" "$BAR_PY" last 2>>"$LOG")"
  if [ -z "${reply//[[:space:]]/}" ]; then
    notify "Prime bar" "No reply yet — click the pill and type something."
    exit 0
  fi
  printf '%s\n' "$reply" | fold -s -w 94 | \
    "$HOME/.config/prime/rofi-hint.sh" -dmenu -no-custom -i -theme "$THEME" -p "last reply" \
         -theme-str 'listview { lines: 16; }' \
         -theme-str 'entry { enabled: false; cursor: default; }' >/dev/null
  exit 0
fi

# ── ask about an existing capture (prime-snip's action sheet) ────────────────
if [ "$MODE" = "ask_shot" ]; then
  if [ ! -s "${GIVEN_SHOT:-}" ]; then
    notify "⚠️ Prime bar" "No screenshot to ask about"
    exit 1
  fi
  # Blank box on purpose: type the question, or just press Enter and let
  # prime-bar.py ask its default ("What am I looking at here?"). Esc cancels.
  text="$(entry_text "󰄄 ask about screen")"
  rc=$?
  if [ $rc -ne 0 ]; then
    log "ask-shot cancelled (Esc) — shot kept at $GIVEN_SHOT"
    notify "Prime bar" "Screenshot saved: $(basename "$GIVEN_SHOT")"
    exit 0
  fi
  log "ask-shot: '${text}' ($GIVEN_SHOT)"
  launch_bg "$PILL_PY" "$BAR_PY" ask "$text" --new --image "$GIVEN_SHOT"
  exit 0
fi

# ── whiteboard an existing capture (prime-snip's whiteboard action) ─────────
# One motion, no question box: the snip IS the question. prime-snip.sh calls this
# from both its action sheet and `Super+Alt+W` (snip --board).
if [ "$MODE" = "board_shot" ]; then
  if [ ! -s "${GIVEN_SHOT:-}" ]; then
    notify "⚠️ Prime bar" "No screenshot to work out on the board"
    exit 1
  fi
  BOARD_PROMPT="Work this out on Prime's Whiteboard: read the problem from the \
screenshot I attached, then write the working to the board with wb.py (python3 \
~@STUDY_DIR@/whiteboard/wb.py — skill: prime-whiteboard). Panel 1 restates \
the problem, then one panel per step in plain words, last panel = the answer \
boxed plus the check. The board window is already on screen beside my work and \
reloads itself — never tell me to refresh it. One line back here when it is up."

  # Board first: it live-reloads, so the working appears in a window already
  # sitting beside his homework instead of popping open after the fact.
  launch_bg "$HOME/.config/waybar/scripts/prime-board.sh" show
  log "board-shot: $GIVEN_SHOT"
  launch_bg "$PILL_PY" "$BAR_PY" ask "$BOARD_PROMPT" --new --image "$GIVEN_SHOT"
  notify "󰆏 Whiteboard" "Working it out on the board — opening beside your work."
  exit 0
fi

# ── screen: capture, then ask about the capture ─────────────────────────────
if [ "$MODE" = "screen" ] || [ "$MODE" = "screen_full" ]; then
  command -v grim >/dev/null 2>&1 || { notify "⚠️ Prime bar" "grim is not installed"; exit 1; }
  SHOT_DIR="$HOME/Pictures/Screenshots"
  mkdir -p "$SHOT_DIR"
  SHOT="$SHOT_DIR/ask_hermes_$(date +%Y%m%d_%H%M%S).png"

  if [ "$MODE" = "screen" ]; then
    geom="$(slurp -b '#00000099' -c '#c084fcff' -w 2 2>/dev/null)" || exit 0   # Esc = cancel
    [ -n "$geom" ] || exit 0
    grim -g "$geom" "$SHOT" || { notify "⚠️ Prime bar" "Capture failed"; exit 1; }
  else
    grim "$SHOT" || { notify "⚠️ Prime bar" "Capture failed"; exit 1; }
  fi
  log "captured $SHOT"

  # Blank box on purpose (no prefill): Enter alone asks the default question.
  text="$(entry_text "󰄄 ask about screen")"
  rc=$?

  if [ $rc -ne 0 ]; then
    log "screen ask cancelled (Esc) — shot kept at $SHOT"
    notify "Prime bar" "Screenshot saved: $(basename "$SHOT")"
    exit 0
  fi

  log "screen ask: '${text}' ($SHOT)"
  launch_bg "$PILL_PY" "$BAR_PY" ask "$text" --new --image "$SHOT"
  exit 0
fi

# ── type a prompt ───────────────────────────────────────────────────────────
PROMPT="󰚩 Prime"
[ "$MODE" = "new" ] && PROMPT="󰚩 New chat"

text="$(entry_text "$PROMPT")"
rc=$?

if [ $rc -ne 0 ] || [ -z "${text//[[:space:]]/}" ]; then
  log "cancelled (rc=$rc)"
  exit 0
fi

log "typed: $text"

# Detached so the box's return does not tie the submit to the click handler.
# Every ask from the bar starts its own chat: the question came from outside the app,
# so the answer should be its own thing to read, not appended to whatever chat
# happened to be focused — and it means the window can be pointed at it cleanly.
launch_bg "$PILL_PY" "$BAR_PY" ask "$text" --new
exit 0
