#!/usr/bin/env bash
# prime-new-file.sh <dir> — "New text file here" for the file manager / desktop.
# Windows' New → Text Document, as a nemo action.
set -u
dir="${1:-$HOME/Desktop}"
[ -d "$dir" ] || dir="$HOME"
f="$dir/untitled.txt"
n=2
while [ -e "$f" ]; do f="$dir/untitled $n.txt"; n=$((n + 1)); done
: >"$f" || exit 1
notify-send -a Prime "New file" "$(basename "$f")" >/dev/null 2>&1 || true
