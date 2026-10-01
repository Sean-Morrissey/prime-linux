#!/usr/bin/env bash
# Install Prime Linux into a throwaway Arch container as a brand-new user
# ("alex") and check the result. Needs docker. Nothing touches this machine.
#
#   tests/install-in-container.sh            full run (downloads packages, ~10 min first time)
#   KEEP=1 tests/install-in-container.sh     leave the container for poking around
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
NAME="prime-install-test-$$"
trap '[ "${KEEP:-0}" = 1 ] || docker rm -f "$NAME" >/dev/null 2>&1' EXIT

# the package download is the slow part — cache it as an image keyed on packages.txt
BASE="prime-test-base:$(sha256sum "$REPO/os/arch/packages.txt" | cut -c1-12)"
if ! docker image inspect "$BASE" >/dev/null 2>&1; then
    echo "== building $BASE (one-time package download)"
    docker run -d --name "$NAME-base" archlinux:latest sleep infinity >/dev/null
    docker cp "$REPO/os/arch/packages.txt" "$NAME-base":/tmp/packages.txt
    docker exec "$NAME-base" bash -c 'pacman -Syu --noconfirm --needed sudo git $(grep -vE "^\s*(#|$)" /tmp/packages.txt) >/dev/null 2>&1; pacman -Q hyprland waybar >/dev/null'
    docker commit "$NAME-base" "$BASE" >/dev/null; docker rm -f "$NAME-base" >/dev/null
fi
docker run -d --name "$NAME" "$BASE" sleep infinity >/dev/null
docker exec "$NAME" bash -c 'useradd -m alex && echo "alex ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/alex &&
    install -d -m 700 -o alex -g alex /run/user/$(id -u alex)'
# hand the checkout over as a git repo, exactly like boot.sh would clone it
git -C "$REPO" bundle create /tmp/prime-$$.bundle HEAD >/dev/null 2>&1
docker cp /tmp/prime-$$.bundle "$NAME":/tmp/prime.bundle; rm -f /tmp/prime-$$.bundle
docker exec -u alex "$NAME" git clone -q /tmp/prime.bundle /home/alex/src
docker cp "$REPO/." "$NAME":/home/alex/src-worktree    # uncommitted changes too
docker exec "$NAME" bash -c 'rm -rf /home/alex/src-worktree/.git && cp -a /home/alex/src-worktree/. /home/alex/src/ &&
    chown -R alex: /home/alex/src && cd /home/alex/src && sudo -u alex git add -A && sudo -u alex git -c user.name=t -c user.email=t@t commit -qm wip || true'

# GSETTINGS_BACKEND=keyfile: no D-Bus session in a container, but the theme
# settings must persist between commands for the uninstall check to mean anything
AS_ALEX=(docker exec -u alex -e HOME=/home/alex -e XDG_RUNTIME_DIR=/run/user/1000 -e GSETTINGS_BACKEND=keyfile "$NAME")

# a stranger's account is never empty: an old terminal config Prime must back up and restore
"${AS_ALEX[@]}" bash -c 'mkdir -p ~/.config/kitty && echo "# my settings, before-prime" > ~/.config/kitty/kitty.conf
    for k in gtk-theme icon-theme font-name; do echo "$k $(gsettings get org.gnome.desktop.interface $k)"; done > /tmp/gsettings-before'

echo "== install"
"${AS_ALEX[@]}" bash /home/alex/src/install.sh --yes

echo "== checks"
docker cp "$REPO/tests/check-install.sh" "$NAME":/tmp/check-install.sh
docker cp "$REPO/tests/check-uninstall.sh" "$NAME":/tmp/check-uninstall.sh
rc=0
"${AS_ALEX[@]}" env PRIME_TEST_PLANTED_CONFIG=1 bash /tmp/check-install.sh || rc=$?

echo "== uninstall"
"${AS_ALEX[@]}" bash /tmp/check-uninstall.sh || rc=$((rc + $?))
exit $rc
