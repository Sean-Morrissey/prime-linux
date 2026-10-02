#!/usr/bin/env bash
# tools/release-sign.sh — make Prime's release key, and sign a release tag with it.
#
#   tools/release-sign.sh --new-key            make ~/.ssh/prime-release (ed25519, with a
#                                              passphrase) and add its public half to
#                                              layer/system/release/allowed_signers
#   tools/release-sign.sh v2026.10.0           sign that tag on HEAD (creates it)
#   tools/release-sign.sh --verify v2026.10.0  check a tag the way installed computers will
#
# Keep the private key OFF any computer that runs untrusted code, with a backup
# offline. Losing it means publishing a new key in an update signed by the old
# one — or, if the old one is gone too, asking everyone to reinstall.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
KEY="${PRIME_RELEASE_KEY:-$HOME/.ssh/prime-release}"
SIGNERS=layer/system/release/allowed_signers
case "${1:-}" in
  --new-key)
    [ -e "$KEY" ] && { echo "$KEY already exists — not overwriting it" >&2; exit 1; }
    ssh-keygen -t ed25519 -C "prime-release" -f "$KEY"
    printf 'prime-release@prime-linux namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$KEY.pub")" >> "$SIGNERS"
    echo "Added to $SIGNERS. Commit it, then sign the next release: tools/release-sign.sh vYYYY.MM.N" ;;
  --verify)
    t="${2:?which tag?}"
    git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$SIGNERS" verify-tag "$t" && echo "$t: good signature" ;;
  v*)
    notes="$(sed -n "/^## $1/,/^## v/p" CHANGELOG.md 2>/dev/null | sed '$d')"   # the release notes, as before
    git -c gpg.format=ssh -c user.signingkey="$KEY.pub" tag -s "$1" -m "${notes:-Prime Linux $1}"
    git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$SIGNERS" verify-tag "$1"
    echo "Signed $1. Publish: git push origin $1, then fast-forward stable (docs/RELEASE.md)." ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
