#!/usr/bin/env bash
# prime-context.sh — the universal right-click contract.
#
#   Every element on the bar (icon, number, text, anything) answers a right-click
#   with a menu whose first entries are "Ask Prime" variants, followed by the
#   element's own actions. The element's CURRENT VALUE is read live and injected
#   into the question, so Prime answers about what is actually on screen.
#
#   prime-context.sh <element-id>              show the menu (waybar calls this)
#   prime-context.sh <element-id> --list       print "id<TAB>label" for every item
#   prime-context.sh <element-id> --run <id>   run one item without the menu
#   prime-context.sh <element-id> --run <id> --dry   ...but print the ask instead
#
#   Elements + their questions live in ~/.config/prime/elements.json (declarative,
#   portable — this is the file Prime Linux ships at /usr/share/prime/elements.json).
#   Unknown element = still gets the generic Ask Prime menu (never a dead click).
#
#   Menu behaviour: like a Windows context menu — clicking anywhere outside it
#   closes it (rofi's own -click-to-exit), and focus returns to the window you
#   were using (-steal-focus).
set -u

ELEMENT="${1:-}"
MODE="menu"
shift || true
if [ "${1:-}" = "--list" ]; then MODE="list"; shift || true; fi
if [ "${1:-}" = "--run"  ]; then MODE="run"; RUN_ID="${2:-}"; shift 2 || true; fi
DRY=0
for a in "$@"; do [ "$a" = "--dry" ] && DRY=1; done

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$RUNTIME"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    WAYLAND_DISPLAY="$(ls "$RUNTIME" 2>/dev/null | grep -m1 '^wayland-[0-9]*$' || true)"
    [ -n "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY
fi

REGISTRY="${PRIME_ELEMENTS:-$HOME/.config/prime/elements.json}"
[ -f "$REGISTRY" ] || REGISTRY="/usr/share/prime/elements.json"
THEME="$HOME/.config/rofi/prime-menu.rasi"
THEME_INPUT="$HOME/.config/rofi/prime-bar.rasi"
PILL_PY="$HOME/.hermes/hermes-agent/venv/bin/python3"
BAR_PY="$HOME/.hermes/scripts/prime-bar.py"
LOG="$RUNTIME/prime-context.log"
STATE_TTL=6                       # seconds; state is cheap but not free
SEP_ROW='<span alpha="28%">───────────────────────────────────────</span>'

log() { printf '%s [%s] %s\n' "$(date +%H:%M:%S)" "${ELEMENT:-?}" "$*" >>"$LOG" 2>/dev/null || true; }
notify() { notify-send -a Prime -t "${3:-5000}" "$1" "$2" >/dev/null 2>&1 || true; }
launch_bg() { setsid nohup "$@" >/dev/null 2>>"$LOG" & disown 2>/dev/null || true; }

[ -n "$ELEMENT" ] || { echo "usage: prime-context.sh <element-id> [--list|--run <id>]" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { notify "⚠️ Prime" "jq is missing — the right-click menu needs it"; exit 1; }

if [ ! -f "$REGISTRY" ]; then
    notify "⚠️ Prime" "Element registry missing: $REGISTRY"
    exit 1
fi

# ── registry lookup (unknown id falls back to the generic contract) ──────────
# The element id must match a registry key exactly; anything else is treated as
# an unknown element and still gets the Ask Prime menu. (jq would happily match
# "bar.updates" against "bar.updatesX" with .elements[] -- hash syntax doesn't.)
entry="$(jq -c --arg id "$ELEMENT" '.elements | if has($id) then .[$id] else empty end' "$REGISTRY" 2>/dev/null)"
if [ -z "$entry" ] || [ "$entry" = "null" ]; then
    log "unknown element — using the fallback contract"
    entry="$(jq -c '.fallback' "$REGISTRY" 2>/dev/null)"
fi
[ -n "$entry" ] || { notify "⚠️ Prime" "Registry unreadable: $REGISTRY"; exit 1; }

LABEL="$(jq -r '.label // "Bar element"' <<<"$entry")"
STATE_CMD="$(jq -r '.state // ""' <<<"$entry")"
ASK_TPL="$(jq -r '.ask // ""' <<<"$entry")"

# ── read the element's live value (cached for STATE_TTL so a menu opens fast) ─
STATE_CACHE="$RUNTIME/prime-context-state-${ELEMENT//[^A-Za-z0-9_.-]/_}"
state_is_fresh() {
    [ -f "$STATE_CACHE" ] || return 1
    [ $(( $(date +%s) - $(stat -c %Y "$STATE_CACHE" 2>/dev/null || echo 0) )) -lt "$STATE_TTL" ]
}
read_state() {
    if state_is_fresh; then cat "$STATE_CACHE"; return; fi
    local out=""
    if [ -n "$STATE_CMD" ]; then
        # timeout 6 also protects the menu from a state command that blocks
        # (swaync-client -swb prints its JSON and then never exits).
        out="$(cd "$HOME" && timeout 6 bash -c "$STATE_CMD" 2>/dev/null)"
    fi
    # collapse to one line, clip — this ends up in the menu header and in a prompt
    out="$(printf '%s' "$out" | tr '\n' ';' | sed 's/;[[:space:]]*/; /g; s/  */ /g; s/[[:space:]]*$//')"
    out="${out:0:600}"
    printf '%s' "$out" > "$STATE_CACHE" 2>/dev/null || true
    printf '%s' "$out"
}

menu_items() {                    # "id<TAB>label": ask group · separators · extras · utilities
    jq -r '.generic_items[] | "\(.id)\t\(.label)"' "$REGISTRY" 2>/dev/null
    local extras
    # NOTE: the element's own items live under .elements[$id].items — querying
    # .items at the document root silently yields nothing and the menu loses its
    # extras (the generic rows still render, so it looks like it worked).
    extras="$(jq -r --arg id "$ELEMENT" '(.elements[$id].items // []) | to_entries[] | "custom/\(.key)\t\(.value.label)"' "$REGISTRY" 2>/dev/null)"
    if [ -n "$extras" ]; then
        printf 'SEP\t%s\n' "$SEP_ROW"
        printf '%s\n' "$extras"
    fi
    if jq -e '(.utility_items // []) | length > 0' "$REGISTRY" >/dev/null 2>&1; then
        printf 'SEP\t%s\n' "$SEP_ROW"
        jq -r '.utility_items[] | "\(.id)\t\(.label)"' "$REGISTRY" 2>/dev/null
    fi
}

item_kind() {                     # id -> kind (generic + utility), custom/<i> -> cmd
    case "$1" in
        custom/*) echo "cmd" ;;
        SEP)      echo "sep" ;;
        *) jq -r --arg id "$1" '
             ((.generic_items // []) + (.utility_items // []))
             | map(select(.id==$id)) | .[0].kind // empty' "$REGISTRY" 2>/dev/null ;;
    esac
}

item_cmd() {                      # custom/<index> -> the command from the registry
    local idx="${1#custom/}"
    jq -r --arg id "$ELEMENT" --argjson i "$idx" '.elements[$id].items[$i].cmd // ""' "$REGISTRY" 2>/dev/null
}

clip_state() { printf '%s' "$1" | cut -c1-160; }

# ── the ask variants ─────────────────────────────────────────────────────────
ask_about_this() {                # $1 = extra instruction (may be empty)
    local st; st="$(read_state)"
    local q="$ASK_TPL"
    if [ -z "$q" ]; then
        q="This is the \"$LABEL\" element in my bar. Its current state: {state}"
    fi
    q="${q//\{state\}/$st}"
    [ -n "$1" ] && q="$q

$1"
    printf '%s' "$q"
}

ask_explain_text() {
    local st; st="$(read_state)"
    printf 'Explain the "%s" element in my status bar as if I am new to Linux: what it shows, how it is wired up, and what a normal value looks like. Current state: %s' \
        "$LABEL" "$st"
}

area_geometry() {                 # capture the thing under the cursor
    local pos x y
    pos="$(hyprctl cursorpos 2>/dev/null | tr -d ' ')" || pos=""
    x="${pos%%,*}"; y="${pos##*,}"
    case "$x" in ''|*[!0-9]*) x=960 ;; esac
    case "$y" in ''|*[!0-9]*) y=24  ;; esac
    if [ "$y" -le 48 ]; then                      # top bar strip
        local left=$(( x - 170 )); [ "$left" -lt 0 ] && left=0
        echo "$left,0 340x48"
    elif [ "$x" -le 60 ]; then                    # left sidebar column
        local top=$(( y - 100 )); [ "$top" -lt 44 ] && top=44
        echo "0,$top 60x220"
    else                                          # anywhere else: around the cursor
        local left=$(( x - 200 )); [ "$left" -lt 0 ] && left=0
        local top=$(( y - 120 ));  [ "$top"  -lt 0 ] && top=0
        echo "$left,$top 400x260"
    fi
}

capture_area() {
    local geom shot dir
    dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"
    shot="$dir/prime_ctx_$(date +%Y%m%d_%H%M%S).png"
    geom="$(area_geometry)"
    grim -g "$geom" "$shot" 2>>"$LOG" || return 1
    printf '%s' "$shot"
}

submit_ask() {                    # $1 text, $2 optional image, $3 optional session mode
    local text="$1" img="${2:-}" mode="${3:-}"
    if [ "$DRY" -eq 1 ]; then
        printf 'ASK: %s\n' "$text"
        [ -n "$img" ] && printf 'IMAGE: %s\n' "$img"
        return 0
    fi
    if [ ! -x "$PILL_PY" ] || [ ! -f "$BAR_PY" ]; then
        notify "⚠️ Prime" "Prime backend missing: $BAR_PY"
        return 1
    fi
    if [ -n "$img" ]; then
        launch_bg "$PILL_PY" "$BAR_PY" ask "$text" --image "$img"
    elif [ "$mode" = "new" ]; then
        launch_bg "$PILL_PY" "$BAR_PY" ask "$text" --new
    else
        launch_bg "$PILL_PY" "$BAR_PY" ask "$text"
    fi
    log "asked Prime: $(printf '%s' "$text" | cut -c1-120)"
}

# ── dispatch one item ────────────────────────────────────────────────────────
run_item() {
    local id="$1" kind cmd
    kind="$(item_kind "$id")"
    case "$kind" in
        ask)
            submit_ask "$(ask_about_this "")" ;;
        ask_explain)
            submit_ask "$(ask_explain_text)" ;;
        ask_area)
            local shot; shot="$(capture_area)" || { notify "⚠️ Prime" "Capture failed"; return 1; }
            submit_ask "What is this element in my bar? It is the \"$LABEL\" element. Read it, tell me what it shows, and flag anything wrong. (System state: $(clip_state "$(read_state)"))" "$shot" ;;
        ask_custom)
            local typed
            typed="$("$HOME/.config/prime/rofi-hint.sh" -dmenu -i -theme "$THEME_INPUT" -p "󰚩 about $LABEL" \
                        -theme-str 'listview { lines: 0; }' \
                        -theme-str "entry { placeholder: \"What do you want to know about the $LABEL element?\"; }" \
                        </dev/null)" || return 0
            [ -n "${typed//[[:space:]]/}" ] || return 0
            submit_ask "$typed

(Element: $LABEL. Current state: $(read_state))" ;;
        copy)
            local st; st="$(read_state)"
            printf '%s' "$st" | wl-copy 2>/dev/null && notify "Prime" "Copied $LABEL: $(clip_state "$st")" ;;
        last)
            bash "$HOME/.config/waybar/scripts/prime-bar-input.sh" --popup ;;
        sep)
            log "separator row selected — no action" ;;
        cmd)
            cmd="$(item_cmd "$id")"
            if [ "$cmd" = "__ask_state__" ]; then
                submit_ask "$(ask_about_this "")"
            elif [ -n "$cmd" ]; then
                launch_bg bash -c "$cmd"
                log "ran: $cmd"
            fi ;;
        *)
            log "unknown item: $id" ;;
    esac
}

# ── list / run (non-interactive, used by tests) ──────────────────────────────
if [ "$MODE" = "list" ]; then
    { menu_items; } | sed 's/\t/  /'
    exit 0
fi

if [ "$MODE" = "run" ]; then
    [ -n "${RUN_ID:-}" ] || { echo "--run needs an item id" >&2; exit 2; }
    run_item "$RUN_ID"
    exit $?
fi

# ── the menu ─────────────────────────────────────────────────────────────────
command -v rofi >/dev/null 2>&1 || { notify "⚠️ Prime" "rofi is not installed"; exit 1; }

mapfile -t RAW < <(menu_items)
LABELS=(); IDS=()
for line in "${RAW[@]}"; do
    LABELS+=("${line#*$'\t'}")
    IDS+=("${line%%$'\t'*}")
done
[ "${#LABELS[@]}" -gt 0 ] || { notify "⚠️ Prime" "No menu items for $ELEMENT"; exit 1; }

header="$(clip_state "$(read_state)" | cut -c1-96)"
[ -n "$header" ] && header="$LABEL — $header" || header="$LABEL"

# -click-to-exit: clicking outside closes the menu (Windows-like).
# -steal-focus:   hands keyboard focus back to the window you were using.
# -markup-rows:   lets the separator rows render as dimmed rules.
choice="$(printf '%s\n' "${LABELS[@]}" | "$HOME/.config/prime/rofi-hint.sh" -dmenu -i -no-custom \
            -click-to-exit -steal-focus -markup-rows \
            -theme "$THEME" \
            -p "󰚩 $LABEL" \
            -mesg "$header" \
            -theme-str 'listview { lines: 12; }')"
rc=$?
[ $rc -ne 0 ] && { log "menu cancelled"; exit 0; }
[ -n "${choice//[[:space:]]/}" ] || exit 0

for i in "${!LABELS[@]}"; do
    if [ "${LABELS[$i]}" = "$choice" ]; then
        log "chose: ${IDS[$i]}"
        run_item "${IDS[$i]}"
        exit $?
    fi
done
log "no item matched: $choice"
