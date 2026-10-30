#!/usr/bin/env bash
# tests/check-release-signing.sh — on the stable channel an update is installed only
# when it is a v* tag signed by a release key the INSTALLED copy already trusts.
# Builds a throwaway "GitHub" repo and an installed copy, then tries forgeries.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; V="$REPO/layer/bin/prime-release-verify"; fail=0
T="$(mktemp -d)"; trap 'gpgconf --homedir "$T/gpg" --kill all >/dev/null 2>&1; rm -rf "$T"' EXIT
ck() { if eval "$2" >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -4; fail=$((fail+1)); fi; }
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1 GNUPGHOME="$T/gpg"
mkdir -m 700 "$T/gpg"
git config --global user.name t; git config --global user.email t@t; git config --global init.defaultBranch stable
for who in good evil; do gpg --batch --quiet --passphrase '' --quick-generate-key "$who <$who@test.invalid>" ed25519 sign never; done
fpr() { gpg --list-keys --with-colons "$1" | awk -F: '/^fpr:/ {print $10; exit}'; }
pub() { gpg --export --armor "$(fpr "$1")"; }
stag() { git -C "$T/up" -c gpg.format=openpgp tag -s -u "$(fpr "$1")" "$2" -m "$2"; }
commit() { echo "$1" > "$T/up/file"; git -C "$T/up" add -A; git -C "$T/up" commit -qm "$1"; }
KEYS=layer/system/release/release-keys.asc

git init -q "$T/up"; mkdir -p "$T/up/layer/system/release"
pub good > "$T/up/$KEYS"
commit v1; stag good v1
git clone -q "$T/up" "$T/inst"                      # the installed computer, on stable
fetch() { git -C "$T/inst" fetch -q --tags; }
target() { git -C "$T/inst" rev-parse '@{upstream}'; }
# the person's own keyring trusts the evil key too: it must not matter
export GNUPGHOME="$T/gpg"

commit v2; stag good v2; fetch
ck "a release signed by the trusted key is accepted"     "bash $V $T/inst \$(target)"
commit v3; fetch
ck "an untagged commit pushed to stable is refused"      "! bash $V $T/inst \$(target)"
stag evil v3; fetch
ck "a tag signed by another key is refused (even one in your own keyring)" "! bash $V $T/inst \$(target)"
commit v4; git -C "$T/up" tag v4 -m unsigned; fetch
ck "an unsigned (annotated) tag is refused"              "! bash $V $T/inst \$(target)"
# the attacker ships their own key in the update itself: the INSTALLED file decides
pub evil > "$T/up/$KEYS"; commit v5; stag evil v5; fetch
ck "an update that brings its own key is still refused"  "! bash $V $T/inst \$(target)"
git -C "$T/inst" merge -q --ff-only "v2^{commit}"
ck "after a good update the computer still trusts only the old key" \
   "diff <(pub good) $T/inst/$KEYS"
git -C "$T/inst" switch -q -c main
ck "other channels (main, edge) follow the branch unsigned" "bash $V $T/inst \$(git -C $T/inst rev-parse origin/stable) | grep -q 'not checked'"
ck "…unless PRIME_REQUIRE_SIGNED=1"                      "! PRIME_REQUIRE_SIGNED=1 bash $V $T/inst \$(git -C $T/inst rev-parse origin/stable)"
git -C "$T/inst" switch -q stable; : > "$T/inst/$KEYS"
ck "no key published yet: allowed, and it says so"       "bash $V $T/inst \$(target) | grep -q 'no release key'"
printf -- '-----BEGIN PGP PUBLIC KEY BLOCK-----\nnope\n' > "$T/inst/$KEYS"
ck "a damaged key file refuses, never allows"            "! bash $V $T/inst \$(target)"
ck "the shipped key file is empty or real keys"          "[ ! -s $REPO/$KEYS ] || grep -q 'BEGIN PGP PUBLIC KEY BLOCK' $REPO/$KEYS"
ck "nothing extra to install (no SSH server, no new package)" "! grep -qxE 'openssh|gnupg' $REPO/os/arch/packages.txt"
ck "prime-update checks before it moves"                 "grep -q 'prime-release-verify' $REPO/layer/bin/prime-update && ! grep -q 'pull --ff-only' $REPO/layer/bin/prime-update"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
