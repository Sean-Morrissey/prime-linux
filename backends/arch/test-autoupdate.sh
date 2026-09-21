#!/usr/bin/env bash
# Proves the unattended update cycle — the part that has to be right, because it
# runs at 4am with nobody watching. Everything happens in the sandbox backend: a
# fake machine in a directory, no root, no pacman, no reboot. What is being tested
# is the *decision*, which is the same code that would run on a real machine.
#
# Cases:
#   1  up to date                     -> does nothing, says so
#   2  night, machine asleep          -> installs, restarts silently
#   3  a long job is running          -> installs, refuses to restart
#   4  daytime, someone is working    -> installs, refuses to restart
#   5  the human said "later"         -> installs nothing at all
#   6  autonomy = suggest             -> installs nothing, asks instead
#   7  the new version is broken      -> rolls back by itself, counts the failure
#   8  that update failed twice       -> stops retrying, does not loop
#
# Run: ./test-autoupdate.sh

set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SELF_DIR/prime-autoupdate"
ROOT="${TMPDIR:-/tmp}/prime-auto-test.$$"
pass=0; fail=0

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_bad=$'\033[31m'; c_b=$'\033[1m'; c_dim=$'\033[2m'
head() { printf '\n%s%s%s\n' "$c_b" "$*" "$c_reset"; }
good() { printf '  %s✓%s %s\n' "$c_ok" "$c_reset" "$*"; pass=$((pass+1)); }
nope() { printf '  %s✗%s %s\n' "$c_bad" "$c_reset" "$*"; fail=$((fail+1)); }
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then good "$1"; else nope "$1 (expected '$2', got '$3')"; fi
}

fresh() { # fresh <name> -> prints a clean state dir seeded with a fake machine
  local d="$ROOT/$1"
  rm -rf "$d"; mkdir -p "$d/sandbox"
  printf '228\n' > "$d/sandbox/pending"
  printf '1840\n' > "$d/sandbox/installed"
  printf '%s\n' "$d"
}

facts() { # facts <statedir> <idle> <hour> [busy_json]
  printf '{"idle_minutes":%s,"on_ac":true,"metered":false,"busy_jobs":%s,"hour":%s}\n' \
    "$2" "${4:-[]}" "$3" > "$1/sandbox/facts.json"
}

cycle() { # cycle <statedir> [autonomy]
  PRIME_BACKEND=sandbox PRIME_STATE_DIR="$1" PRIME_AUTONOMY="${2:-auto-all}" \
  PRIME_GRACE_SECONDS=0 PRIME_NOTIFY=0 "$ENGINE" cycle >"$1/out.txt" 2>&1
}

pending()   { cat "$1/sandbox/pending" 2>/dev/null; }
rebooted()  { [ -e "$1/sandbox/last_reboot" ] && echo yes || echo no; }

head "1. machine is up to date"
d="$(fresh uptodate)"; printf '0\n' > "$d/sandbox/pending"; facts "$d" 45 4
cycle "$d" >/dev/null; rc=$?
check "exits cleanly" "0" "$rc"
grep -q "up to date" "$d/out.txt" && good "says there is nothing to do" || nope "did not report being up to date"
check "no restart happened" "no" "$(rebooted "$d")"

head "2. 4am, machine asleep -> installs and restarts by itself"
d="$(fresh night)"; facts "$d" 45 4
cycle "$d" >/dev/null
check "updates installed" "0" "$(pending "$d")"
check "restarted without asking" "yes" "$(rebooted "$d")"
grep -q "safe moment to restart" "$d/out.txt" && good "explained why now was safe" || nope "did not explain the restart"

head "3. someone is rendering video -> installs, will not restart"
d="$(fresh busy)"; facts "$d" 45 4 '["ffmpeg"]'
cycle "$d" >/dev/null
check "updates installed" "0" "$(pending "$d")"
check "did not restart" "no" "$(rebooted "$d")"
grep -q "not restarting now" "$d/out.txt" && good "said why it is waiting" || nope "did not say why"

head "4. daytime and someone is working -> installs, will not restart"
d="$(fresh working)"; facts "$d" 2 14
cycle "$d" >/dev/null
check "updates installed" "0" "$(pending "$d")"
check "did not restart" "no" "$(rebooted "$d")"
grep -q "in use" "$d/out.txt" && good "recognised the machine is in use" || nope "did not report the machine in use"

head "5. the human said later -> installs nothing"
d="$(fresh later)"; facts "$d" 45 4
PRIME_STATE_DIR="$d" PRIME_BACKEND=sandbox "$ENGINE" later 12 >/dev/null
cycle "$d" >/dev/null
check "nothing installed" "228" "$(pending "$d")"
check "no restart" "no" "$(rebooted "$d")"
grep -q "holding off" "$d/out.txt" && good "honoured it quietly, no nagging" || nope "did not honour the deferral"

head "6. autonomy = suggest -> installs nothing, asks instead"
d="$(fresh suggest)"; facts "$d" 45 4
cycle "$d" suggest >/dev/null
check "nothing installed" "228" "$(pending "$d")"
check "no restart" "no" "$(rebooted "$d")"
grep -q "will not install these without you" "$d/out.txt" && good "asked instead of acting" || nope "did not ask permission"

head "7. the new version boots broken -> recovers by itself"
d="$(fresh broken)"; facts "$d" 45 4
cycle "$d" >/dev/null
check "update went in" "0" "$(pending "$d")"
check "restarted into it" "yes" "$(rebooted "$d")"
touch "$d/sandbox/health_broken"          # this is the bad boot
PRIME_BACKEND=sandbox PRIME_STATE_DIR="$d" PRIME_AUTONOMY=auto-all PRIME_NOTIFY=0 \
  "$ENGINE" post-boot >"$d/post.txt" 2>&1
grep -q "going back to the version that worked" "$d/post.txt" && good "decided to go back" || nope "did not decide to roll back"
check "back on the previous version" "228" "$(pending "$d")"
check "machine healthy again" "0" "$([ -e "$d/sandbox/health_broken" ] && echo 1 || echo 0)"
check "failure recorded for next time" "1" "$(cat "$d/autoupdate.failcount" 2>/dev/null || echo 0)"

head "8. that update already failed twice -> stops retrying"
d="$(fresh givup)"; facts "$d" 45 4
printf '2\n' > "$d/autoupdate.failcount"
cycle "$d" >/dev/null
check "nothing installed" "228" "$(pending "$d")"
check "no restart" "no" "$(rebooted "$d")"
grep -q "not retrying today" "$d/out.txt" && good "refused to loop" || nope "would have retried a known-bad update"

head "9. the audit trail exists for all of it"
if [ -s "$ROOT/broken/audit.jsonl" ]; then
  good "every decision was logged to audit.jsonl"
  grep -q '"action":"rollback"' "$ROOT/broken/audit.jsonl" \
    && good "including the rollback it did on its own" || nope "rollback not in the audit log"
else
  nope "no audit log written"
fi

printf '\n%s%d passed, %d failed%s   %s(work dir: %s)%s\n' \
  "$c_b" "$pass" "$fail" "$c_reset" "$c_dim" "$ROOT" "$c_reset"
rm -rf "$ROOT"
[ "$fail" -eq 0 ]
