#!/usr/bin/env bash
# tests/check-release-signing.sh — on the stable channel an update is installed only
# when it is a v* tag signed by a release key the INSTALLED copy already trusts.
# Builds a throwaway "GitHub" repo and an installed copy, then tries forgeries.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; V="$REPO/layer/bin/prime-release-verify"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if eval "$2" >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -4; fail=$((fail+1)); fi; }
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name t; git config --global user.email t@t; git config --global init.defaultBranch stable
ssh-keygen -q -t ed25519 -N '' -C good -f "$T/good"; ssh-keygen -q -t ed25519 -N '' -C evil -f "$T/evil"
signers() { printf 'prime-release@prime-linux namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$1.pub")"; }
stag() { git -C "$T/up" -c gpg.format=ssh -c user.signingkey="$1.pub" tag -s "$2" -m "$2"; }
commit() { echo "$1" > "$T/up/file"; git -C "$T/up" add -A; git -C "$T/up" commit -qm "$1"; }

git init -q "$T/up"; mkdir -p "$T/up/layer/system/release"
signers "$T/good" > "$T/up/layer/system/release/allowed_signers"
commit v1; stag "$T/good" v1
git clone -q "$T/up" "$T/inst"                      # the installed computer, on stable
fetch() { git -C "$T/inst" fetch -q --tags; }
target() { git -C "$T/inst" rev-parse '@{upstream}'; }

commit v2; stag "$T/good" v2; fetch
ck "a release signed by the trusted key is accepted"     "bash $V $T/inst \$(target)"
commit v3; fetch
ck "an untagged commit pushed to stable is refused"      "! bash $V $T/inst \$(target)"
stag "$T/evil" v3; fetch
ck "a tag signed by an unknown key is refused"           "! bash $V $T/inst \$(target)"
commit v4; git -C "$T/up" tag v4 -m unsigned; fetch
ck "an unsigned (annotated) tag is refused"              "! bash $V $T/inst \$(target)"
# the attacker swaps in their own key in the update itself: the INSTALLED list decides
signers "$T/evil" > "$T/up/layer/system/release/allowed_signers"; commit v5; stag "$T/evil" v5; fetch
ck "an update that brings its own key is still refused"  "! bash $V $T/inst \$(target)"
git -C "$T/inst" merge -q --ff-only "v2^{commit}"
ck "after a good update the computer still trusts the old key only" "grep -qF \"\$(cut -d' ' -f2 $T/good.pub)\" $T/inst/layer/system/release/allowed_signers && ! grep -qF \"\$(cut -d' ' -f2 $T/evil.pub)\" $T/inst/layer/system/release/allowed_signers"
git -C "$T/inst" switch -q -c main
ck "other channels (main, edge) follow the branch unsigned" "bash $V $T/inst \$(git -C $T/inst rev-parse origin/stable) | grep -q 'not checked'"
ck "…unless PRIME_REQUIRE_SIGNED=1"                      "! PRIME_REQUIRE_SIGNED=1 bash $V $T/inst \$(git -C $T/inst rev-parse origin/stable)"
git -C "$T/inst" switch -q stable; : > "$T/inst/layer/system/release/allowed_signers"
ck "no key published yet: allowed, and it says so"       "bash $V $T/inst \$(target) | grep -q 'no release key'"
ck "the shipped key list is valid (comments, or real keys only)" \
   "! grep -vE '^\s*(#|\$)' $REPO/layer/system/release/allowed_signers | grep -vqE '^\S+ namespaces=\"git\" ssh-(ed25519|rsa) '"
ck "prime-update refuses unverified updates before moving" \
   "grep -q 'prime-release-verify' $REPO/layer/bin/prime-update && ! grep -q 'pull --ff-only' $REPO/layer/bin/prime-update"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
