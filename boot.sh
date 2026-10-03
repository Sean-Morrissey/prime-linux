#!/usr/bin/env bash
# Prime Linux — the one-line install on a fresh CachyOS:
#
#   curl -fsSL https://raw.githubusercontent.com/sean-morrissey/prime-linux/stable/boot.sh | bash
#
# It fetches Prime Linux into ~/.local/share/prime-linux with git, then runs
# install.sh from there. Anything after "bash -s --" is passed to install.sh:
#   curl -fsSL …/boot.sh | bash -s -- --dry-run
#
# Settings (environment):
#   PRIME_REPO     where to get it   (default: the GitHub repo; a local path works)
#   PRIME_REF      branch or tag     (default: stable — the latest signed release; main is the test channel)
#
# The repository is public, so the line above needs no GitHub account and no
# sign-in. If it is ever made private, `curl` can't read it: clone it with your
# GitHub login (gh repo clone sean-morrissey/prime-linux) and run
# `bash prime-linux/install.sh`, or point PRIME_REPO at a URL you can read
# (PRIME_REPO=git@github.com:sean-morrissey/prime-linux.git).
#
# On the stable channel nothing runs until the download is checked: it must be a
# v* release tag signed by Prime's release key (fingerprint below — compare it with
# docs/RELEASE.md). Other channels (PRIME_REF=main) are for testers and unsigned.
#
# Everything is inside main(), which runs on the last line: if the download is
# cut off half-way, bash has nothing to run instead of half a script.
set -euo pipefail

PRIME_RELEASE_FPR="${PRIME_RELEASE_FPR_TEST:-9E04CC6DCD67F5DC95FECB8654BBD88772267D63}"   # _TEST: tests only

# signed_release <dir> → 0 when the checked-out commit carries a v* tag signed by that key
signed_release() {
    local dir="$1" ring t ok=1
    command -v gpg >/dev/null || { echo "  gpg is missing, so the download can't be checked." >&2; return 1; }
    ring="$(mktemp -d)"; chmod 700 "$ring"
    if gpg --homedir "$ring" --batch --quiet --import < "$dir/layer/system/release/release-keys.asc" 2>/dev/null; then
        for t in $(git -C "$dir" tag --points-at HEAD --list 'v*'); do
            # VALIDSIG's last field is the signing key's primary fingerprint
            if GNUPGHOME="$ring" git -C "$dir" -c gpg.format=openpgp verify-tag --raw "$t" 2>&1 >/dev/null \
                    | awk '$2 == "VALIDSIG" {print $NF}' | grep -qx "$PRIME_RELEASE_FPR"; then
                ok=0; break
            fi
        done
    fi
    gpgconf --homedir "$ring" --kill all >/dev/null 2>&1 || true
    rm -rf "$ring"
    return $ok
}

main() {
    local repo="${PRIME_REPO:-https://github.com/sean-morrissey/prime-linux.git}"
    local ref="${PRIME_REF:-${PRIME_BRANCH:-stable}}"
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
                echo "  · GitHub unreachable from here? try again in a minute" >&2
                echo "  · a private copy of the repository needs a login — see the top of boot.sh" >&2
                exit 1
            fi
            sleep 3
        done
    fi

    if [ "$ref" = stable ] || [ "${PRIME_REQUIRE_SIGNED:-0}" = 1 ]; then
        if signed_release "$dest"; then
            echo "  Checked: a signed Prime Linux release ($(git -C "$dest" describe --tags --always))"
        else
            echo "This download isn't a Prime Linux release signed by Prime's release key, so nothing was installed." >&2
            echo "  Try again in a few minutes; if it keeps happening, please open an issue on GitHub." >&2
            exit 1
        fi
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
