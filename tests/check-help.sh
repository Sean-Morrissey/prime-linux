#!/usr/bin/env bash
# tests/check-help.sh — "Get help" makes a report a helper can use, and it never
# carries the home folder's path or anything secret-looking. Throwaway HOME.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
mkdir -p "$T/home/.config/prime"
echo "OPENAI_API_KEY=sk-test-should-never-appear" > "$T/home/.config/prime/ai.key"
HOME="$T/home" PRIME_NO_PANEL=1 timeout 120 bash "$REPO/layer/bin/prime-help" --print > "$T/r" 2>&1
ck "says which Prime and system this is"   "grep -q '^== Prime' $T/r && grep -q '^== System' $T/r && grep -q '^kernel: ' $T/r"
ck "has the health check and safety summary" "grep -q '^== Health check' $T/r && grep -q '^== Safety summary' $T/r"
ck "no home-folder path in it"             "! grep -q '$T/home' $T/r"
ck "no keys from Prime's files"             "! grep -q 'sk-test' $T/r"
ck "no colour codes (it's for pasting)"     "! grep -q \$'\\x1b' $T/r"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
