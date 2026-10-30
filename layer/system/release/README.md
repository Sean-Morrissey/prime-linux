# Prime Linux release keys

`release-keys.asc` holds the public half of Prime's release signing key(s),
ASCII-armored (`gpg --export --armor`).

Current key (ed25519, made 2026-10-02, expires 2031-10-01):

    Prime Linux release key <release@prime-linux.invalid>
    28E8 CC02 D92E E130 CC3D  35ED D5F0 D24D D4FD 54FB

Every computer keeps the copy it was installed with. An update on the `stable`
channel is installed only when its `v*` tag is signed by a key in THAT copy
(`layer/bin/prime-release-verify`) — so a new key can only arrive inside an
update an existing key signed. GnuPG does the checking; it is already on every
Arch/CachyOS machine (pacman uses it), so nothing extra is installed.
See docs/RELEASE.md → Signing.
