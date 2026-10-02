#!/usr/bin/env bash
# Lifecycle test for the Prime supervisor.
#
# Proves the loop that the whole idea rests on, on a fake machine in a temp
# directory: snapshot before anything risky, apply, verify, and undo it yourself
# when the machine comes back broken.
#
# Run it: ./test-lifecycle.sh
# It touches nothing outside its own temp directory, needs no root, and does not
# go near a real system.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d /tmp/prime-lifecycle-XXXXXX)"
export PRIME_BACKEND="sandbox"
export PRIME_STATE_DIR="$WORK/state"

PASS=0; FAIL=0
check() { # check <description> <condition-output> <expected-substring>
  if printf '%s' "$2" | grep -q -- "$3"; then
    printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  \033[31m✗\033[0m %s\n' "$1"
    printf '      expected to find: %s\n' "$3"
    printf '      got: %s\n' "$(printf '%s' "$2" | head -3)"
    FAIL=$((FAIL+1))
  fi
}

run() { "$HERE/prime" "$@" 2>&1; }
pending() { cat "$PRIME_STATE_DIR/sandbox/pending" 2>/dev/null || echo "?"; }

printf '\n\033[1mPrime supervisor — lifecycle test\033[0m\n'
printf 'sandbox: %s\n\n' "$WORK"

printf '\033[1m1. a machine with no undo button\033[0m\n'
out="$(run status)"
check "reports the machine state"            "$out" "machine:"
check "counts the waiting updates"           "$out" "228 update(s) waiting"
check "notices there is no rollback point"   "$out" "no rollback point exists"
check "says an update now would be one-way"  "$out" "one-way"

printf '\n\033[1m2. a healthy update, autonomy: suggest\033[0m\n'
export PRIME_AUTONOMY="suggest"
out="$(run update)"
check "takes a rollback point first"         "$out" "rollback point:"
check "applies the updates"                  "$out" "updates applied"
check "verifies the machine afterwards"      "$out" "update verified"
check "leaves nothing pending"               "$(pending)" "^0$"

printf '\n\033[1m3. an update that breaks the machine, autonomy: auto-all\033[0m\n'
# new batch arrives, and this one is going to go wrong
bash -c "source '$HERE/backend-sandbox.sh'; sb_set_pending 40; sb_break_next_update"
export PRIME_AUTONOMY="auto-all"
out="$(run update)"
check "applies the broken update"            "$out" "updates applied"
check "detects the unhealthy result"         "$out" "does not look healthy"
check "rolls itself back"                    "$out" "rolled back to"
check "the update is undone"                 "$(pending)" "^40$"
out="$(run health)"
check "machine is healthy again"             "$out" "machine looks healthy"

printf '\n\033[1m4. an update that fails to install at all\033[0m\n'
bash -c "source '$HERE/backend-sandbox.sh'; sb_set_pending 12; sb_fail_next_apply"
out="$(run update)"
check "notices the install failed"           "$out" "the update itself failed"
check "leaves the machine untouched"         "$(pending)" "^12$"
check "still has the rollback point"         "$(run rollbacks)" "pre-update"

printf '\n\033[1m5. the same failure, autonomy: suggest (it must ask)\033[0m\n'
bash -c "source '$HERE/backend-sandbox.sh'; sb_break_next_update"
export PRIME_AUTONOMY="suggest"
out="$(run update)"
check "detects the unhealthy result"         "$out" "does not look healthy"
check "refuses to act without a human"       "$out" "will not undo this without you"
check "hands over the exact command"         "$out" "prime rollback"
out="$(run status)"
check "machine is still broken (no silent fix)" "$out" "unhealthy"

printf '\n\033[1m6. the human says undo it\033[0m\n'
snap="$(run rollbacks | awk '{print $1}' | head -1)"
out="$(printf 'y\n' | run rollback "$snap")"
check "restores the rollback point"          "$out" "restored"
out="$(run health)"
check "machine is healthy again"             "$out" "machine looks healthy"

printf '\n\033[1m7. the audit trail\033[0m\n'
out="$(run audit)"
check "records every snapshot"               "$out" "snapshot"
check "records the failed update"            "$out" "update    failed"
check "records the automatic rollback"       "$out" "rollback  ok"
check "records the refusal to act alone"     "$out" "rollback  skipped"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mthe loop closes: snapshot → update → verify → undo if broken\033[0m\n\n'
  rm -rf "$WORK"
  exit 0
fi
printf '\033[31msomething in the loop is broken (sandbox kept at %s)\033[0m\n\n' "$WORK"
exit 1
