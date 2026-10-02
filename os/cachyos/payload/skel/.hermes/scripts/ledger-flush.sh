#!/usr/bin/env bash
# Send every unsent entry in @USER@'s ledger to WhatsApp, then mark it sent.
#
# Contract (see the cron-job-delivery skill): this runs as a cron --no-agent
# --script job, so it must be SILENT when there is nothing to send. Delivery is
# done by `hermes send` from inside the script (explicit target + real exit
# code) rather than by cron's own deliver= resolution, which has historically
# failed to resolve a WhatsApp target from a fresh cron session.
#
#   LEDGER_TARGET   override the send target (default: whatsapp)
set -u

LEDGER="$HOME/.hermes/ledger.md"
TARGET="${LEDGER_TARGET:-whatsapp}"
LOCK="$HOME/.hermes/cache/ledger.lock"
LOG="$HOME/.hermes/cache/ledger.log"
STAMP="$HOME/.hermes/cache/ledger.last-send"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG" 2>/dev/null || true; }

[ -f "$LEDGER" ] || exit 0
mkdir -p "$(dirname "$LOCK")"

# One flusher at a time — a manual -n send and the cron tick can overlap.
exec 9>"$LOCK"
if ! flock -n 9; then
  log "another flush holds the lock — skipping this tick"
  exit 0
fi

mapfile -t pending < <(grep -n '^- \[ \] ' "$LEDGER" 2>/dev/null || true)
count="${#pending[@]}"
if [ "$count" -eq 0 ]; then
  exit 0
fi

body=""
for entry in "${pending[@]}"; do
  text="${entry#*:}"                # drop grep's line number
  rest="${text#- \[ \] }"           # drop the checkbox
  ts="${rest%% | *}"; rest="${rest#* | }"
  tag="${rest%% | *}"; msg="${rest#* | }"
  body+="• ${ts#* } [${tag}] ${msg}"$'\n'
done

out="$(mktemp "${TMPDIR:-/tmp}/ledger-flush.XXXXXX")"
{
  printf '📋 Ledger — %s new\n\n' "$count"
  printf '%s' "$body"
} >"$out"

if hermes send --to "$TARGET" --file "$out" --quiet; then
  awk -v stamp="$(date '+%H:%M')" \
    '/^- \[ \] / { sub(/^- \[ \] /, "- [x] "); print $0 " ·sent " stamp; next } { print }' \
    "$LEDGER" >"$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
  date '+%F %T' >"$STAMP"
  log "sent $count entr(y|ies) to $TARGET"
  rm -f "$out"
  exit 0
fi

log "SEND FAILED for $count pending entr(y|ies) — left queued"
cat "$out"
rm -f "$out"
exit 1
