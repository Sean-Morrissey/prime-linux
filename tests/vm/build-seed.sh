#!/usr/bin/env bash
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VM_DIR="${PRIME_VM_DIR:-$HOME/VMs/prime}"
[ -d "$SCRIPT_DIR/seed" ] && VM_DIR="$SCRIPT_DIR"
cd "$VM_DIR"
rm -f seed.iso
xorriso -as mkisofs -output seed.iso -volid cidata -joliet -rock \
    seed/user-data seed/meta-data >/dev/null 2>&1
echo "seed.iso: $(du -h seed.iso | cut -f1)"
