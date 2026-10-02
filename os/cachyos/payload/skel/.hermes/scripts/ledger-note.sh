#!/usr/bin/env bash
# Append a note to @USER@'s ledger (~/.hermes/ledger.md).
#
#   ledger-note.sh [-t TAG] [-n] [-a] "message text"
#     -t TAG   category tag (default: note)  e.g. sys, printer, school, money
#     -n       send now instead of waiting for the next flush tick
#     -a       ASK: this is @USER@ writing TO Hermes (a request), not a message
#              for him. Lands as "- [?] ..." which the flush ignores and the
#              ledger-inbox job picks up.
#
# Directions, all in one file:
#   - [ ]  queued for @USER@   (ledger-flush sends it, flips to - [x])
#   - [x]  already sent to @USER@
#   - [?]  @USER@ → Prime, not actioned yet
#   - [!]  actioned (ledger-handle.sh stamps it)
set -u

TAG="note"
NOW=0
ASK=0
while getopts "t:na" opt; do
  case "$opt" in
    t) TAG="$OPTARG" ;;
    n) NOW=1 ;;
    a) ASK=1 ;;
    *) echo "usage: ledger-note.sh [-t TAG] [-n] [-a] \"text\"" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

MSG="${*:-}"
if [ -z "$MSG" ]; then
  echo "usage: ledger-note.sh [-t TAG] [-n] [-a] \"text\"" >&2
  exit 2
fi

LEDGER="$HOME/.hermes/ledger.md"
TS="$(date '+%F %H:%M')"

# One entry = one line. Collapse newlines and runs of spaces.
MSG="$(printf '%s' "$MSG" | tr '\n' ' ' | tr -s ' ')"
MSG="$(printf '%s' "$MSG" | sed -e 's/^ *//' -e 's/ *$//')"

mkdir -p "$(dirname "$LEDGER")"
if [ ! -f "$LEDGER" ]; then
  {
    printf '# @USER@'\''s ledger\n\n'
    printf 'Two directions, one file:\n\n'
    printf '  `- [ ]` / `- [x]`   Hermes → @USER@    (ledger-flush sends new ones to WhatsApp)\n'
    printf '  `- [?]` / `- [!]`   @USER@ → Hermes    (ledger-inbox hands new ones to the agent)\n\n'
    printf 'One line per entry: `- [ ] YYYY-MM-DD HH:MM | tag | text`\n\n'
  } >"$LEDGER"
fi

MARK="- [ ]"
[ "$ASK" = "1" ] && MARK="- [?]"
printf -- '%s %s | %s | %s\n' "$MARK" "$TS" "$TAG" "$MSG" >>"$LEDGER"

if [ "$ASK" = "1" ]; then
  echo "queued for Hermes [$TAG] $MSG"
  exit 0
fi

echo "logged [$TAG] $MSG"

if [ "$NOW" = "1" ]; then
  exec "$HOME/.hermes/scripts/ledger-flush.sh"
fi
