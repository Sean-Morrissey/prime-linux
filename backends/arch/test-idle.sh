#!/usr/bin/env bash
# Regression test for the idle-time computation (P0-1).
#
# The bug: /proc/uptime is in seconds (multiplied to microseconds) while loginctl's
# IdleSinceHintMonotonic is already in microseconds, but the old code divided the
# idle-since value *out* of microseconds and then by 60, so idle_minutes came back
# around a hundred million for every session — the "only reboot when idle" gate was
# always true and the machine could reboot while someone was working.
#
# This proves three things:
#   1. the pure idle_minutes_from() math is sane and clamped;
#   2. a busy machine yields idle 0, not idle-everything;
#   3. the full facts_json path, fed a mocked loginctl plus synthetic uptime,
#      produces a sane in-range idle_minutes.
#
# Run: ./test-idle.sh

set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SELF_DIR/prime-autoupdate"
ROOT="${TMPDIR:-/tmp}/prime-idle-test.$$"
pass=0; fail=0

good() { printf '  \033[32m✓\033[0m %s\n' "$*"; pass=$((pass+1)); }
nope() { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=$((fail+1)); }
check() { if [ "$2" = "$3" ]; then good "$1"; else nope "$1 (expected '$2', got '$3')"; fi; }

# Load the engine's functions without running its main dispatch (guarded by
# BASH_SOURCE[0] == $0). Use the non-sandbox facts path via a dummy backend.
export PRIME_BACKEND=bootc
export PRIME_STATE_DIR="$ROOT/state"
export PRIME_NOTIFY=0
mkdir -p "$PRIME_STATE_DIR"
# shellcheck source=/dev/null
source "$ENGINE"

head() { printf '\n\033[1m%s\033[0m\n' "$*"; }

head "1. idle_minutes_from — the pure math (P0-1)"
# up = 2h = 7_200_000_000 us. IdleSinceHintMonotonic is in the SAME units.
check "busy machine (idle 1s) -> 0"  "0"  "$(idle_minutes_from 7200000000 7199000000)"
check "10 minutes idle"              "10" "$(idle_minutes_from 7200000000 6600000000)"
check "30 minutes idle"              "30" "$(idle_minutes_from 7200000000 5400000000)"
check "negative difference clamps"   "0"  "$(idle_minutes_from 1000000 5000000)"
check "idle-since 0 -> full uptime"  "120" "$(idle_minutes_from 7200000000 0)"

head "2. every synthetic pair stays in [0, uptime_minutes]"
badpairs=0
for up in 0 1 60000000 7200000000 123456789000; do
  for since in 0 12345 60000000 7200000000 99999999999; do
    m="$(idle_minutes_from "$up" "$since")"
    uptime_min=$(( up / 60000000 ))
    if [ "$m" -lt 0 ] || [ "$m" -gt "$uptime_min" ]; then
      nope "idle_minutes_from $up $since -> $m (outside [0..$uptime_min])"
      badpairs=$((badpairs+1))
    fi
  done
done
[ "$badpairs" -eq 0 ] && good "all 25 synthetic pairs in range (the old bug produced ~hundred-million)"

head "3. facts_json with a mocked loginctl + synthetic /proc/uptime"
MOCKBIN="$ROOT/bin"; mkdir -p "$MOCKBIN"
cat > "$MOCKBIN/loginctl" <<'EOF'
#!/usr/bin/env bash
# mock loginctl: one session, idle since $MOCK_IDLE_SINCE_US (microseconds)
case "$1" in
  list-sessions) printf 'c1 1000 sean seat0\n' ;;
  show-session)
    case "$4" in
      IdleHint) echo yes ;;
      IdleSinceHintMonotonic) echo "${MOCK_IDLE_SINCE_US:-0}" ;;
    esac ;;
esac
exit 0
EOF
chmod +x "$MOCKBIN/loginctl"

# Synthetic uptime: 2h in microseconds. The mock loginctl reports idle-since in
# the same units, so the whole path is deterministic and independent of the host.
read_uptime_us() { echo 7200000000; }
export PATH="$MOCKBIN:$PATH"

MOCK_IDLE_SINCE_US=6600000000; export MOCK_IDLE_SINCE_US   # idle 10 minutes
check "facts_json idle_minutes = 10 (mocked loginctl)" "10" "$(fact idle_minutes)"

MOCK_IDLE_SINCE_US=7199000000; export MOCK_IDLE_SINCE_US   # idle 1 second
check "facts_json busy machine -> 0 (not idle-everything)" "0" "$(fact idle_minutes)"

head "4. audit() escapes quotes in detail (P1(iv))"
audit test ok 'snapshot "pre-update" reason'
python3 - "$PRIME_STATE_DIR/audit.jsonl" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1]) if l.strip()]
bad = 0
for l in lines:
    try:
        json.loads(l)
    except Exception:
        bad += 1
print("parseable" if bad == 0 else f"{bad} unparseable")
sys.exit(0 if bad == 0 else 1)
PY
rc=$?
[ "$rc" -eq 0 ] && good "audit line containing quotes parses" || nope "audit line containing quotes is unparseable"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
rm -rf "$ROOT"
[ "$fail" -eq 0 ]
