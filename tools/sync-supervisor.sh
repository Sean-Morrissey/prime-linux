#!/usr/bin/env bash
# Copy the supervisor from backends/arch/ into the file layer that the image build
# ships from. backends/arch/ is the source of truth — it is where the code is tested
# — but BlueBuild can only copy files that live under files/system/, so the two have
# to be kept identical. CI runs this and fails if anything drifts, which means the
# shipped copy can never quietly go stale.
#
# Run after changing anything in backends/arch/:  bash tools/sync-supervisor.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/backends/arch"
DST="$ROOT/files/system/usr/libexec/prime"

FILES=(prime prime-autoupdate prime-setup backend-bootc.sh backend-sandbox.sh backend-btrfs.sh)

mkdir -p "$DST"
for f in "${FILES[@]}"; do
  if [ ! -r "$SRC/$f" ]; then
    echo "missing: $SRC/$f" >&2
    exit 1
  fi
  install -m 0755 "$SRC/$f" "$DST/$f"
  echo "  synced $f"
done
echo "supervisor synced into files/system/usr/libexec/prime/"
