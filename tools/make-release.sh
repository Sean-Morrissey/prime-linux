#!/usr/bin/env bash
# tools/make-release.sh — cut a Prime Linux release: check the gate, sign the tag,
# move the stable channel, and (once) switch everyone's install line to stable.
#
#   tools/make-release.sh v2026.10.0              the real thing (asks before pushing)
#   tools/make-release.sh v2026.10.0 --dry-run    say what it would do, change nothing
#   tools/make-release.sh v2026.10.0 --no-push    do it all locally, push by hand later
#   tools/make-release.sh v2026.10.0 --skip-vm    skip gate 2 (say why in the release notes)
#
# What it does, in order (docs/RELEASE.md → "What releasable means" and "Signing"):
#   1. refuses unless: run on main, nothing uncommitted, the tag is free, CHANGELOG.md
#      has a section for this version, and the release key's private half is here
#   2. runs the gate — syntax, static, the whole fast suite, a clean install and
#      uninstall in a fresh Arch container, every pack on and off, the signing tests,
#      and the real-boot VM evidence
#   3. the first time only: points boot.sh and the install lines in the docs at the
#      stable channel, as its own commit
#   4. signs an annotated tag with the CHANGELOG section as its message
#   5. fast-forwards stable to that tag and verifies it the way a user's computer will
#   6. pushes main, stable and the tag — after showing you exactly what goes
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
KEYS="layer/system/release/release-keys.asc"
VERSION=""; DRY=0; PUSH=1; SKIP_VM=0
for a in "$@"; do case "$a" in
    --dry-run) DRY=1 ;;
    --no-push) PUSH=0 ;;
    --skip-vm) SKIP_VM=1 ;;
    v*) VERSION="$a" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
esac; done

