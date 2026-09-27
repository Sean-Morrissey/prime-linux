#!/usr/bin/env bash
# prime-snip — Snipping-Tool style capture for Hyprland.
#
#   prime-snip.sh [area|full|screen|window] [--no-menu] [--ask] [--board]
#
# area    drag to highlight a region (dimmed overlay, live dimensions)   [default]
# full    every monitor joined into one image
# screen  the monitor the pointer is on
# window  the focused window's own rectangle
#
# After the shot: it is on the clipboard, saved in ~/Pictures/Screenshots, and a
# small action sheet appears — Ask Prime about it, work it out on Prime's
# Whiteboard, annotate (swappy), copy, open the folder, or delete.
# --no-menu / --ask / --board skip the sheet (--ask and --board act at once).
set -u

MODE="area"
NO_MENU=0
ASK_NOW=0
BOARD_NOW=0
for arg in "$@"; do
  case "$arg" in
    area|full|screen|window) MODE="$arg" ;;
    --no-menu) NO_MENU=1 ;;
    --ask)     ASK_NOW=1; NO_MENU=1 ;;
    --board)   BOARD_NOW=1; NO_MENU=1 ;;
  esac
done

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[ -d "$RUNTIME" ] || RUNTIME="/run/user/$(id -u)"
export XDG_RUNTIME_DIR="$RUNTIME"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  WAYLAND_DISPLAY="$(ls "$RUNTIME" 2>/dev/null | grep -m1 '^wayland-[0-9]*$' || true)"
  [ -n "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY
fi
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  HYPRLAND_INSTANCE_SIGNATURE="$(ls "$RUNTIME/hypr" 2>/dev/null | head -1)"
  [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && export HYPRLAND_INSTANCE_SIGNATURE
fi

SAVE_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SAVE_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
SHOT="$SAVE_DIR/snip_${STAMP}.png"
TMP="/tmp/prime-snip-${STAMP}.png"
LOG="$RUNTIME/prime-snip.log"
log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOG" 2>/dev/null || true; }

need() { command -v "$1" >/dev/null 2>&1 || { notify-send -a "Prime Snip" "Missing tool: $1"; exit 1; }; }
need grim
need slurp
need wl-copy

geom=""
case "$MODE" in
  area)
    # Purple highlight border + dimmed surround, exactly the "drag a box" gesture.
    # Use slurp's DEFAULT output ("X,Y WxH"). Do NOT pass -f '%wx%h+%x+%y':
    # grim on this machine rejects that form with "invalid geometry", which made
    # every area snip die silently one step after the drag (2026-09-25).
    geom="$(slurp -b '#00000099' -c '#c084fcff' -w 2 2>/dev/null)" || exit 0
    [ -n "$geom" ] || exit 0
    log "area geom: $geom"
    grim -g "$geom" "$TMP" || {
      log "grim failed for geom '$geom'"
      notify-send -a "Prime Snip" "Capture failed" "grim rejected the region ($geom)"
      exit 1
    }
    ;;
  full)
    grim "$TMP" || exit 1
    ;;
  screen)
    mon="$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.x),\(.y) \(.width)x\(.height)"' 2>/dev/null)"
    [ -n "$mon" ] && [ "$mon" != "null" ] || mon=""
    if [ -n "$mon" ]; then grim -g "$mon" "$TMP" || exit 1; else grim "$TMP" || exit 1; fi
    ;;
  window)
    win="$(hyprctl activewindow -j | jq -r 'if (.at and .size) then "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])" else "" end' 2>/dev/null)"
    if [ -n "$win" ] && [ "$win" != "null" ]; then
      grim -g "$win" "$TMP" || exit 1
    else
      notify-send -a "Prime Snip" "No focused window"; exit 0
    fi
    ;;
esac

[ -s "$TMP" ] || { notify-send -a "Prime Snip" "Capture failed"; exit 1; }
mv -f "$TMP" "$SHOT"
wl-copy <"$SHOT"
log "captured $MODE -> $SHOT"

ask_hermes() {
  setsid "$HOME/.config/waybar/scripts/prime-bar-input.sh" --ask-shot "$SHOT" \
      >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# Same one-motion path, but the answer belongs on the whiteboard: no question box,
# straight to "work this out on Prime's Whiteboard" (prime-bar-input.sh --board-shot).
board_ask() {
  setsid "$HOME/.config/waybar/scripts/prime-bar-input.sh" --board-shot "$SHOT" \
      >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

if [ "$ASK_NOW" = "1" ]; then ask_hermes; exit 0; fi
if [ "$BOARD_NOW" = "1" ]; then board_ask; exit 0; fi

notify-send -a "Prime Snip" -i "$SHOT" -t 4000 \
  "Snip saved" "$(basename "$SHOT")  •  copied to clipboard"

if [ "$NO_MENU" = "1" ]; then exit 0; fi

choice="$(printf '%s\n' \
  "󰚩  Ask Prime about this" \
  "󰆏  Work it on the whiteboard" \
  "󰎞  Annotate (swappy)" \
  "󰆼  Copy again" \
  "󰉋  Open folder" \
  "󰩹  Delete" \
  | "$HOME/.config/prime/rofi-hint.sh" -dmenu -i -theme "$HOME/.config/rofi/prime-bar.rasi" -p "󰄄 snip" \
         -theme-str 'listview { lines: 6; }' \
         -theme-str 'entry { enabled: false; }')" || exit 0

case "$choice" in
  *"Ask Prime"*)   ask_hermes ;;
  *whiteboard*)    board_ask ;;
  *Annotate*)      command -v swappy >/dev/null 2>&1 && swappy -f "$SHOT" -o "$SHOT" ;;
  *"Copy again"*)  wl-copy <"$SHOT"; notify-send -a "Prime Snip" "Copied to clipboard" ;;
  *"Open folder"*) xdg-open "$SAVE_DIR" >/dev/null 2>&1 & ;;
  *Delete*)        rm -f "$SHOT"; notify-send -a "Prime Snip" "Snip deleted" ;;
esac
exit 0
