#!/usr/bin/env bash
# Install Prime Linux into a throwaway Arch container as user "alex", then put
# the system pieces in place exactly as the installer will (install-system.sh)
# and run check-system-install.sh. Needs docker; nothing touches this machine.
#
#   bash backends/arch/test-system-in-container.sh          checks (a few minutes)
#   FULL=1 bash backends/arch/test-system-in-container.sh   + a real system update in the container
#   KEEP=1 …                                                leave the container running
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
NAME="prime-system-test-$$"
trap '[ "${KEEP:-0}" = 1 ] || docker rm -f "$NAME" >/dev/null 2>&1' EXIT
BASE="prime-test-base:$(sha256sum "$REPO/os/arch/packages.txt" | cut -c1-12)"
docker image inspect "$BASE" >/dev/null 2>&1 || { echo "run tests/install-in-container.sh once first (builds $BASE)"; exit 2; }
docker run -d --name "$NAME" "$BASE" sleep infinity >/dev/null
docker exec "$NAME" bash -c 'useradd -m alex && echo "alex ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/alex &&
    install -d -m 700 -o alex -g alex /run/user/$(id -u alex)'
git -C "$REPO" bundle create "/tmp/prime-sys-$$.bundle" HEAD >/dev/null 2>&1
docker cp "/tmp/prime-sys-$$.bundle" "$NAME":/tmp/prime.bundle; rm -f "/tmp/prime-sys-$$.bundle"
docker exec -u alex "$NAME" git clone -q /tmp/prime.bundle /home/alex/src
docker cp "$REPO/." "$NAME":/home/alex/src-worktree
docker exec "$NAME" bash -c 'rm -rf /home/alex/src-worktree/.git && cp -a /home/alex/src-worktree/. /home/alex/src/ &&
    chown -R alex: /home/alex/src && cd /home/alex/src && sudo -u alex git add -A && sudo -u alex git -c user.name=t -c user.email=t@t commit -qm wip || true'
run() { docker exec -u alex -e HOME=/home/alex -e XDG_RUNTIME_DIR=/run/user/1000 -e FULL="${FULL:-0}" "$NAME" "$@"; }

echo "== install (desktop layer)"
run bash /home/alex/src/install.sh --no-packages >/dev/null
echo "== install (system pieces — what install.sh's integration step will run)"
run bash -c 'sudo bash ~/.local/share/prime-linux/layer/system/install-system.sh install --user alex'
echo "== checks"
docker cp "$REPO/backends/arch/check-system-install.sh" "$NAME":/tmp/check-system-install.sh
run bash /tmp/check-system-install.sh
