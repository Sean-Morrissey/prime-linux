# Prime Linux release keys

`release-keys.asc` holds the public half of Prime's release signing key(s),
ASCII-armored (`gpg --export --armor`). It is **empty until the first key is
made** (`tools/release-sign.sh --new-key`).

Every computer keeps the copy it was installed with. An update on the `stable`
channel is installed only when its `v*` tag is signed by a key in THAT copy
(`layer/bin/prime-release-verify`) — so a new key can only arrive inside an
update an existing key signed. GnuPG does the checking; it is already on every
Arch/CachyOS machine (pacman uses it), so nothing extra is installed.
See docs/RELEASE.md → Signing.
