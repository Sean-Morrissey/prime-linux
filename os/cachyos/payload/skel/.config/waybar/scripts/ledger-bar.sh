#!/usr/bin/env bash
# Click target for the ledger pill (custom/ledger).
#
#   ledger-bar.sh add     type a note for Prime (goes in as "- [?] ...")
#   ledger-bar.sh paste   put the clipboard in as a note: text, image, file(s), link
#   ledger-bar.sh attach  pick file(s)/photo(s) with a file dialog, then note them
#   ledger-bar.sh copy    copy the ledger text to the clipboard
#   ledger-bar.sh view    read the ledger in a rofi list (read-only)
#   ledger-bar.sh calendar  due dates + scheduled events (interactive calendar)
#   ledger-bar.sh menu    context menu (paste / copy / note / attach / read / send / calendar)
#   ledger-bar.sh flush   send anything queued to WhatsApp right now
#
# Waybar has no text-entry widget, so input is a rofi line anchored under the
# bar — same shape as prime-bar-input.sh. Nothing here ever asks rofi to read
# the clipboard: rofi 2.0.0 on Wayland requests "text/plain" while modern apps
# (Chrome, GTK) offer only "text/plain;charset=utf-8", so Ctrl+V into a rofi box
# silently inserts nothing. Clipboard content is read with wl-paste instead.
set -u

MODE="${1:-menu}"
shift || true

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[ -d "$RUNTIME" ] || RUNTIME="/run/user/$(id -u)"
export XDG_RUNTIME_DIR="$RUNTIME"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  WAYLAND_DISPLAY="$(ls "$RUNTIME" 2>/dev/null | grep -m1 '^wayland-[0-9]*$' || true)"
  [ -n "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY
fi

NOTE="$HOME/.hermes/scripts/ledger-note.sh"
FLUSH="$HOME/.hermes/scripts/ledger-flush.sh"
LEDGER="$HOME/.hermes/ledger.md"
CALENDAR="$HOME/.config/waybar/scripts/ledger-calendar.py"
ATTACH="$HOME/.hermes/attachments"
THEME="$HOME/.config/rofi/prime-bar.rasi"
LOG="$RUNTIME/ledger-bar.log"

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOG" 2>/dev/null || true; }
notify() { notify-send -a Ledger -t "${3:-4000}" "$1" "$2" >/dev/null 2>&1 || true; }
have() { command -v "$1" >/dev/null 2>&1; }

command -v rofi >/dev/null 2>&1 || { notify "⚠️ Ledger" "rofi is not installed"; exit 1; }

# ── text entry ──────────────────────────────────────────────────────────────
# prime-entry.py is a GTK box with a real right-click menu (Cut/Copy/Paste/
# Select All) and a paste path that works on Wayland; rofi's entry has neither
# (its 2.0.0 Wayland clipboard asks for "text/plain", which no modern app
# offers, so Ctrl+V lands as nothing). rofi stays as the fallback.
ENTRY="$HOME/.config/waybar/scripts/prime-entry.py"
entry_text() {  # $1 = prompt, $2 = extra flags (optional); prints the text, non-zero if cancelled
  if [ -x "$ENTRY" ] && /usr/bin/python3 -c 'import gi' >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    /usr/bin/python3 "$ENTRY" -p "$1" ${2:-}
  else
    "$HOME/.config/prime/rofi-hint.sh" -dmenu -i -theme "$THEME" -p "$1" \
         -theme-str 'listview { lines: 0; }' </dev/null
  fi
}

# ── the one place notes get written ─────────────────────────────────────────
# note_add TAG TEXT  →  "- [?] ... | TAG | TEXT", notify, and nudge the inbox job
# so Hermes picks it up on the next tick instead of the next 5-minute sweep.
# LEDGER_NO_NUDGE=1 writes the note without waking the agent (batch/scripted use).
note_add() {
  tag="$1"; msg="$2"
  if "$NOTE" -a -t "$tag" "$msg" >/dev/null; then
    notify "󰉹 Noted" "$(printf '%s' "$msg" | cut -c1-110)"
    [ "${LEDGER_NO_NUDGE:-0}" = "1" ] || hermes cron run ad988cbb9035 >/dev/null 2>&1 || true
  else
    notify "⚠️ Ledger" "Could not write the note"
    return 1
  fi
  log "noted [$tag]: $(printf '%s' "$msg" | cut -c1-200)"
}

# ── helpers ─────────────────────────────────────────────────────────────────
# Save an image/paste blob into the attachment store; prints the stored path.
save_blob() {  # $1 = mime, stdin = data
  mime="$1"
  ext="bin"
  case "$mime" in
    image/png) ext=png ;; image/jpeg) ext=jpg ;; image/webp) ext=webp ;;
    image/gif) ext=gif ;; image/svg+xml) ext=svg ;;
    text/plain*) ext=txt ;;
    application/pdf) ext=pdf ;;
    image/*) ext="${mime#image/}" ;;
    application/*) ext="${mime##*/}" ;;
  esac
  dir="$ATTACH/$(date +%Y-%m-%d)"
  mkdir -p "$dir"
  file="$dir/paste-$(date +%H%M%S).$ext"
  if cat >"$file" && [ -s "$file" ]; then printf '%s' "$file"; else rm -f "$file"; return 1; fi
}

