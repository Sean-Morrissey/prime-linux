#!/usr/bin/env bash
# tools/release-sign.sh — make Prime's release key, and sign a release tag with it.
#
#   tools/release-sign.sh --new-key            make a signing key in your GnuPG keyring
#                                              (ed25519, asks for a passphrase) and put its
#                                              public half in layer/system/release/release-keys.asc
#   tools/release-sign.sh v2026.10.0           sign that tag on HEAD (creates it, with the
#                                              CHANGELOG notes), then check it like computers will
#   tools/release-sign.sh --verify v2026.10.0  check a tag exactly as installed computers do
#
# Keep a backup of the secret key offline (gpg --export-secret-keys --armor), and
# don't keep it on a computer that runs untrusted code. Losing it means publishing a
# new key in an update signed by the old one — or, if both are gone, a reinstall.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
KEYS=layer/system/release/release-keys.asc
UID_="${PRIME_RELEASE_UID:-Prime Linux release key <release@prime-linux.invalid>}"
keyid() { gpg --list-secret-keys --with-colons "$UID_" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}'; }
case "${1:-}" in
  --new-key)
    [ -n "$(keyid)" ] && { echo "a key for \"$UID_\" already exists ($(keyid)) — not making another" >&2; exit 1; }
    gpg --quick-generate-key "$UID_" ed25519 sign 5y
    gpg --export --armor "$(keyid)" >> "$KEYS"
    echo "Fingerprint: $(keyid)  — publish it in the README and the release notes."
    echo "Added to $KEYS. Commit it, then sign the next release: tools/release-sign.sh vYYYY.MM.N" ;;
  --verify)
    t="${2:?which tag?}"; c="$(git rev-parse "$t^{commit}")"
    PRIME_REQUIRE_SIGNED=1 PRIME_RELEASE_KEYS="$KEYS" layer/bin/prime-release-verify . "$c" ;;
  v*)
    [ -n "$(keyid)" ] || { echo "no release key in your keyring — tools/release-sign.sh --new-key first" >&2; exit 1; }
    notes="$(sed -n "/^## $1/,/^## v/p" CHANGELOG.md 2>/dev/null | sed '$d')"
    git -c gpg.format=openpgp tag -s -u "$(keyid)" "$1" -m "${notes:-Prime Linux $1}"
    PRIME_REQUIRE_SIGNED=1 PRIME_RELEASE_KEYS="$KEYS" layer/bin/prime-release-verify . "$(git rev-parse "$1^{commit}")"
    echo "Signed $1. Publish: git push origin $1, then fast-forward stable (docs/RELEASE.md)." ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
