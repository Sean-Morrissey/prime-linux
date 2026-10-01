#!/usr/bin/env bash
# Prime Linux — one-line install on a fresh CachyOS:
#   curl -fsSL https://raw.githubusercontent.com/sean-morrissey/prime-linux/main/boot.sh | bash
set -euo pipefail
REPO="${PRIME_REPO:-https://github.com/sean-morrissey/prime-linux.git}"
BRANCH="${PRIME_BRANCH:-main}"
DEST="$HOME/.local/share/prime-linux"
command -v git >/dev/null || sudo pacman -S --needed --noconfirm git
if [ -d "$DEST/.git" ]; then git -C "$DEST" pull --ff-only
else git clone --depth 1 --branch "$BRANCH" "$REPO" "$DEST"; fi
exec bash "$DEST/install.sh" "$@" </dev/tty
