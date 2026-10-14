#!/usr/bin/env bash
# tests/check-no-rewind.sh — Prime never goes back to an old version by itself.
#   * install.sh run from an old clone (the ~/prime-linux made for the first
#     install) hands over to the newer installed copy instead of putting the old
#     one back — also when the two have no history in common;
#   * prime-update follows GitHub after the repo's history was restarted (a
#     fast-forward can't), but never over files someone edited.
# Everything happens in a temporary HOME with throwaway git repos; no pacman.
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
ROOT="$PWD"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home"; mkdir -p "$HOME"; git config --global init.defaultBranch main
commit() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" commit -qam "$3"; }
INSTALLED="$HOME/.local/share/prime-linux"
STUB='#!/usr/bin/env bash
echo "INSTALLED-COPY-RAN $*"'

# a PATH without pacman: a run that isn't handed over stops at "pacman not found"
mkdir -p "$T/bin"
for c in bash env dirname date git cat sed mkdir uname readlink; do ln -s "$(command -v "$c")" "$T/bin/$c"; done
# the installer refuses root; CI containers and sandboxes often are root
printf '#!%s\n[ "${1:-}" = -u ] && { echo 1000; exit; }; exec %s "$@"\n' "$(command -v bash)" "$(command -v id)" > "$T/bin/id"; chmod +x "$T/bin/id"
run_install() { env PATH="$T/bin" bash "$1/install.sh" --dry-run "${@:2}" > "$T/out" 2>&1; }

echo "install.sh from an old clone"
# one history: the old clone is behind the installed copy
git init -q "$T/one"; cp "$ROOT/install.sh" "$T/one/"; git -C "$T/one" add -A; commit "$T/one" 2026-10-02T12:00 old
git clone -q "$T/one" "$HOME/prime-linux"
printf '%s\n' "$STUB" > "$T/one/install.sh"; commit "$T/one" 2026-10-13T12:00 new
git clone -q "$T/one" "$INSTALLED"
run_install "$HOME/prime-linux" --yes
ck "an older clone hands over to the installed copy"       "grep -q 'INSTALLED-COPY-RAN --dry-run --yes' $T/out"
ck "and says why"                                           "grep -q 'never takes Prime back' $T/out"
ck "the installed copy is untouched"                        "[ \"\$(git -C $INSTALLED log -1 --format=%s)\" = new ]"
PRIME_ALLOW_DOWNGRADE=1 run_install "$HOME/prime-linux"
ck "PRIME_ALLOW_DOWNGRADE=1 installs the old one anyway"    "! grep -q INSTALLED-COPY-RAN $T/out && grep -q 'pacman not found' $T/out"

# restarted history: nothing in common, the clone's commit is older
rm -rf "$INSTALLED"; git init -q "$INSTALLED"; printf '%s\n' "$STUB" > "$INSTALLED/install.sh"
git -C "$INSTALLED" add -A; commit "$INSTALLED" 2026-10-13T12:00 restarted
run_install "$HOME/prime-linux"
ck "no history in common: the older one still hands over"   "grep -q INSTALLED-COPY-RAN $T/out"

# a newer source installs as before
GIT_COMMITTER_DATE=2026-09-01T12:00 git -C "$INSTALLED" commit -q --amend --no-edit
run_install "$HOME/prime-linux"
ck "a newer source is installed (not handed over)"          "! grep -q INSTALLED-COPY-RAN $T/out && grep -q 'pacman not found' $T/out"

echo "prime-update after GitHub's history was restarted"
rm -rf "$INSTALLED" "$T/one"
git init -q "$T/old"; cp -a "$ROOT/layer" "$T/old/"; git -C "$T/old" add -A; commit "$T/old" 2026-10-02T12:00 old
git init -q "$T/new"; cp -a "$ROOT/layer" "$T/new/"; echo new > "$T/new/NEW"; git -C "$T/new" add -A; commit "$T/new" 2026-10-13T12:00 new
git clone -q --bare "$T/new" "$T/github.git"
git clone -q "$T/old" "$INSTALLED"; git -C "$INSTALLED" remote set-url origin "$T/github.git"
mkdir -p "$HOME/.config/systemd/user"
up() { env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE PRIME_NO_PANEL=1 PRIME_NO_LIVE=1 PRIME_NO_GSETTINGS=1 \
        timeout 120 bash "$INSTALLED/layer/bin/prime-update" --prime > "$T/out" 2>&1 </dev/null; }
echo edited >> "$INSTALLED/layer/bin/prime-about"
up
ck "edited files: left alone"                               "[ \"\$(git -C $INSTALLED log -1 --format=%s)\" = old ] && grep -q 'were edited' $T/out"
git -C "$INSTALLED" checkout -q -- layer/bin/prime-about
up
ck "unedited copy: moves to the new history"                "[ \"\$(git -C $INSTALLED log -1 --format=%s)\" = new ] && [ -f $INSTALLED/NEW ]"
ck "and says so"                                            "grep -q 'history was restarted' $T/out"

[ $fail = 0 ] || sed 's/^/      | /' "$T/out" | tail -20
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
