#!/usr/bin/env bash
# Tell @USER@, on the desktop, what the last prime-pc update cycle did.
# Runs as @USER@ on a user timer; reads what the root-side cycle left behind.
# The WhatsApp/ledger message is sent by the root cycle itself, so this is the
# at-the-desk notice only — it never duplicates the ledger entry.
#   prime-pc-notify.sh            report the newest cycle, once
#   prime-pc-notify.sh --force    report it again anyway
set -uo pipefail

LASTRUN=/var/lib/prime-pc/last-run.json
MARKER="$HOME/.hermes/cache/prime-pc-notified"
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1

[ -r "$LASTRUN" ] || exit 0

mapfile -t F < <(python3 -c '
import json
d = json.load(open("/var/lib/prime-pc/last-run.json"))
print(d.get("ts", ""))
print(d.get("summary", "").replace("\n", " "))
print(d.get("reboot_needed", ""))
print(d.get("health_fails", 0))
' 2>/dev/null)

TS="${F[0]:-}"; SUMMARY="${F[1]:-}"; REBOOT="${F[2]:-}"; HEALTH="${F[3]:-0}"
[ -n "$TS" ] || exit 0

LAST="$(cat "$MARKER" 2>/dev/null || echo)"
if [ "$TS" = "$LAST" ] && [ "$FORCE" = 0 ]; then exit 0; fi

URGENCY=normal
case "$REBOOT" in
  yes)   URGENCY=critical ;;
  maybe) URGENCY=normal ;;
esac
[ "${HEALTH:-0}" != "0" ] && URGENCY=critical

if command -v notify-send >/dev/null 2>&1; then
  notify-send -a Prime -u "$URGENCY" -i system-software-update \
    "Prime — PC update" "$SUMMARY" 2>/dev/null || true
fi

mkdir -p "$(dirname "$MARKER")"
printf '%s\n' "$TS" >"$MARKER"
