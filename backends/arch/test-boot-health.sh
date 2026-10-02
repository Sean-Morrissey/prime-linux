#!/usr/bin/env bash
# Regression test for the boot-time health check (P0-3).
#
# The bug: the boot verifier ran network / display / session checks as root at boot.
# A Wi-Fi laptop that had not associated yet, a lid-closed laptop, or a machine
# sitting at the login screen (no session) all "failed" health, which triggered a
# rollback, a reboot, and the same failure again — a loop that bricks the machine.
#
# This proves the boot-time verifier only asserts boot-critical things (failed
# units, storage, the root filesystem), that network/session absence still shows up
# in the *full* check (which a human runs), and — end to end in the sandbox — that a
# boot at the login screen with no session does NOT roll back.
#
# Run: ./test-boot-health.sh

set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${TMPDIR:-/tmp}/prime-boothealth-test.$$"
pass=0; fail=0

good() { printf '  \033[32m✓\033[0m %s\n' "$*"; pass=$((pass+1)); }
nope() { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=$((fail+1)); }
check() { if [ "$2" = "$3" ]; then good "$1"; else nope "$1 (expected '$2', got '$3')"; fi; }

head() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# --- part A: the bootc backend_health must ignore comfort-check absence ---------
MOCKBIN="$ROOT/bin"; mkdir -p "$MOCKBIN"
cat > "$MOCKBIN/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0   # pretend no failed units
EOF
cat > "$MOCKBIN/ip" <<'EOF'
#!/usr/bin/env bash
exit 0   # no output -> no default route -> "no network"
EOF
cat > "$MOCKBIN/loginctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-sessions) printf 'c1 1000 alex seat0\n' ;;   # a session exists, but...
  show-session)
    case "$4" in
      Type) echo tty ;;            # ...it is not graphical -> login screen
      IdleHint) echo yes ;;
      IdleSinceHintMonotonic) echo 0 ;;
    esac ;;
esac
exit 0
EOF
cat > "$MOCKBIN/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1   # no audio server running
EOF
chmod +x "$MOCKBIN/systemctl" "$MOCKBIN/ip" "$MOCKBIN/loginctl" "$MOCKBIN/pgrep"
export PATH="$MOCKBIN:$PATH"

# shellcheck source=/dev/null
source "$SELF_DIR/backend-bootc.sh"

head "1. boot-time verifier ignores no-network + no-session (P0-3)"
out="$(backend_health_boot)"
printf '%s\n' "$out" | sed 's/^/    /'
if printf '%s\n' "$out" | grep -q $'\t0\t'; then
  nope "boot-time verify reported a failure with no network and no session"
else
  good "boot-time verify reports healthy (no false failure)"
fi

full="$(backend_health)"
if printf '%s\n' "$full" | grep -q $'network\t0'; then
  good "full check still flags 'no network' (post-login, not boot-critical)"
else
  nope "full check did not flag the missing network"
fi
if printf '%s\n' "$full" | grep -q $'session\t0'; then
  good "full check still flags 'no session' (post-login, not boot-critical)"
else
  nope "full check did not flag the missing session"
fi

# --- part B: end to end — sandbox post-boot at the login screen ---------------
ENGINE="$SELF_DIR/prime-autoupdate"
export PRIME_BACKEND=sandbox
export PRIME_NOTIFY=0
export PRIME_GRACE_SECONDS=0
export PRIME_AUTONOMY=auto-user

fresh() { local d="$ROOT/$1"; rm -rf "$d"; mkdir -p "$d/sandbox"; printf '228\n' > "$d/sandbox/pending"; printf '1840\n' > "$d/sandbox/installed"; printf '%s\n' "$d"; }
cycle()    { PRIME_STATE_DIR="$1" "$ENGINE" cycle     >"$1/cycle.txt" 2>&1; }
postboot() { PRIME_STATE_DIR="$1" "$ENGINE" post-boot >"$1/post.txt"  2>&1; }

head "2. end-to-end: a boot at the login screen must NOT roll back"
d="$(fresh login)"
printf '{"idle_minutes":45,"on_ac":true,"metered":false,"busy_jobs":[],"hour":4}\n' > "$d/sandbox/facts.json"
cycle "$d"
# the update installed and the machine rebooted; now it boots to the login screen
# (no graphical session, no network) — boot-critical is fine, comfort is absent.
touch "$d/sandbox/comfort_broken"
before="$(cat "$d/sandbox/last_reboot" 2>/dev/null)"
postboot "$d"
after="$(cat "$d/sandbox/last_reboot" 2>/dev/null)"
check "no rollback happened (update stays installed)" "0" "$(cat "$d/sandbox/pending" 2>/dev/null)"
check "no reboot was triggered by the false alarm" "$before" "$after"
grep -q "update verified" "$d/post.txt" && good "post-boot declared the boot healthy" || nope "post-boot did not declare the boot healthy"
grep -q "going back to the version that worked" "$d/post.txt" && nope "post-boot rolled back at the login screen" || good "post-boot did not roll back at the login screen"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
rm -rf "$ROOT"
[ "$fail" -eq 0 ]
