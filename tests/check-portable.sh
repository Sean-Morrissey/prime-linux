#!/usr/bin/env bash
# tests/check-portable.sh — nothing a friend installs may only work on the
# author's PC: his home folder, his name, his GPU (RX 9060 XT), his screens,
# his sound devices, his personal add-on. Scans exactly what install.sh puts on
# a machine: install.sh, boot.sh, layer/ and the package list.
set -u
# With no argument this gates its own repo, as it always has. With a directory
# argument it gates any other tree that gets installed onto a machine — the
# harvested desktop bundle, say — so one rule decides what "portable" means
# instead of each checkout inventing its own.
#   check-portable.sh                      this repo
#   check-portable.sh ~/Projects/prime-desktop
ROOT="${1:-}"
if [ -n "$ROOT" ]; then
    cd "$ROOT" || exit 1
else
    cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
fi
fail=0
# Only the paths that exist here: a bundle has no layer/ or os/arch, a repo has
# no top-level hypr/ or waybar/.
SHIPPED=()
for p in install.sh boot.sh layer os/arch hypr waybar prime rofi kitty swaync fish; do
    [ -e "$p" ] && SHIPPED+=("$p")
done
[ "${#SHIPPED[@]}" -gt 0 ] || { echo "nothing shippable found in $(pwd)" >&2; exit 2; }
echo "  ..  scanning: ${SHIPPED[*]}"
scan() { # scan <what> <regex> [extra grep args] — fails when any shipped file matches
    local hits
    hits="$(grep -rnIiE "$2" "${SHIPPED[@]}" --exclude-dir=previews "${@:3}" 2>/dev/null)"
    if [ -z "$hits" ]; then echo "  PASS  no $1"
    else echo "  FAIL  $1:"; printf '%s\n' "$hits" | head -10 | sed 's/^/          /'; fail=$((fail+1)); fi
}
scan "home-folder paths (/home/<someone>)" '/home/[a-z_][a-z0-9_-]*' --exclude=prime-spotlight --exclude=prime-uninstall
# the author's name and handles are not written in this public file: CI passes them in
# as the PRIME_AUTHOR_RE secret; on the author's machine they come from his private
# ~/.config/prime/author-patterns.json (see tools/capture-workspace.py)
AUTHOR_FILE="${PRIME_AUTHOR_PATTERNS:-$HOME/.config/prime/author-patterns.json}"
if [ -z "${PRIME_AUTHOR_RE:-}" ] && [ -r "$AUTHOR_FILE" ] && command -v jq >/dev/null; then
    PRIME_AUTHOR_RE="$(jq -r '[.leaks[][1] | sub("\\(\\?i\\)"; "")] | join("|")' "$AUTHOR_FILE")"
fi
if [ -n "${PRIME_AUTHOR_RE:-}" ]; then scan "author's name or login" "$PRIME_AUTHOR_RE" --exclude=boot.sh
else echo "  SKIP  author's name (set PRIME_AUTHOR_RE)"; fi
scan "author's GPU model or overrides"     'RX ?9060|Navi ?44|gfx1200|HSA_OVERRIDE_GFX'
scan "fixed GPU card or sensor numbers"    '/sys/class/drm/card[0-9]|hwmon/hwmon[0-9]'
scan "named screens (DP-1, HDMI-A-1, eDP-1…)" '(^|[^a-z])(DP|HDMI-A|eDP|DVI-D)-[0-9]' --exclude=prime-import
scan "named sound devices"                 'alsa_(output|input)\.[a-z0-9]'
scan "the author's own agent (Hermes setup, ledger, his API provider)" '\.hermes/|hermes-gateway|ledger-(note|flush|handle|inbox)|DEEPSEEK_API_KEY'
# the personal add-on is made on your own machine by prime-import, never shipped
if [ -e layer/addons/my-desktop ] || git ls-files | grep -q 'addons\.d/'; then echo "  FAIL  a personal add-on is in the repo"; fail=$((fail+1))
else echo "  PASS  no personal add-on in the repo"; fi
# boot.sh may name the repo (that's where it downloads from) but nothing else of his
if [ -n "${PRIME_AUTHOR_RE:-}" ] && grep -niE "$PRIME_AUTHOR_RE" boot.sh | grep -viqE '[a-z0-9-]+/prime-linux'; then echo "  FAIL  boot.sh names the author outside the repo URL"; fail=$((fail+1))
else echo "  PASS  boot.sh only names the repo"; fi
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