# Turn clipboard text into a list of existing files: lines that are paths,
# "~/"-paths, or file:// URIs (percent-decoded). Prints one path per line.
paths_in_text() {
  python3 -c '
import os, sys, urllib.parse
seen, out = set(), []
for line in sys.stdin.read().splitlines():
    s = line.strip().strip("\"").strip("\x27")
    if not s:
        continue
    cand = urllib.parse.unquote(s[7:]) if s.startswith("file://") else s
    cand = os.path.expanduser(cand)
    if os.path.exists(cand):
        rp = os.path.realpath(cand)
        if rp not in seen:
            seen.add(rp); out.append(rp)
print("\n".join(out))
'
}

# Short human description of a file: "name (PDF, 1.2 MB)"
describe_file() {
  f="$1"
  size="$(du -h -- "$f" 2>/dev/null | cut -f1)"
  ext="$(printf '%s' "${f##*.}" | tr '[:lower:]' '[:upper:]')"
  [ "${#ext}" -gt 5 ] && ext="file"
  printf '%s (%s, %s)' "$(basename -- "$f")" "$ext" "${size:-?}"
}

# ── write a note for Prime ──────────────────────────────────────────────────
do_add() {
  text="$(entry_text "󰉹 note for Prime")"
  rc=$?
  if [ $rc -ne 0 ] || [ -z "${text//[[:space:]]/}" ]; then
    log "add cancelled (rc=$rc)"
    exit 0
  fi
  note_add ask "$text"
}

# ── the clipboard goes in, whatever it holds ────────────────────────────────
do_paste() {
  if ! have wl-paste; then
    notify "⚠️ Ledger" "wl-clipboard is not installed"
    exit 1
  fi
  types="$(wl-paste --list-types 2>/dev/null || true)"
  if [ -z "$types" ]; then
    notify "󰉹 Ledger" "Clipboard is empty — copy something first, then Paste."
    exit 0
  fi

  # 1) an image on the clipboard → save it and note the file
  if printf '%s\n' "$types" | grep -q '^image/'; then
    mime="$(printf '%s\n' "$types" | grep -m1 '^image/')"
    if file="$(wl-paste --type "$mime" | save_blob "$mime")" && [ -n "$file" ]; then
      note_add ask "photo pasted from the clipboard: $file"
    else
      notify "⚠️ Ledger" "Could not read the clipboard image"
    fi
    exit 0
  fi

  text="$(wl-paste --no-newline 2>/dev/null || true)"
  if [ -z "${text//[[:space:]]/}" ]; then
    notify "󰉹 Ledger" "Clipboard holds $(printf '%s' "$types" | tr '\n' ' ') — nothing I can note yet."
    exit 0
  fi
  backticks_safe="$(printf '%s' "$text" | tr '\n' ' ' | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')"

  # 2) paths (a file, a set of files, a photo from the file manager) → attach them
  paths="$(printf '%s' "$text" | paths_in_text)"
  if [ -n "$paths" ]; then
    list=""
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      list="$list$(describe_file "$p") @ $p; "
    done <<<"$paths"
    count="$(printf '%s\n' "$paths" | grep -c .)"
    if [ "$count" = "1" ]; then
      note_add ask "file: ${list%; }"
    else
      note_add ask "$count files: ${list%; }"
    fi
    exit 0
  fi

  # 3) a link
  if printf '%s' "$backticks_safe" | grep -qE '^https?://[^ ]+$'; then
    note_add ask "link: $backticks_safe"
    exit 0
  fi

  # 4) plain text; long text is parked in a file the note points at, so the
  #    ledger stays one line and Hermes still gets all of it.
  chars=${#text}
  if [ "$chars" -gt 400 ]; then
    dir="$HOME/.hermes/notes"
    mkdir -p "$dir"
    file="$dir/paste-$(date +%Y%m%d-%H%M%S).txt"
    printf '%s\n' "$text" >"$file"
    msg="$(printf '%s' "$backticks_safe" | cut -c1-300)… [full text: $file]"
  else
    msg="$backticks_safe"
  fi
  log "paste: $chars chars"
  note_add ask "$msg"
}

# ── attach files / photos ───────────────────────────────────────────────────
# ledger-bar.sh attach [--quiet] [PATH...]
#   no PATH  → file dialog, starting in Downloads
#   --quiet  → skip the "add a line" box (for scripts / file-manager actions)
do_attach() {
  quiet=0
  if [ "${1:-}" = "--quiet" ]; then quiet=1; shift; fi
  if [ "$#" -gt 0 ]; then
    picked="$(printf '%s\n' "$@")"
  else
    if ! have zenity; then
      notify "⚠️ Ledger" "zenity is not installed — nowhere to pick files from"
      exit 1
    fi
    picked="$(zenity --file-selection --multiple --separator=$'\n' \
                     --title="Attach to Prime" --filename="$HOME/Downloads/" 2>/dev/null)" || exit 0
  fi
  [ -n "${picked//[[:space:]]/}" ] || exit 0

  list=""
  while IFS= read -r p; do
    [ -n "$p" ] && list="$list$(describe_file "$p") @ $p; "
  done <<<"$picked"

  if [ "$quiet" = "1" ]; then
    note_add ask "files: ${list%; }"
    exit 0
  fi

  text="$(entry_text "󰂺 add a line (optional)")" || exit 0
  if [ -n "${text//[[:space:]]/}" ]; then
    msg="$text — ${list%; }"
  else
    msg="files: ${list%; }"
  fi
  note_add ask "$msg"
}

# ── copy side of the menu ───────────────────────────────────────────────────
do_copy() {
  if ! have wl-copy; then
    notify "⚠️ Ledger" "wl-clipboard is not installed"
    exit 1
  fi
  if wl-copy -- "$(cat -- "$LEDGER" 2>/dev/null)"; then
    notify "󰃀 Copied" "The whole ledger is on your clipboard."
  else
    notify "⚠️ Ledger" "Could not copy the ledger"
  fi
}

# ── the calendar (due dates + scheduled events) ─────────────────────────────
# A GTK window, not a rofi list: he asked for an *interactive* calendar, so the
# month grid is clickable and the day panel follows the selection. It attaches to
# the monitor under the pointer, which is where he just clicked the pill.
do_calendar() {
  [ -f "$CALENDAR" ] || { notify "⚠️ Ledger" "Calendar script is missing: $CALENDAR"; exit 1; }
  if pgrep -f "[l]edger-calendar.py" >/dev/null 2>&1; then
    notify "󰃭 Calendar" "Already open — click it, or close it with Esc."
    log "calendar: already running"
    exit 0
  fi
  setsid nohup /usr/bin/python3 "$CALENDAR" >"$RUNTIME/ledger-calendar.out" 2>&1 &
  disown 2>/dev/null || true
  sleep 0.6
  if pgrep -f "[l]edger-calendar.py" >/dev/null 2>&1; then
    log "calendar: launched"
  else
    notify "⚠️ Ledger" "The calendar did not start — see $RUNTIME/ledger-calendar.out"
    log "calendar: did NOT start"
  fi
}

# ── read-only view ──────────────────────────────────────────────────────────
do_view() {
  if [ ! -s "$LEDGER" ]; then
    notify "󰉹 Ledger" "Empty — click to write the first note."
    exit 0
  fi
  # ledger-view.py does the human-readable formatting (plain English sections,
  # 8:30am style times) so the popup never shows the raw machine format.
  # The calendar row is offered at the TOP of the list: this is the ledger list, and
  # a deadline is the one thing he opens it to check. Picking it opens the calendar
  # (the list itself is read-only, so this is the only row that does anything).
  choice="$({ printf '%s\n' "󰃭  Calendar — due dates + scheduled events"; \
              python3 "$HOME/.hermes/scripts/ledger-view.py"; } | \
    "$HOME/.config/prime/rofi-hint.sh" -dmenu -no-custom -i -theme "$THEME" -p "󰉹 ledger" \
         -theme-str 'listview { lines: 24; }' \
         -theme-str 'entry { enabled: false; cursor: default; }')" || exit 0
  case "$choice" in
    *Calendar*) do_calendar ;;
  esac
}

# ── context menu ────────────────────────────────────────────────────────────
do_menu() {
  # `grep -c` prints 0 AND exits 1 when nothing matches, so `|| echo 0` used to
  # append a second 0 and the row rendered as "0⏎0 queued". Pipe through head -1.
  count_in() { grep -c "$1" "$LEDGER" 2>/dev/null | head -1; }
  queued="$(count_in '^- \[ \] ')"; [ -n "$queued" ] || queued=0
  asks="$(count_in '^- \[?\] ')";   [ -n "$asks" ] || asks=0
  # NOTE: no "</dev/null" on this rofi call — the item list arrives on stdin and
  # a redirect there silently replaces it, leaving an empty prompt box.
  choice="$(printf '%s\n' \
      "󰆏  Paste clipboard in   (text · photo · file · link)" \
      "󰃀  Copy the ledger to the clipboard" \
      "󰉹  Write a note" \
      "󰂺  Attach a file or photo…" \
      "󰃭  Calendar   (due dates + scheduled events)" \
      "󰈈  Read the ledger   ($asks for me · $queued queued)" \
      "󰒲  Send queued notes now   ($queued)" \
      "󰷉  Open the ledger" \
    | "$HOME/.config/prime/rofi-hint.sh" -dmenu -i -theme "$THEME" -p "󰉹 ledger" \
        -theme-str 'listview { lines: 8; }')"
  rc=$?
  [ $rc -ne 0 ] && exit 0
  case "$choice" in
    *"Paste clipboard"*) do_paste ;;
    *"Copy the ledger"*) do_copy ;;
    *"Write a note"*)    do_add ;;
    *"Attach a file"*)   do_attach ;;
    *"Calendar"*)        do_calendar ;;
    *"Read the ledger"*) do_view ;;
    *"Send queued"*)     out="$("$FLUSH")"; notify "󰉹 Ledger" "${out:-Nothing queued — all sent.}" ;;
    *"Open the ledger"*) setsid nohup xdg-open "$LEDGER" >/dev/null 2>&1 & disown 2>/dev/null || true ;;
  esac
}

case "$MODE" in
  add)      do_add ;;
  paste)    do_paste ;;
  attach)   do_attach "$@" ;;
  copy)     do_copy ;;
  view)     do_view ;;
  calendar) do_calendar ;;
  flush)    out="$("$FLUSH")"; notify "󰉹 Ledger" "${out:-Nothing queued — all sent.}" ;;
  *)        do_menu ;;
esac
