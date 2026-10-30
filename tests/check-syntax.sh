#!/usr/bin/env bash
# tests/check-syntax.sh — no-container syntax pass over every script and JSON
# file the repo tracks: bash -n for shell, py_compile for Python, json.tool for
# JSON. Fast; run it before the container suites.
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
fail=0; n=0
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
while IFS= read -r f; do
    [ -f "$f" ] || continue
    first="$(head -n1 "$f" 2>/dev/null | tr -d '\0')"
    case "$f:$first" in
        *.sh:*|*:'#!'*bash*|*:'#!'*/sh*)
            n=$((n+1)); bash -n "$f" 2>"$tmp/err" || { echo "  FAIL  $f"; sed 's/^/        /' "$tmp/err"; fail=$((fail+1)); } ;;
        *.py:*|*:'#!'*python*)
            n=$((n+1)); python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f" 2>"$tmp/err" \
                || { echo "  FAIL  $f"; sed 's/^/        /' "$tmp/err"; fail=$((fail+1)); } ;;
        *.json:*)
            n=$((n+1)); python3 -m json.tool "$f" >/dev/null 2>"$tmp/err" || { echo "  FAIL  $f"; sed 's/^/        /' "$tmp/err"; fail=$((fail+1)); } ;;
    esac
done < <(git ls-files --cached --others --exclude-standard)
echo "$n files checked"
[ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"
exit $fail
