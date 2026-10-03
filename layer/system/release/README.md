# Prime Linux release keys

`release-keys.asc` holds the public half of Prime's release signing key(s),
ASCII-armored (`gpg --export --armor`).

Current key (ed25519, made 2026-10-03, expires 2031-10-02):

    Prime Linux release key <release@prime-linux.invalid>
    9E04 CC6D CD67 F5DC 95FE  CB86 54BB D887 7226 7D63

An earlier key (28E8 CC02 … D4FD 54FB, made 2026-10-02) was replaced before any
release was signed with it, so no computer ever trusted it. Nothing to rotate:
this file holds one key, and v2026.10.0 is the first release of any kind.

Every computer keeps the copy it was installed with. An update on the `stable`
channel is installed only when its `v*` tag is signed by a key in THAT copy
(`layer/bin/prime-release-verify`) — so a new key can only arrive inside an
update an existing key signed. GnuPG does the checking; it is already on every
Arch/CachyOS machine (pacman uses it), so nothing extra is installed.
See docs/RELEASE.md → Signing.
