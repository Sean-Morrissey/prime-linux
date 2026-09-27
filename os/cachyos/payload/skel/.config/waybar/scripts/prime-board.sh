#!/usr/bin/env bash
# prime-board.sh — the whiteboard button's engine (waybar custom/whiteboard).
#
#   prime-board.sh            focus the board window, or open it beside his work
#   prime-board.sh toggle     same as default, but hides it when it owns the screen
#   prime-board.sh timeline   open the activity timeline (what he's been doing)
#   prime-board.sh clear      wipe the board (asks first, via rofi)
#   prime-board.sh status     one line: service + panel count + window state
#
# The board itself is Prime's Whiteboard (systemd --user prime-whiteboard.service,
# http://localhost:8777/) and lives in a real Chrome window, tiled beside the
# worksheet on whatever screen holds his homework — never fullscreen, never on
# top of the Hermes chat (see the prime-whiteboard skill for why).
set -u

BOARD_URL="http://localhost:8777/"
TITLE_MATCH="Prime's Whiteboard"
WB_PY="$HOME@STUDY_DIR@/whiteboard/wb.py"
CHROME="${PRIME_CHROME:-google-chrome-stable}"

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[ -d "$RUNTIME" ] || RUNTIME="/run/user/$(id -u)"
export XDG_RUNTIME_DIR="$RUNTIME"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  WAYLAND_DISPLAY="$(ls "$RUNTIME" 2>/dev/null | grep -m1 '^wayland-[0-9]*$' || true)"
  [ -n "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY
fi
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  HYPRLAND_INSTANCE_SIGNATURE="$(ls "$RUNTIME/hypr" 2>/dev/null | head -1 || true)"
  [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && export HYPRLAND_INSTANCE_SIGNATURE
fi

LOG="$RUNTIME/prime-board.log"
log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOG" 2>/dev/null || true; }
notify() { notify-send -a Prime -t "${2:-5000}" "󰆏 Whiteboard" "$1" >/dev/null 2>&1 || true; }

have_hypr() { command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; }

clients() { hyprctl clients -j 2>/dev/null; }

board_addr() { clients | jq -r --arg t "$TITLE_MATCH" \
  '.[] | select(.title | contains($t)) | .address' 2>/dev/null | head -1; }

board_ws() { clients | jq -r --arg t "$TITLE_MATCH" \
  '.[] | select(.title | contains($t)) | .workspace.id' 2>/dev/null | head -1; }

# The workspace his homework is on: @STUDY_PLATFORM@ tab or a LibreOffice worksheet wins.
work_ws() {
  clients | jq -r '
    [ .[] | select(
        (.title | test("@STUDY_PLATFORM@"; "i"))
        or (.class | test("libreoffice"))
      ) | select(.title | contains("Whiteboard") | not) | .workspace.id ] | .[0] // empty' 2>/dev/null
}

service_up() { systemctl --user is-active --quiet prime-whiteboard.service; }

start_service() {
  systemctl --user start prime-whiteboard.service >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8; do
    curl -sf -o /dev/null --max-time 1 "$BOARD_URL" && return 0
    sleep 0.4
  done
  return 1
}

open_board() {                                  # launch, then park it beside the work
  local ws before after
  ws="$(work_ws)"; [ -n "$ws" ] || ws="$(hyprctl activeworkspace -j 2>/dev/null | jq -r .id)"
  hyprctl dispatch exec -- "$CHROME" --new-window "$BOARD_URL" >/dev/null 2>&1 || true
  # Chrome reuses a running instance, so wait for the title rather than the process
  for _ in $(seq 1 20); do
    sleep 0.4
    after="$(board_addr)"
    [ -n "$after" ] && break
  done
  if [ -z "$after" ]; then
    log "no board window appeared"; notify "The board window did not open — try again"; return 1
  fi
  # focusmonitor does NOT steer a new Chrome window; move it explicitly (comma, no space)
  [ -n "$ws" ] && hyprctl dispatch movetoworkspacesilent "$ws,address:$after" >/dev/null 2>&1
  hyprctl dispatch focuswindow "address:$after" >/dev/null 2>&1
  log "board opened at $after on ws $ws"
  return 0
}

focus_board() {
  local addr; addr="$(board_addr)"
  [ -n "$addr" ] || return 1
  if [ "$(board_ws)" = "special:minimized" ]; then
    local ws; ws="$(work_ws)"; [ -n "$ws" ] || ws="$(hyprctl activeworkspace -j 2>/dev/null | jq -r .id)"
    hyprctl dispatch movetoworkspacesilent "$ws,address:$addr" >/dev/null 2>&1
  fi
  hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1
  log "focused board at $addr"
  return 0
}

case "${1:-show}" in
  show|toggle)
    service_up || { start_service || { notify "The whiteboard service is not responding — systemctl --user restart prime-whiteboard.service"; exit 1; }; }
    focus_board || open_board
    ;;
  timeline)
    command -v xdg-open >/dev/null && xdg-open "http://localhost:8777/activity" >/dev/null 2>&1 || \
      hyprctl dispatch exec -- "$CHROME" --new-window "http://localhost:8777/activity" >/dev/null 2>&1
    ;;
  clear)
    if command -v rofi >/dev/null 2>&1; then
      printf 'no\n' | rofi -dmenu -no-custom -i -theme "$HOME/.config/rofi/prime-menu.rasi" \
        -p "Clear the whiteboard?" -mesg "This wipes every panel. Use the ledger/notes if you want to keep the working." >/dev/null 2>&1
    fi
    python3 "$WB_PY" clear >/dev/null 2>&1
    notify "Board cleared."
    ;;
  status)
    printf 'service %s · ' "$(service_up && echo up || echo down)"
    python3 "$WB_PY" list 2>/dev/null | wc -l | awk '{printf "%s panel(s) · ", $1}'
    if [ -n "$(board_addr)" ]; then printf 'window open\n'; else printf 'window closed\n'; fi
    ;;
  *)
    printf 'usage: prime-board.sh [show|toggle|timeline|clear|status]\n' >&2; exit 2 ;;
esac
