#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"   # never the real home or session (tests/sandbox.sh)
# tests/check-plain-fixes.sh — what the repair and safety screens tell a person to do
# is words or a button, never a command to type. Runs the checks that feed the health
# check (Super+H) and Settings → Privacy & Security, and reads the messages in the
# code for the ones a sandbox can't reach. Every button names a repair prime-fix knows.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; L="$REPO/layer"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if ( eval "$2" ) >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -8; fail=$((fail+1)); fi; }
CMD='(^|[^-])\b(sudo|pacman -|systemctl |gh auth|nmtui|journalctl|ufw |snapper -|mkinitcpio|pacdiff|paccache|usermod)'

# the rows the checks print right now (whatever this sandbox looks like), plus a btrfs
# machine without snapshots set up, which is the case people actually hit
EN="$L/system/updates/prime-system-update"
printf 'root_fs=btrfs\nsnapper_root=no\nbootloader=limine\n' > "$T/facts"
{
    bash "$L/bin/prime-security" status --tsv 2>/dev/null
    PRIME_TEST_ALLOW_NONROOT=1 PRIME_FACTS_FILE="$T/facts" bash "$EN" snapshots --tsv 2>/dev/null
    printf 'root_fs=ext4\n' > "$T/facts2"
    PRIME_TEST_ALLOW_NONROOT=1 PRIME_FACTS_FILE="$T/facts2" bash "$EN" snapshots --tsv 2>/dev/null
    HOME="$T" bash "$L/bin/prime-file-history" status --tsv 2>/dev/null
} > "$T/rows"
ck "the checks printed rows to look at"   "[ \$(wc -l < '$T/rows') -ge 5 ]"
ck "no row tells a person to type a command" "! cut -f2,3 '$T/rows' | grep -E '$CMD'"
ck "a btrfs computer without snapshots gets a button for it" "grep -qP '\tSet up snapshots\tsnapshots$' '$T/rows'"
ck "every button is a repair prime-fix knows" \
   "cut -f4 '$T/rows' | grep -v '^\$' | sort -u | while read -r f; do bash '$L/bin/prime-fix' --list | grep -qx \"\$f\" || { echo \"unknown: \$f\"; exit 1; }; done"

# the rows a sandbox can't produce: read them in the code
ck "no fix text in the checks' code is a command (prime-security, the updater's snapshot rows)" \
   "! grep -nE \"row (bad|warn|info|ok) .*\\\"[^\\\"]*$CMD\" '$L/bin/prime-security' && ! grep -nE \"printf '(bad|warn|ok)\\\\\\\\t[^']*$CMD\" '$EN'"
ck "the health check, the updater and the packs' checks speak in words" \
   "! grep -nE '\b(bad|tip|say note|ck_bad|ck_warn|stop|dim)\b[^#]*\"[^\"]*$CMD' '$L/bin/prime-doctor' '$L/bin/prime-update' '$L/bin/prime-addon' '$L/addons/gaming/bin/prime-gaming' '$EN' | grep -v 'sudo -A'"
ck "the undo steps never ask for a terminal" "! sed -n '/^cmd_undo()/,/^}/p' '$EN' | grep -E 'terminal|$CMD'"

# the buttons themselves
ck "prime-fix refuses what it doesn't know"     "! bash '$L/bin/prime-fix' rm-rf"
ck "the firewall button uses the root-owned copy when there is one" \
   "grep -q 'SEC=/usr/local/lib/prime-linux/prime-security' '$L/bin/prime-fix'"
ck "a button runs its fixed repair (dry run)"  "PRIME_FIX_DRY=1 bash '$L/bin/prime-fix' ssh-off | grep -q 'RUN \[Switching remote sign-in off\] sudo -A .*prime-security ssh off'"
ck "the health check turns a fix name into a button" \
   "grep -q 'action \"\$3\" \"\$BIN/prime-fix \$4\"' '$L/bin/prime-doctor'"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
