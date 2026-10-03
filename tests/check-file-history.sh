#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"   # never the real home or session (tests/sandbox.sh)
# tests/check-file-history.sh — File History (snapshots of the home disk) with fake
# findmnt/btrfs/snapper/systemctl: switched on only where it can work, never changes
# someone's own snapper settings, each account sees its own home, and a chosen moment
# opens read-only. No root, no btrfs needed.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; F="$REPO/layer/bin/prime-file-history"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if eval "$2" >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -5; fail=$((fail+1)); fi; }
mkdir -p "$T/bin" "$T/configs" "$T/home/.snapshots/7/snapshot/alex/Documents" "$T/home/alex"
cat > "$T/bin/findmnt" <<'X'
#!/usr/bin/env bash
cat "$FAKE/fstype" 2>/dev/null
X
cat > "$T/bin/btrfs" <<'X'
#!/usr/bin/env bash
[ -e "$FAKE/subvol" ]
X
cat > "$T/bin/snapper" <<'X'
#!/usr/bin/env bash
echo "snapper $*" >> "$FAKE/calls"
case " $* " in
  *" create-config "*) : > "$FAKE/configs/home" ;;
  *" get-config "*)    printf '{"ALLOW_USERS":"%s"}\n' "$(cat "$FAKE/allow" 2>/dev/null)" ;;
  *" set-config "*)    for a; do case "$a" in ALLOW_USERS=*) printf '%s' "${a#ALLOW_USERS=}" > "$FAKE/allow" ;; esac; done ;;
  *" list "*)          printf 'number\tdate\n0\t\n6\t2026-10-01 09:00:00\n7\t%s\n' "$(date '+%F %H:00:00')" ;;
esac
X
printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$FAKE/calls"\n' > "$T/bin/systemctl"
printf '#!/usr/bin/env bash\n:\n' > "$T/bin/notify-send"
chmod +x "$T/bin/"*
export FAKE="$T" PATH="$T/bin:$PATH" PRIME_FH_TESTING=1 PRIME_FH_CONFIGS="$T/configs" PRIME_FH_HOME_MOUNT="$T/home"
calls() { cat "$T/calls" 2>/dev/null; }

echo ext4 > "$T/fstype"
ck "not btrfs: says it isn't possible, changes nothing"  "bash $F setup --user alex | grep -q 'not possible' && [ -z \"\$(calls)\" ]"
ck "…and the report says so (info, not a problem)"        "bash $F status --tsv | grep -q '^info'"
echo btrfs > "$T/fstype"
ck "btrfs but /home isn't its own subvolume: not possible" "bash $F setup --user alex | grep -q 'not possible'"
touch "$T/subvol"
ck "off where it could be on: a warning with the way to fix it" "bash $F status --tsv | grep -qP '^warn\t.*\tUpdate everything'"
ck "switched on with hourly/daily/weekly/monthly and space limits" \
   "bash $F setup --user alex && calls | grep -q 'create-config' && calls | grep -q 'TIMELINE_CREATE=yes' && calls | grep -q 'SPACE_LIMIT=0.25' && calls | grep -q 'FREE_LIMIT=0.25'"
ck "the timers that make and tidy snapshots are on"      "calls | grep -q 'enable --now snapper-timeline.timer snapper-cleanup.timer'"
ck "alex may see the snapshots"                          "[ \"\$(cat $T/allow)\" = alex ]"
: > "$T/calls"
ck "a second account is added, nothing else changes"     "bash $F setup --user sam && [ \"\$(cat $T/allow)\" = 'alex sam' ] && ! calls | grep -q 'create-config\|TIMELINE'"
ck "running it again adds nobody twice"                  "bash $F setup --user sam && [ \"\$(cat $T/allow)\" = 'alex sam' ]"
ck "a bad user name is refused"                          "! bash $F setup --user 'x;rm' "
ck "on: the report says how to get a file back"          "bash $F status --tsv | grep -q '^ok.*Get a file back'"
ck "the moments are listed newest first, in words"       "HOME=$T/home/alex bash $F list | head -1 | grep -qP '^7\tToday, '"
ck "a moment opens your own home folder as it was"       "HOME=$T/home/alex bash $F open 7 | grep -qx 'OPEN $T/home/.snapshots/7/snapshot/alex'"
ck "a moment that's gone says so"                        "! HOME=$T/home/alex bash $F open 3"
ck "only numbers are accepted"                           "! HOME=$T/home/alex bash $F open '../../etc'"
ck "the installer switches it on (root copy)"            "grep -q 'prime-file-history setup' $REPO/layer/system/install-system.sh && grep -q 'bin/prime-file-history|' $REPO/layer/system/install-system.sh"
ck "it's in the Prime menu and the app list"             "grep -q prime-file-history $REPO/layer/default/menu.json && [ -f $REPO/layer/applications/prime-file-history.desktop ]"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