B=$'\e[1m'; G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; N=$'\e[0m'
say()  { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
die()  { printf '  %s✗%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '  would run: %s\n' "$*"; else "$@"; fi; }

[ -n "$VERSION" ] || die "say which version: tools/make-release.sh v2026.10.0"
[[ "$VERSION" =~ ^v20[0-9][0-9]\.(0[1-9]|1[0-2])\.[0-9]+$ ]] || die "version must look like v2026.10.0"

# ── 1. is this a sane place to cut a release from? ────────────────────────────
say "before anything"
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "cut releases from main (you are on $(git rev-parse --abbrev-ref HEAD))"
[ -z "$(git status --porcelain)" ] || die "commit or stash your changes first"
git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null && die "$VERSION already exists"
ok "on main, nothing uncommitted, $VERSION is free"

git fetch -q origin main 2>/dev/null || warn "couldn't reach origin (working offline?)"
if git rev-parse -q --verify origin/main >/dev/null; then
    [ "$(git rev-list --count origin/main..HEAD)" != 0 ] || ok "main matches origin"
fi

NOTES="$(mktemp)"; trap 'rm -f "$NOTES"' EXIT
sed -n "/^## ${VERSION} /,/^## v/p" CHANGELOG.md | sed '${/^## v/d}' > "$NOTES"
[ -s "$NOTES" ] || die "CHANGELOG.md has no section headed '## $VERSION — <date>'"
ok "changelog section found ($(wc -l < "$NOTES") lines)"

grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$KEYS" || die "$KEYS holds no key — nothing a user's computer could check a release against"
FPR="$(gpg --show-keys --with-colons "$KEYS" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
[ -n "$FPR" ] || die "couldn't read a fingerprint out of $KEYS"
gpg --list-secret-keys "$FPR" >/dev/null 2>&1 || die "the private half of $FPR isn't on this computer — the release key must sign the tag"
ok "release key $FPR, private half present"

# ── 2. the gate ──────────────────────────────────────────────────────────────
say "the gate (docs/RELEASE.md)"
gate() { # gate <name> <command…>
    local name="$1"; shift
    if [ "$DRY" = 1 ]; then printf '  would check: %s\n' "$name"; return 0; fi
    local log; log="$(mktemp)"
    if "$@" >"$log" 2>&1; then ok "$name"; rm -f "$log"
    else printf '  %s✗%s %s — last lines:\n' "$R" "$N" "$name"; tail -15 "$log" | sed 's/^/        /'; die "gate failed: $name (full log: $log)"; fi
}
gate "syntax (bash -n, Python AST, JSON)"      bash tests/check-syntax.sh
gate "static suite"                            env PRIME_REQUIRE_GUI=1 bash tests/check-static.sh
gate "menus and Start menu"                    bash tests/check-menus.sh
gate "settings app"                            env PRIME_REQUIRE_GUI=1 bash tests/check-settings-app.sh
gate "repairs are buttons, never commands"     bash tests/check-plain-fixes.sh
gate "remote login (SSH) safety"            bash tests/check-ssh.sh
gate "no trace of this machine"                bash tests/check-portable.sh
gate "stable installs only signed releases"    bash tests/check-release-signing.sh
gate "title bars rebuild themselves"           bash tests/check-titlebars.sh
gate "nightly updater, installer, security"    bash backends/arch/test-system-update.sh
gate "clean install + uninstall (container)"   bash tests/install-in-container.sh
gate "every pack on and off (container)"       env PRIME_GPU=amd bash tests/packs-in-container.sh

SHOT="tests/vm/.work/desktop.png"
if [ "$SKIP_VM" = 1 ]; then
    warn "gate 2 (real CachyOS VM boot) skipped — say so in the release notes"
elif [ -s "$SHOT" ]; then
    ok "real-boot VM evidence: $SHOT ($(date -r "$SHOT" '+%F %H:%M'))"
    [ "$(find "$SHOT" -mtime +7 2>/dev/null)" ] && warn "that screenshot is over a week old — consider tests/vm/run.sh all again"
else
    die "no real-boot evidence ($SHOT). Run: tests/vm/run.sh all   (or --skip-vm)"
fi

# ── 3. the channel flip, the first time only ─────────────────────────────────
say "the install line"
if grep -q 'PRIME_BRANCH:-main' boot.sh; then
    run sed -i 's/PRIME_BRANCH:-main/PRIME_BRANCH:-stable/' boot.sh
    run sed -i 's#prime-linux/main/boot.sh#prime-linux/stable/boot.sh#g' README.md docs/USER-GUIDE.md
    if [ "$DRY" = 0 ]; then
        bash -n boot.sh || die "boot.sh no longer parses after the edit"
        git add boot.sh README.md docs/USER-GUIDE.md
        git commit -qm "The install line follows the stable channel

$VERSION is the first signed release, so boot.sh and the install lines in the
README and user guide now point at stable instead of main. main stays the test
channel: prime-update follows whichever branch is checked out."
    fi
    ok "boot.sh and the docs now point at stable"
else
    ok "already pointing at stable"
fi

# ── 4. sign the tag ──────────────────────────────────────────────────────────
say "signing $VERSION"
run git -c gpg.format=openpgp tag -s -u "$FPR" -F "$NOTES" "$VERSION"
if [ "$DRY" = 0 ]; then
    git tag -v "$VERSION" >/dev/null 2>&1 || die "the tag didn't verify straight after signing"
    ok "annotated, signed by $FPR, message = the changelog section"
fi

# ── 5. move stable, then check it the way a user's computer will ─────────────
say "the stable channel"
if [ "$DRY" = 0 ]; then
    if git rev-parse -q --verify refs/heads/stable >/dev/null; then
        git branch -f stable "$VERSION" || die "couldn't move stable to $VERSION"
    else
        git branch stable "$VERSION"
    fi
    ok "stable → $VERSION"

    T="$(mktemp -d)"; trap 'rm -rf "$T"; rm -f "$NOTES"' EXIT
    git clone -q --branch stable "$REPO" "$T/inst" 2>/dev/null || die "couldn't clone a test copy"
    git -C "$T/inst" fetch -q --tags "$REPO" 2>/dev/null
    if bash layer/bin/prime-release-verify "$T/inst" "$(git rev-parse "$VERSION")" >"$T/out" 2>&1; then
        ok "a user's computer would accept it: $(tail -1 "$T/out")"
    else
        cat "$T/out" | sed 's/^/        /'; die "prime-release-verify refused this release"
    fi
else
    printf '  would move stable to %s and verify it with prime-release-verify\n' "$VERSION"
fi

# ── 6. push ──────────────────────────────────────────────────────────────────
say "what would go to GitHub"
printf '    main    %s\n' "$(git rev-parse --short main)"
printf '    stable  %s  (%s)\n' "$(git rev-parse --short stable 2>/dev/null || echo '—')" "$VERSION"
printf '    tag     %s  signed by %s\n' "$VERSION" "$FPR"
echo
if [ "$DRY" = 1 ]; then say "dry run — nothing was changed"; exit 0; fi
if [ "$PUSH" = 0 ]; then say "not pushing (--no-push). When you are ready:"; echo "    git push origin main stable $VERSION"; exit 0; fi

printf 'Push these to origin? Every machine on the stable channel follows it. [y/N] '
read -r reply
case "$reply" in
    y|Y|yes|YES) git push origin main stable "$VERSION" && say "released $VERSION" ;;
    *) say "not pushed. When you are ready:"; echo "    git push origin main stable $VERSION" ;;
esac
