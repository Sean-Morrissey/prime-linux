#!/usr/bin/env bash
# ledger-handle.sh — mark @USER@'s ledger asks as actioned.
#
#   ledger-handle.sh            stamp EVERY open "- [?]" entry as done
#   ledger-handle.sh <match>    stamp only entries whose text contains <match>
#
# Called by the agent after it has actually dealt with an ask (calendar written,
# task done, answer left in the outbox). Output is the count so a run log shows
# something happened.
set -u

LEDGER="$HOME/.hermes/ledger.md"
MATCH="${1:-}"
LOCK="$HOME/.hermes/cache/ledger.lock"
STAMP="$(date '+%H:%M')"

[ -f "$LEDGER" ] || { echo "0"; exit 0; }
mkdir -p "$(dirname "$LOCK")"

exec 9>"$LOCK"
flock -n 9 || { echo "busy"; exit 0; }

n=$(grep -c '^- \[?\] ' "$LEDGER" 2>/dev/null || true)
if [ "$n" = "0" ]; then
  echo "0"
  exit 0
fi

if [ -n "$MATCH" ]; then
  awk -v m="$MATCH" -v stamp="$STAMP" '
    /^- \[\?\] / && index($0, m) { sub(/^- \[\?\] /, "- [!] "); print $0 " ·done " stamp; next }
    { print }
  ' "$LEDGER" >"$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
else
  awk -v stamp="$STAMP" '
    /^- \[\?\] / { sub(/^- \[\?\] /, "- [!] "); print $0 " ·done " stamp; next }
    { print }
  ' "$LEDGER" >"$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
fi

echo "$n"
