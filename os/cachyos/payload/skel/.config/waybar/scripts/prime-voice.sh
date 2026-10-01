#!/usr/bin/env bash
# Waybar module: Prime hold-to-talk state.
#
#   listening -> 🎤 Ns   (while Super+R is held; N = seconds into the take)
#   sent      -> ✅ sent (for ~12s after a take is transcribed and delivered)
#   no-speech -> 🤔 nothing
#   error     -> ⚠️ voice
#   otherwise -> hidden
#
# Reads only runtime files, so it costs one stat per second and never needs to
# ask the agent anything.
set -u

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STATE="$RUNTIME/prime-ptt.state"
STATUS="$RUNTIME/prime-ptt.status"
NOW=$(date +%s)

live=0
if [ -f "$STATE" ]; then
  pid="$(sed -n 2p "$STATE" 2>/dev/null)"
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    live=1
  fi
fi

if [ "$live" = "1" ]; then
  started="$(stat -c %Y "$STATE" 2>/dev/null || echo "$NOW")"
  age=$(( NOW - started ))
  [ "$age" -lt 0 ] && age=0
  printf '{"text":"🎤 %ss","class":"recording","tooltip":"Prime is listening — release Super+R to send (%ss)"}\n' "$age" "$age"
  exit 0
fi

if [ -f "$STATUS" ]; then
  kind=""; stamp="0"; note=""
  IFS=' ' read -r kind stamp note < "$STATUS" 2>/dev/null || true
  age=$(( NOW - ${stamp:-0} ))
  if [ "$age" -ge 0 ] && [ "$age" -lt 12 ]; then
    case "${kind:-}" in
      sent)
        # The note reads "<what he said> → <where it went>", so the chip can name
        # the chat the take landed in without opening the app.
        dest="${note##*→ }"
        [ "$dest" = "$note" ] && dest="sent"
        dest="${dest%% (*}"
        [ "${#dest}" -gt 22 ] && dest="…${dest: -21}"
        printf '{"text":"✅ %s","class":"sent","tooltip":"Delivered: %s"}\n' "$dest" "${note:-transcribed}"
        exit 0 ;;
      command)
        # A spoken chat command ("switched to X", "named this chat Y").
        dest="${note%% — *}"
        printf '{"text":"🎙️ %s","class":"sent","tooltip":"%s — talk whenever"}\n' "${dest:-done}" "${note:-command}"
        exit 0 ;;
      no-speech)
        # A tap opens the Hermes text box (see prime-ptt-send.py open_text_box) —
        # say "type", don't scold him with "nothing".
        case "${note:-}" in
          *tap*)
            printf '{"text":"⌨️ type","class":"sent","tooltip":"Tap = typing box (Prime pill input)"}\n'
            exit 0 ;;
        esac
        printf '{"text":"🤔 nothing","class":"warn","tooltip":"No speech detected — try again"}\n'
        exit 0 ;;
      error)
        printf '{"text":"⚠️ voice","class":"warn","tooltip":"%s"}\n' "${note:-voice error}"
        exit 0 ;;
    esac
  fi
fi

printf '{"text":"","class":"idle"}\n'
