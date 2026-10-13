#!/usr/bin/env bash
# tests/check-cli-metadata.sh — every desktop command carries a one-line
# `# prime:summary=` header, and `prime commands` reads them back. The headers
# are what makes the CLI self-describing; without this check a new script joins
# layer/bin and is invisible in the help listing forever.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

BIN="$REPO/layer/bin"
ROUTER="$REPO/files/system/usr/libexec/prime/prime"

# --- every command has a header -------------------------------------------
missing=""
total=0
for f in "$BIN"/prime-*; do
  [ -f "$f" ] || continue
  total=$((total+1))
  grep -q '^# prime:summary=' "$f" || missing="$missing $(basename "$f")"
done
echo "  ..  $total commands in layer/bin"
ck "every command has a prime:summary header"  "[ -z '$missing' ]"
[ -n "$missing" ] && echo "        missing:$missing"

# --- headers are useful, not empty or absurdly long ------------------------
bad=""
for f in "$BIN"/prime-*; do
  [ -f "$f" ] || continue
  s="$(sed -n 's/^# prime:summary=//p' "$f" | head -1)"
  n=${#s}
  if [ "$n" -lt 8 ] || [ "$n" -gt 110 ]; then bad="$bad $(basename "$f")($n)"; fi
done
ck "every summary is between 8 and 110 characters"  "[ -z '$bad' ]"
[ -n "$bad" ] && echo "        out of range:$bad"

# --- the header sits in the first few lines, where the router looks --------
late=""
for f in "$BIN"/prime-*; do
  [ -f "$f" ] || continue
  grep -q '^# prime:summary=' "$f" || continue
  head -10 "$f" | grep -q '^# prime:summary=' || late="$late $(basename "$f")"
done
ck "every header is within the first 10 lines"  "[ -z '$late' ]"

# --- the router reads them back -------------------------------------------
HOME="$T/home" PRIME_LAYER_BIN="$BIN" PRIME_STATE_DIR="$T/state" \
  bash "$ROUTER" commands > "$T/out" 2>&1
listed="$(grep -c 'prime-' "$T/out" || true)"
ck "prime commands lists every command"  "[ '$listed' = '$total' ]"
ck "prime help includes the desktop commands" \
   "HOME=$T/home PRIME_LAYER_BIN=$BIN PRIME_STATE_DIR=$T/state bash $ROUTER help | grep -q 'Desktop commands:'"

# --- and degrades quietly when the layer is not installed ------------------
ck "prime help works with no layer installed" \
   "HOME=$T/empty PRIME_LAYER_BIN=/nonexistent PRIME_STATE_DIR=$T/state bash $ROUTER help >/dev/null 2>&1"

echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
