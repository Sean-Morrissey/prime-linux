#!/usr/bin/env bash
# tests/check-shellcheck.sh — every shell script in the repo passes shellcheck at
# warning level. CI installed shellcheck but nothing ran it, so only `bash -n`
# guarded the scripts that run as root or touch people's files.
#
# Left out on purpose, with the reason (each is noise in this codebase, not a bug):
#   SC1090/SC1091  sourcing a path built at run time (add-ons, os-release)
#   SC2034         colour and layout variables set for every script, used by some
#   SC2154         variables that come from a sourced helper
#   SC2088         "~/…" inside messages meant for people, never expanded
#   SC1111         typographic quotes inside messages
#   SC2010         `ls | grep` over Prime's own fixed names
#   SC2174         `mkdir -p -m 700` where only the last folder needs to be private
#   SC2054         qemu arguments are comma lists by design (-drive if=…,format=…)
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
SC="$(command -v shellcheck || true)"
if [ -z "$SC" ]; then echo "  SKIP  shellcheck is not installed"; exit 0; fi
mapfile -t files < <(git ls-files | while read -r f; do
    [ -f "$f" ] || continue
    case "$f" in *.sh) echo "$f"; continue ;; esac
    head -c 64 "$f" | grep -qE '^#!.*\b(bash|sh)\b' && echo "$f"
done | sort -u)
if "$SC" -S warning -e SC1090,SC1091,SC2034,SC2154,SC2088,SC1111,SC2010,SC2174,SC2054 "${files[@]}"; then
    echo "  PASS  ${#files[@]} shell scripts, shellcheck $("$SC" --version | sed -n 's/^version: //p')"
    echo; echo "ALL PASSED"
else
    echo; echo "FAILED — fix the warnings above (or, if one is truly intended, disable it on that line with a reason)"; exit 1
fi
