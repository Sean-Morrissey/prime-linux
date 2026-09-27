#!/usr/bin/env bash
# rofi-hint.sh — rofi with the universal footer hint.
#
# Every Prime surface that still uses rofi (menus, pickers, lists) goes through
# here so the little grey line explaining the keys is always present, the same
# way prime-entry.py boxes show "Enter → send · Esc → cancel".
#
#   ROFI_HINT="custom text" rofi-hint.sh -dmenu ...
#   (no ROFI_HINT → the generic key hint)
set -u
HINT="${ROFI_HINT:-↑↓ move  ·  Enter pick  ·  Esc cancel  ·  type to filter}"
for a in "$@"; do
  [ "$a" = "-mesg" ] && exec rofi "$@"   # caller already set one
done
exec rofi "$@" -mesg "$HINT"
