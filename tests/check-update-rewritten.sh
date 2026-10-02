#!/usr/bin/env bash
# tests/check-update-rewritten.sh — the published history was started afresh (the
# repository was recreated): "Update everything" must follow it instead of saying
# files were edited and staying on the old version forever. A copy with real edits
# is still left alone. Everything is local: a bare repo stands in for GitHub.
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
g() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }
mkdir -p "$T/work" "$T/home"
git ls-files -z | xargs -0 tar -cf - | tar -xf - -C "$T/work"
g -C "$T/work" init -q && g -C "$T/work" add -A && g -C "$T/work" commit -qm old
g clone -q --bare "$T/work" "$T/origin.git"
upd() {   # upd <copy>: run that copy's own updater, Prime part only, no desktop
    env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE HOME="$T/home" PRIME_NO_LIVE=1 PRIME_NO_GSETTINGS=1 \
        timeout 120 bash "$1/layer/bin/prime-update" --prime > "$T/out" 2>&1 </dev/null
}
g clone -q "$T/origin.git" "$T/copy"
g clone -q "$T/origin.git" "$T/edited"
echo "# changed here" >> "$T/edited/README.md"
# the repository is recreated: one new commit with no shared history
g -C "$T/work" checkout -q --orphan fresh && echo fresh > "$T/work/FRESH" && g -C "$T/work" add -A && g -C "$T/work" commit -qm fresh
g -C "$T/work" push -q -f "$T/origin.git" fresh:main
new="$(git -C "$T/origin.git" rev-parse main)"

upd "$T/copy"
ck "an untouched copy follows the new history"   "[ \"\$(git -C '$T/copy' rev-parse HEAD)\" = '$new' ] && [ -e '$T/copy/FRESH' ]"
ck "… and says so in words"                       "grep -q 'started afresh' '$T/out'"
ck "it says out loud that the main channel isn't signature-checked" "grep -q \"test channel (main), so Prime's own updates aren't checked for a signature\" '$T/out'"
upd "$T/edited"
ck "a copy with edits is left alone"              "[ \"\$(git -C '$T/edited' rev-parse HEAD)\" != '$new' ] && grep -q 'changed here' '$T/edited/README.md'"
[ $fail = 0 ] || sed 's/^/      | /' "$T/out" | tail -20
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
