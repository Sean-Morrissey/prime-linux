#!/usr/bin/env bash
# Provision the test VM with Prime Linux, unattended.
# Runs entirely inside the VM: the host desktop is never touched.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${PRIME_REPO_DIR:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$HOME/Projects/prime-linux")}"
VM_DIR="${PRIME_VM_DIR:-$HOME/VMs/prime}"
[ -f "$SCRIPT_DIR/id_ed25519" ] && VM_DIR="$SCRIPT_DIR"
cd "$VM_DIR"

LOG="$VM_DIR/provision.log"
SSH=(ssh -F /dev/null -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -i "$VM_DIR/id_ed25519" -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes sean@127.0.0.1)

say() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

say "waiting for cloud-init to finish"
"${SSH[@]}" 'cloud-init status --wait' >>"$LOG" 2>&1 || true
say "cloud-init: $("${SSH[@]}" 'cloud-init status --long | head -1' 2>/dev/null)"

say "copying the repo ($REPO_DIR) into the VM"
# tar, not rsync: the VM image has no rsync and installing one would need a
# second package sync just to copy files.
# .git is required: install.sh refuses to run outside a git checkout ("fatal:
# not a git repository"), and the layer it installs is itself a checkout.
tar -C "$REPO_DIR" --exclude tests/e2e/results --exclude tests/vm/vm-results -cf - . \
  | "${SSH[@]}" 'rm -rf ~/prime-linux && mkdir -p ~/prime-linux && tar -C ~/prime-linux -xf -' >>"$LOG" 2>&1

say "running install.sh --yes inside the VM (this is the long step)"
"${SSH[@]}" 'cd ~/prime-linux && bash install.sh --yes' >>"$LOG" 2>&1
say "install finished, exit $?"

say "verifying the layer landed"
"${SSH[@]}" 'ls -d ~/.local/share/prime-linux/layer && git -C ~/.local/share/prime-linux status --porcelain | wc -l' >>"$LOG" 2>&1
say "done — see $LOG"
