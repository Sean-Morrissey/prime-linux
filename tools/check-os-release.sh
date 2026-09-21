#!/usr/bin/env bash
# Guard the one file the disk build parses strictly.
#
# Two failed disk builds came from this file: a `#` comment line
# ("readOSRelease: invalid input") and a renamed ID ("could not find def file for
# distro primelinux-44"). Neither breaks the image build, so neither shows up until
# someone spends twenty minutes waiting on a disk build. This check takes a
# millisecond and runs before either.
#
# Run: bash tools/check-os-release.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/files/system/usr/lib/os-release"
bad=0

note() { printf '  ✗ %s\n' "$*"; bad=$((bad+1)); }

[ -r "$FILE" ] || { printf '  ✗ missing %s\n' "$FILE"; exit 1; }

# 1. every line must be KEY=VALUE — no comments, no blank lines, no continuation
n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n+1))
  [ -z "$line" ] && note "line $n is blank"
  case "$line" in
    \#*) note "line $n is a comment — the builder's reader fails on these" ;;
    *=*) ;;
    *) note "line $n is not KEY=VALUE: $line" ;;
  esac
done < "$FILE"

# 2. the keys the builder needs, with the values it expects
get() { grep -m1 "^$1=" "$FILE" | cut -d= -f2- | tr -d '"'; }

[ "$(get ID)" = "fedora" ] || note "ID must be 'fedora' (got '$(get ID)') — the builder matches it against its distro definitions"
[ -n "$(get PLATFORM_ID)" ] || note "PLATFORM_ID is missing — the builder reads it to pick a manifest"
[ -n "$(get VERSION_ID)" ] || note "VERSION_ID is missing"
[ "$(get VERSION_ID)" = "44" ] || note "VERSION_ID should be the base Fedora release (44), got '$(get VERSION_ID)'"
for k in NAME PRETTY_NAME VARIANT VARIANT_ID; do
  [ -n "$(get "$k")" ] || note "$k is missing — that is where our branding belongs"
done

# 3. no stray carriage returns (the file is written on Linux, built on Linux)
grep -q $'\r' "$FILE" && note "file contains carriage returns"

if [ "$bad" -eq 0 ]; then
  printf '  ✓ %s is clean (%s lines, ID=%s, VARIANT_ID=%s)\n' \
    "usr/lib/os-release" "$n" "$(get ID)" "$(get VARIANT_ID)"
  exit 0
fi
printf '  %s problem(s) in %s — the disk build will fail on this\n' "$bad" "usr/lib/os-release"
exit 1
