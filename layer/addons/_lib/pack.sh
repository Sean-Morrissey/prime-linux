# Shared helpers for Prime packs (sourced, not run). Not an add-on itself:
# prime-addon only lists folders that have an addon.conf.
#
#   . "$(dirname "$(readlink -f "$0")")/../../_lib/pack.sh"
#
# Gives: LAYER, PACK_STATE, say/note/warn, ask, notify, nonint, have,
#        ck_ok/ck_warn/ck_bad (check output), gpus, rc_add/rc_remove, bookmark_add/remove.

LAYER="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../..")"
PACK_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/prime/packs"
mkdir -p "$PACK_STATE" 2>/dev/null
USER="${USER:-$(id -un)}"

_A=$'\e[38;2;248;113;113m'; _D=$'\e[2m'; _B=$'\e[1m'; _R=$'\e[0m'
[ -t 1 ] || { _A=""; _D=""; _B=""; _R=""; }
say()  { printf '    %s\n' "$*"; }
note() { printf '    %s%s%s\n' "$_D" "$*" "$_R"; }
warn() { printf '    %s!%s %s\n' "$_A" "$_R" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
nonint() { [ "${PRIME_NONINTERACTIVE:-0}" = 1 ] || ! [ -t 0 ]; }

# ask "Question?" [default y|n] — yes/no; non-interactive answers the default
ask() {
    local q="$1" def="${2:-y}" a
    if nonint; then [ "$def" = y ]; return; fi
    printf '    %s %s ' "$q" "$([ "$def" = y ] && echo '[Y/n]' || echo '[y/N]')"
    read -r a || a=""
    a="${a:-$def}"; [[ "$a" =~ ^[Yy] ]]
}

notify() { notify-send -a Prime -t "${2:-5000}" "${3:-Prime}" "$1" >/dev/null 2>&1 || true; }

# health-check lines, read by `prime-addon check`
ck_ok()   { printf 'ok\t%s\n' "$*"; }
ck_warn() { printf 'warn\t%s\n' "$*"; }
ck_bad()  { printf 'bad\t%s\n' "$*"; }

# gpus — prints the graphics vendors in this machine, one per line:
#   amd | intel | nvidia (proprietary driver installed) | nouveau (NVIDIA without it) | none
# PRIME_GPU="amd intel" overrides (tests, or a machine lspci can't see).
gpus() {
    if [ -n "${PRIME_GPU:-}" ]; then tr ' ,' '\n\n' <<<"$PRIME_GPU" | grep .; return; fi
    local l found=0
    l="$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)"
    if grep -qi nvidia <<<"$l"; then
        found=1
        if pacman -Qq nvidia-utils >/dev/null 2>&1; then echo nvidia; else echo nouveau; fi
    fi
    grep -qiE 'amd|ati |radeon' <<<"$l" && { echo amd; found=1; }
    grep -qi intel <<<"$l" && { echo intel; found=1; }
    [ $found = 1 ] || echo none
}

# rc_add <file> <tag> <line> — add one line to a shell startup file, marked so
# rc_remove can take exactly that line out again. Never touches anything else.
rc_add() {
    local f="$1" tag="$2" line="$3"
    [ -f "$f" ] || return 0
    grep -q "# prime:$tag\$" "$f" && return 0
    printf '%s  # prime:%s\n' "$line" "$tag" >> "$f"
}
rc_remove() { [ -f "$1" ] && sed -i "/# prime:$2\$/d" "$1"; return 0; }

# a folder in the file manager's sidebar (GTK bookmarks: Nemo, file pickers)
bookmark_add() {
    local f="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/bookmarks" uri="file://$1"
    mkdir -p "$(dirname "$f")"; touch "$f"
    grep -q "^$uri\( \|\$\)" "$f" || echo "$uri ${2:-$(basename "$1")}" >> "$f"
}
bookmark_remove() {
    local f="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/bookmarks"
    [ -f "$f" ] && sed -i "\#^file://$1\( \|\$\)#d" "$f"; return 0
}

# refresh one custom waybar module (signal N) without restarting the bar
bar_signal() { pkill -RTMIN+"$1" -x waybar 2>/dev/null || true; }

# in_group <group> — is this user in it (in the account database, not just this login)?
in_group() { id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$1"; }
