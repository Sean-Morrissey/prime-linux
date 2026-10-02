#!/usr/bin/env bash
# Prime Linux — the one-line install on a fresh CachyOS:
#
#   curl -fsSL https://raw.githubusercontent.com/sean-morrissey/prime-linux/main/boot.sh | bash
#
# It fetches Prime Linux into ~/.local/share/prime-linux with git, then runs
# install.sh from there. Anything after "bash -s --" is passed to install.sh:
#   curl -fsSL …/boot.sh | bash -s -- --dry-run
#
# Settings (environment):
#   PRIME_REPO     where to get it   (default: the GitHub repo; a local path works)
#   PRIME_REF      branch or tag     (default: main — "stable" channel = latest tag, see docs/RELEASE.md)
#
# While the repository is private, `curl` can't read it: clone it yourself with
# your GitHub login (gh repo clone sean-morrissey/prime-linux) and run
# `bash prime-linux/install.sh`, or point PRIME_REPO at a URL you can read
# (PRIME_REPO=git@github.com:sean-morrissey/prime-linux.git).
#
# Everything is inside main(), which runs on the last line: if the download is
# cut off half-way, bash has nothing to run instead of half a script.
set -euo pipefail

main() {
    local repo="${PRIME_REPO:-https://github.com/sean-morrissey/prime-linux.git}"
    local ref="${PRIME_REF:-${PRIME_BRANCH:-main}}"
    local dest="$HOME/.local/share/prime-linux"
    local A=$'\e[38;2;248;113;113m' B=$'\e[1m' R=$'\e[0m'
    printf '\n  %s%sPrime Linux%s — getting the installer\n\n' "$B" "$A" "$R"

    [ "$(id -u)" -ne 0 ] || { echo "Run this as your normal user, not as root (no sudo in front)." >&2; exit 1; }
    command -v pacman >/dev/null || { echo "Prime Linux installs on CachyOS (or Arch Linux) — pacman wasn't found." >&2; exit 1; }
    if ! command -v git >/dev/null; then
        echo "  Installing git first (asks for your password)…"
        sudo pacman -S --needed --noconfirm git
    fi

    local tries=0
    if [ -d "$dest/.git" ]; then
        echo "  Updating the copy in ${dest/#$HOME/\~}"
        until git -C "$dest" fetch --quiet --tags origin "$ref" 2>/dev/null || git -C "$dest" fetch --quiet --tags "$repo" "$ref"; do
            tries=$((tries+1)); [ $tries -lt 3 ] || { echo "Couldn't download Prime Linux (is the internet up?)" >&2; exit 1; }
            sleep 3
        done
        git -C "$dest" checkout --quiet --force FETCH_HEAD
        git -C "$dest" checkout --quiet -B "$ref" 2>/dev/null || true
    else
        if [ -e "$dest" ]; then mv "$dest" "$dest.old-$(date +%s)"; fi
        mkdir -p "$(dirname "$dest")"
        until git clone --quiet --branch "$ref" "$repo" "$dest"; do
            tries=$((tries+1)); rm -rf "$dest"
            if [ $tries -ge 3 ]; then
                echo "Couldn't download Prime Linux from $repo" >&2
                echo "  · not online yet? connect to Wi-Fi from the network icon near the clock, then try again" >&2
                echo "  · private repo? see the comment at the top of boot.sh" >&2
                exit 1
            fi
            sleep 3
        done
    fi

    # install.sh asks questions; with "curl | bash" our stdin is the script itself,
    # so questions go to the terminal. No terminal (automation): --yes.
    if [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null; then
        exec bash "$dest/install.sh" "$@" </dev/tty
    else
        exec bash "$dest/install.sh" --yes "$@"
    fi
}

main "$@"
