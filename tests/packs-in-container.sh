#!/usr/bin/env bash
# Install Prime Linux into a throwaway Arch container as "alex", run the normal
# install checks, then enable/disable every pack non-interactively (check-packs.sh).
# Needs docker. Nothing touches this machine.
#
#   tests/packs-in-container.sh                 resolve every package/Flathub id, install none (fast)
#   FULL=1 tests/packs-in-container.sh          really install every pack (many GB, slow)
#   PRIME_GPU=amd tests/packs-in-container.sh   pretend the machine has an AMD card
#   KEEP=1 …                                    leave the container for poking around
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
NAME="prime-packs-test-$$"
trap '[ "${KEEP:-0}" = 1 ] || docker rm -f "$NAME" >/dev/null 2>&1' EXIT

# same cached base image as install-in-container.sh
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
    install -d -m 700 -o alex -g alex /run/user/$(id -u alex) && touch /home/alex/.bashrc && chown alex: /home/alex/.bashrc &&
    pacman -Sy >/dev/null'
git -C "$REPO" bundle create /tmp/prime-$$.bundle HEAD >/dev/null 2>&1
docker cp /tmp/prime-$$.bundle "$NAME":/tmp/prime.bundle; rm -f /tmp/prime-$$.bundle
docker exec -u alex "$NAME" git clone -q /tmp/prime.bundle /home/alex/src
docker cp "$REPO/." "$NAME":/home/alex/src-worktree    # uncommitted changes too
docker exec "$NAME" bash -c 'rm -rf /home/alex/src-worktree/.git && cp -a /home/alex/src-worktree/. /home/alex/src/ &&
    chown -R alex: /home/alex/src && cd /home/alex/src && sudo -u alex git add -A && sudo -u alex git -c user.name=t -c user.email=t@t commit -qm wip || true'

ENV=(-e HOME=/home/alex -e XDG_RUNTIME_DIR=/run/user/1000 -e USER=alex -e "PRIME_GPU=${PRIME_GPU:-none}"
     -e "PRIME_ADDON_PACKAGES=$([ "${FULL:-0}" = 1 ] && echo install || echo check)")
echo "== install"
docker exec -u alex "${ENV[@]}" "$NAME" bash /home/alex/src/install.sh >/dev/null
echo "== install checks"
docker cp "$REPO/tests/check-install.sh" "$NAME":/tmp/check-install.sh
docker exec -u alex "${ENV[@]}" "$NAME" bash /tmp/check-install.sh | tail -1
# check-install switched the AI add-on on; start the packs from a clean list
docker exec -u alex "${ENV[@]}" "$NAME" bash -c 'sed -i "/^ai\$/d" ~/.config/prime/addons && ~/.local/share/prime-linux/layer/bin/prime-addon --relink'
echo "== packs"
docker cp "$REPO/tests/check-packs.sh" "$NAME":/tmp/check-packs.sh
docker exec -u alex "${ENV[@]}" "$NAME" bash /tmp/check-packs.sh
