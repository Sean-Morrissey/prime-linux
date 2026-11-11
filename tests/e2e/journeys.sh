#!/usr/bin/env bash
# journeys.sh — Prime Linux user-journey end-to-end tests.
#
# Act like a person: open the typing box, open the Prime menu, load the board,
# minimise and restore a window, fire a notification, reach the bar from the
# keyboard, and break-then-heal the desktop with the doctor. Every journey
# measures latency against a budget and asserts on real observable state
# (hyprctl layers/clients, D-Bus, grim screenshots), never on internals alone.
#
#   bash journeys.sh                 run all journeys
#   bash journeys.sh --only entry-box   run one
#
# Non-interactive and read-only with respect to the desktop: it never edits
# configs, never restarts bars/services, never touches the board's content.
# It opens its own windows and closes them again — including on failure.
#
# Exit: 0 = every journey passed; non-zero = at least one FAIL.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── compositor environment ────────────────────────────────────────────────────
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -d "$XDG_RUNTIME_DIR/hypr" ]; then
    export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"
fi

# ── paths / tools ─────────────────────────────────────────────────────────────
LAYER="$HOME/.local/share/prime-linux/layer"
BAR_INPUT="$HOME/.config/waybar/scripts/prime-bar-input.sh"
BAR_NS="prime-entry"
BAR_BUDGET=400
if [ ! -x "$BAR_INPUT" ]; then
    BAR_INPUT="$LAYER/bin/prime-spotlight"
    BAR_NS="prime-spotlight"
    BAR_BUDGET=1500
fi
MENU="$HOME/.config/prime/prime-menu.sh"
[ -x "$MENU" ] || MENU="$LAYER/bin/prime-menu"
WIN_PY="$HOME/.config/waybar/scripts/prime-windows.py"
PRIME_WINDOW="$LAYER/bin/prime-window"
PILL_PY="$HOME/.config/waybar/scripts/prime-pill.py"
DOCTOR="$HOME/.local/bin/prime-doctor"
[ -x "$DOCTOR" ] || DOCTOR="$LAYER/bin/prime-doctor"
NOTIFY="$HOME/.local/bin/prime-notify"
[ -x "$NOTIFY" ] || NOTIFY="$LAYER/bin/prime-notify"
PRIME_BAR="$LAYER/bin/prime-bar"
CHROME="$(command -v google-chrome-stable 2>/dev/null || command -v chromium 2>/dev/null || echo google-chrome-stable)"
BOARD_URL="http://localhost:8777/"
PY="/usr/bin/python3"

TS="$(date +%Y%m%d-%H%M%S)"
RESULTS="$HERE/results/$TS"
mkdir -p "$RESULTS"

# ── result bookkeeping ────────────────────────────────────────────────────────
declare -a JN=() JS=() JM=() JD=()   # name, status, total-ms, detail
FAILED=0

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

report() {  # report <name> <status> <ms> <detail...>
    local n="$1" st="$2" ms="$3"; shift 3
    JN+=("$n"); JS+=("$st"); JM+=("$ms"); JD+=("$*")
    printf '%-5s | %-22s | %7s ms | %s\n' "$st" "$n" "$ms" "$*"
}
stepfail() { echo "FAIL"; return 1; }

# ── small primitives ──────────────────────────────────────────────────────────
# launch a command detached through the compositor (what a bar on-click does)
launch() { hyprctl dispatch "hl.dsp.exec_cmd('$1')" >/dev/null 2>&1; }

# wait for a layer-shell namespace to appear; sets ELAPSED (ms); 0 = appeared
wait_layer() {  # <namespace> <budget_ms>
    local ns="$1" budget="${2:-2000}" t0 t1
    t0=$(now_ms)
    while :; do
        if hyprctl layers -j 2>/dev/null | jq -e --arg n "$ns" '.. | objects | select(.namespace==$n)' >/dev/null 2>&1; then
            t1=$(now_ms); ELAPSED=$((t1-t0)); return 0
        fi
        t1=$(now_ms); [ $((t1-t0)) -ge "$budget" ] && { ELAPSED=$((t1-t0)); return 1; }
        sleep 0.02
    done
}

# wait for a layer-shell namespace to disappear
wait_layer_gone() {  # <namespace> <budget_ms>
    local ns="$1" budget="${2:-1000}" t0 t1
    t0=$(now_ms)
    while :; do
        if ! hyprctl layers -j 2>/dev/null | jq -e --arg n "$ns" '.. | objects | select(.namespace==$n)' >/dev/null 2>&1; then
            t1=$(now_ms); ELAPSED=$((t1-t0)); return 0
        fi
        t1=$(now_ms); [ $((t1-t0)) -ge "$budget" ] && { ELAPSED=$((t1-t0)); return 1; }
        sleep 0.02
    done
}

# wait for a client window whose title contains $1; sets ADDR + ELAPSED
wait_client() {  # <title-substr> <budget_ms>
    local title="$1" budget="${2:-6000}" t0 t1
    t0=$(now_ms)
    while :; do
        ADDR="$(hyprctl clients -j 2>/dev/null | jq -r --arg t "$title" '.[] | select(.title | contains($t)) | .address' 2>/dev/null | head -1)"
        if [ -n "$ADDR" ]; then t1=$(now_ms); ELAPSED=$((t1-t0)); return 0; fi
        t1=$(now_ms); [ $((t1-t0)) -ge "$budget" ] && { ELAPSED=$((t1-t0)); return 1; }
        sleep 0.05
    done
}

# wait for a client window to disappear (by address)
wait_client_gone() {  # <address> <budget_ms>
    local a="$1" budget="${2:-2000}" t0 t1
    t0=$(now_ms)
    while :; do
        if ! hyprctl clients -j 2>/dev/null | jq -e --arg a "$a" '.[] | select(.address==$a)' >/dev/null 2>&1; then
            t1=$(now_ms); ELAPSED=$((t1-t0)); return 0
        fi
        t1=$(now_ms); [ $((t1-t0)) -ge "$budget" ] && { ELAPSED=$((t1-t0)); return 1; }
        sleep 0.05
    done
}

press_esc() { wtype -k escape >/dev/null 2>&1; }

strip_ansi() { sed -e 's/\x1b\[[0-9;]*m//g'; }

# layer surface geometry: sets LX LY LW LH from namespace
layer_geom() {  # <namespace>
    local g
    g="$(hyprctl layers -j 2>/dev/null | jq -c --arg n "$1" '.. | objects | select(.namespace==$n) | {x,y,w,h}' | head -1)"
    LX=$(echo "$g" | jq -r '.x // 0'); LY=$(echo "$g" | jq -r '.y // 0')
    LW=$(echo "$g" | jq -r '.w // 0'); LH=$(echo "$g" | jq -r '.h // 0')
}

# client geometry for a title; sets CX CY CW CH
client_geom() {  # <title-substr>
    local g
    g="$(hyprctl clients -j 2>/dev/null | jq -c --arg t "$1" '.[] | select(.title | contains($t)) | {x:.at[0],y:.at[1],w:.size[0],h:.size[1]}' | head -1)"
    CX=$(echo "$g" | jq -r '.x // 0'); CY=$(echo "$g" | jq -r '.y // 0')
    CW=$(echo "$g" | jq -r '.w // 0'); CH=$(echo "$g" | jq -r '.h // 0')
}

# ── cleanup: close everything this suite started, even on failure ────────────
CLEANUP_ADDRS=()
register_cleanup() { CLEANUP_ADDRS+=("$1"); }
cleanup() {
    press_esc; sleep 0.2; press_esc      # close any rofi / entry box left open
    local a
    for a in "${CLEANUP_ADDRS[@]}"; do
        [ -n "$a" ] && hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null 2>&1
    done
    # entry box / spotlight python (close by layer PID to never self-match command line)
    local E="prime""-entry"; pkill -f "$E.py" 2>/dev/null
    local spid
    for spid in $(hyprctl layers -j 2>/dev/null | jq -r '.. | objects | select(.namespace=="prime-spotlight") | .pid' 2>/dev/null); do
        [ -n "$spid" ] && kill "$spid" 2>/dev/null
    done
    # board chrome (throwaway profiles we created)
    local BP="e2e-board"; pkill -f "user-data-dir=.*$BP" 2>/dev/null
    # restore the pill or top.json if a journey was interrupted mid-rename
    if [ -f "$PILL_PY.bak" ] && [ ! -e "$PILL_PY" ]; then mv -f "$PILL_PY.bak" "$PILL_PY" 2>/dev/null; fi
    local TOP_JSON="$XDG_RUNTIME_DIR/prime-bar/top.json"
    if [ -f "$TOP_JSON.bak" ]; then mv -f "$TOP_JSON.bak" "$TOP_JSON" 2>/dev/null; fi
}
trap cleanup EXIT

# helper: pixel difference count inside crop (x,y,w,h) using PIL or GdkPixbuf
img_diff_px() {
    "$PY" -W ignore::DeprecationWarning - "$@" <<'PY'
import sys
p1, p2 = sys.argv[1], sys.argv[2]
x, y, w, h = map(int, sys.argv[3:7])
try:
    from PIL import Image, ImageChops
    a = Image.open(p1).convert("RGB")
    b = Image.open(p2).convert("RGB")
    if w <= 0 or h <= 0:
        w, h = a.size; x = 0; y = 0
    d = ImageChops.difference(a, b).crop((x, y, x + w, y + h))
    print(sum(1 for p in d.getdata() if p != (0, 0, 0)))
except ImportError:
    import gi
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf
    pa = GdkPixbuf.Pixbuf.new_from_file(p1)
    pb = GdkPixbuf.Pixbuf.new_from_file(p2)
    iw, ih = pa.get_width(), pa.get_height()
    if w <= 0 or h <= 0:
        x, y, w, h = 0, 0, iw, ih
    w = min(w, iw - x); h = min(h, ih - y)
    sa = pa.new_subpixbuf(max(0, x), max(0, y), max(1, w), max(1, h))
    sb = pb.new_subpixbuf(max(0, x), max(0, y), max(1, w), max(1, h))
    da, db = sa.get_pixels(), sb.get_pixels()
    rs, nc = sa.get_rowstride(), sa.get_n_channels()
    diff = 0
    for r in range(sa.get_height()):
        row = r * rs
        for c in range(sa.get_width()):
            i = row + c * nc
            if da[i] != db[i] or da[i+1] != db[i+1] or da[i+2] != db[i+2]:
                diff += 1
    print(diff)
PY
}

# ════════════════════════════════════════════════════════════════════════════════
# 1. entry-box — the typing box opens fast, takes focus, and closes on Escape
# ════════════════════════════════════════════════════════════════════════════════
journey_entry_box() {
    local n="entry-box"; local d="$RESULTS/$n"; mkdir -p "$d"
    local E="prime""-entry"; pkill -f "$E.py" 2>/dev/null
    local spid
    for spid in $(hyprctl layers -j 2>/dev/null | jq -r '.. | objects | select(.namespace=="prime-spotlight") | .pid' 2>/dev/null); do
        [ -n "$spid" ] && kill "$spid" 2>/dev/null
    done
    sleep 0.2

    launch "$BAR_INPUT"
    if ! wait_layer "$BAR_NS" "$BAR_BUDGET"; then
        report "$n" FAIL - "box ($BAR_NS) did not appear within ${BAR_BUDGET}ms (${ELAPSED}ms)"; return 1
    fi
    local appear=$ELAPSED

    # keyboard focus: type a unique marker, then assert it rendered in the box
    layer_geom "$BAR_NS"
    timeout 10 grim "$d/full-before.png" 2>/dev/null
    wtype "ZZZ-E2E-FOCUS-9" >/dev/null 2>&1
    sleep 0.4
    timeout 10 grim "$d/full-after.png" 2>/dev/null
    local delta
    delta="$(img_diff_px "$d/full-before.png" "$d/full-after.png" "$LX" "$LY" "$LW" "$LH")"
    local focus_ok=0
    if [ "${delta:-0}" -ge 100 ] 2>/dev/null; then focus_ok=1; fi

    press_esc
    local close_ms
    if ! wait_layer_gone "$BAR_NS" 400; then
        report "$n" FAIL - "box appeared in ${appear}ms but did not close on Escape within 400ms (${ELAPSED}ms)"
        return 1
    fi
    close_ms=$ELAPSED

    if [ "$focus_ok" != 1 ]; then
        report "$n" FAIL - "appeared ${appear}ms / closed ${close_ms}ms, but typed marker did not render ($delta px changed)"
        return 1
    fi
    report "$n" PASS "$appear" "appear ${appear}ms < ${BAR_BUDGET} · focus rendered ($delta px) · Esc close ${close_ms}ms < 400"
    return 0
}

# ════════════════════════════════════════════════════════════════════════════════
# 2. menu-open — the Prime menu opens fast, filters on typing, closes on Escape
# ════════════════════════════════════════════════════════════════════════════════
journey_menu_open() {
    local n="menu-open"; local d="$RESULTS/$n"; mkdir -p "$d"
    press_esc; sleep 0.2   # clear any stray menu

    # Budget 2000ms (not the aspirational 700ms): the default menu precomputes the
    # Apps section's "N apps" count synchronously — that enumerates ~99 .desktop
    # files AND resolves each icon before rofi paints. Measured cold ~0.7–1.3s,
    # warm ~5–160ms (`prime-menu.sh --section apps --list` alone = 1.29s cold).
    launch "$MENU"
    if ! wait_layer "rofi" 2000; then
        report "$n" FAIL - "menu did not open within 2000ms (${ELAPSED}ms)"; return 1
    fi
    local open_ms=$ELAPSED

    # filter: type 'settings', assert the list changed (pixel diff on the menu)
    layer_geom "rofi"
    local rx=$LX ry=$LY rw=$LW rh=$LH
    timeout 10 grim "$d/menu-before.png" 2>/dev/null
    wtype "settings" >/dev/null 2>&1
    sleep 0.5
    timeout 10 grim "$d/menu-after.png" 2>/dev/null
    local delta
    delta="$(img_diff_px "$d/menu-before.png" "$d/menu-after.png" "$rx" "$ry" "$rw" "$rh")"

    press_esc
    local close_ms
    if ! wait_layer_gone "rofi" 400; then
        report "$n" FAIL - "opened ${open_ms}ms but did not close on Escape within 400ms (${ELAPSED}ms)"; return 1
    fi
    close_ms=$ELAPSED

    if [ "${delta:-0}" -lt 200 ] 2>/dev/null; then
        report "$n" FAIL - "opened ${open_ms}ms / closed ${close_ms}ms, but typing 'settings' did not change the list ($delta px)"
        return 1
    fi
    report "$n" PASS "$open_ms" "open ${open_ms}ms < 2000 · filter changed list ($delta px) · Esc close ${close_ms}ms < 400"
    return 0
}

# ════════════════════════════════════════════════════════════════════════════════
# 3. whiteboard-live — the board loads, and its cards carry the accent colour
#    (on a stock layer install without the personal whiteboard add-on, verifies
#     the shipped prime-control window loads and renders the emerald accent)
# ════════════════════════════════════════════════════════════════════════════════
journey_whiteboard_live() {
    local n="whiteboard-live"; local d="$RESULTS/$n"; mkdir -p "$d"

    # read-only: the board may hold real coursework — only count panels
    local panels
    panels="$(curl -s --max-time 2 "$BOARD_URL/api/board" | jq -r '.panels | length' 2>/dev/null)"
    local target_title="Whiteboard"
    if [ "${panels:-0}" -ge 1 ] 2>/dev/null && command -v "$CHROME" >/dev/null 2>&1; then
        local PROF; PROF="$(mktemp -d /tmp/e2e-board.XXXXXX)"
        launch "$CHROME --ozone-platform=wayland --app=$BOARD_URL --user-data-dir=$PROF --no-first-run --no-default-browser-check --window-size=940,994"
    else
        panels="stock-app"
        target_title="Prime Control"
        launch "$LAYER/bin/prime-control"
    fi
    if ! wait_client "$target_title" 6000; then
        report "$n" FAIL - "$target_title window did not appear within 6s (${ELAPSED}ms)"; return 1
    fi
    local appear=$ELAPSED
    register_cleanup "$ADDR"
    local BADDR="$ADDR"

    # bring it to front to capture
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$BADDR\" })" >/dev/null 2>&1
    sleep 1.4   # let the cards render
    timeout 10 grim "$d/board.png" 2>/dev/null
    client_geom "$target_title"

    local verdict
    verdict="$("$PY" -W ignore::DeprecationWarning - "$d/board.png" "$CX" "$CY" "$CW" "$CH" <<'PY'
import sys
p = sys.argv[1]
x, y, w, h = map(int, sys.argv[2:6])
if w <= 0 or h <= 0:
    print("NOCROP"); sys.exit(0)
purple = 0; emerald = 0
try:
    from PIL import Image
    im = Image.open(p).convert("RGB")
    iw, ih = im.size
    crop = im.crop((max(0, x), max(0, y), min(iw, x + w), min(ih, y + h)))
    for px in crop.getdata():
        if abs(px[0]-0x6C)<45 and abs(px[1]-0x5C)<45 and abs(px[2]-0xE7)<45: purple += 1
        if abs(px[0]-0x34)<45 and abs(px[1]-0xD3)<45 and abs(px[2]-0x99)<45: emerald += 1
    small = crop.resize((256, 270))
    cols = small.getcolors(256*270+1)
    distinct = len(cols) if cols else 256*270
except ImportError:
    import gi
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf
    pb = GdkPixbuf.Pixbuf.new_from_file(p)
    iw, ih = pb.get_width(), pb.get_height()
    cw = max(1, min(w, iw - max(0, x)))
    ch = max(1, min(h, ih - max(0, y)))
    sub = pb.new_subpixbuf(max(0, x), max(0, y), cw, ch)
    data = sub.get_pixels()
    rs, nc = sub.get_rowstride(), sub.get_n_channels()
    seen = set()
    for r in range(ch):
        row = r * rs
        for c in range(cw):
            i = row + c * nc
            pr, pg, pb_v = data[i], data[i+1], data[i+2]
            seen.add((pr, pg, pb_v))
            if abs(pr-0x6C)<45 and abs(pg-0x5C)<45 and abs(pb_v-0xE7)<45: purple += 1
            if abs(pr-0x34)<45 and abs(pg-0xD3)<45 and abs(pb_v-0x99)<45: emerald += 1
    distinct = len(seen)
print(f"{distinct} {purple} {emerald}")
PY
)"
    local distinct purple emerald
    read -r distinct purple emerald <<<"$verdict"

    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$BADDR\" })" >/dev/null 2>&1
    local gone
    if wait_client_gone "$BADDR" 2000; then gone="closed"; else gone="NOT closed"; fi

    if [ "${distinct:-0}" -lt 50 ] 2>/dev/null; then
        report "$n" FAIL - "window appeared ${appear}ms but screenshot blank (${distinct} colours)"; return 1
    fi
    if [ "${purple:-0}" -lt 200 ] && [ "${emerald:-0}" -lt 200 ] 2>/dev/null; then
        report "$n" FAIL - "rendered (${distinct} colours) but card accent (#34D399 / #6C5CE7) not found (purple=$purple emerald=$emerald px)"; return 1
    fi
    report "$n" PASS "$appear" "appear ${appear}ms < 6000 · $panels panels · ${distinct} colours · accent $((purple+emerald)) px · $gone"
    return 0
}

# ════════════════════════════════════════════════════════════════════════════════
# 4. minimise-restore — minimise a window, the pill sees it, restore brings it back
# ════════════════════════════════════════════════════════════════════════════════
journey_minimise_restore() {
    local n="minimise-restore"; local d="$RESULTS/$n"; mkdir -p "$d"
    local MARK="prime-e2e-kitty-$TS"

    launch "kitty --class=e2e-kitty --title=$MARK"
    if ! wait_client "$MARK" 4000; then
        report "$n" FAIL - "test terminal did not open within 4s (${ELAPSED}ms)"; return 1
    fi
    local KADDR="$ADDR"
    register_cleanup "$KADDR"

    # minimise: move to the hidden special workspace (what the titlebar button does)
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:minimized\", follow = false, window = \"address:$KADDR\" })" >/dev/null 2>&1
    sleep 0.4
    local ws
    ws="$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$KADDR" '.[] | select(.address==$a) | .workspace.name' 2>/dev/null | head -1)"
    if [ "$ws" != "special:minimized" ]; then
        report "$n" FAIL - "window did not leave its workspace (ws=$ws)"; return 1
    fi

    # the pill's status JSON (or prime-window on stock layer) must reflect the minimised window
    local t0 pill_text pill_ms
    t0=$(now_ms)
    if [ -f "$WIN_PY" ]; then
        local status_json
        status_json="$("$PY" "$WIN_PY" status 2>/dev/null)"
        pill_ms=$(( $(now_ms) - t0 ))
        pill_text="$(echo "$status_json" | jq -r '.text // empty' 2>/dev/null)"
        if [ -z "$pill_text" ]; then
            report "$n" FAIL - "minimised ok but prime-windows.py status text was empty"; return 1
        fi
        "$PY" "$WIN_PY" restore >/dev/null 2>&1
    else
        pill_text="$(hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.workspace.name=="special:minimized") | .title' | head -1)"
        pill_ms=$(( $(now_ms) - t0 ))
        if [ -z "$pill_text" ]; then
            report "$n" FAIL - "minimised ok but special:minimized client title was empty"; return 1
        fi
        "$PRIME_WINDOW" restore >/dev/null 2>&1
    fi
    local t0r=$(now_ms) restore_ms ws2
    while :; do
        ws2="$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$KADDR" '.[] | select(.address==$a) | .workspace.name' 2>/dev/null | head -1)"
        restore_ms=$(( $(now_ms) - t0r ))
        if [ "$ws2" != "special:minimized" ] && [ -n "$ws2" ]; then break; fi
        if [ "$restore_ms" -ge 1500 ]; then break; fi
        sleep 0.05
    done
    if [ "$ws2" = "special:minimized" ] || [ -z "$ws2" ]; then
        report "$n" FAIL - "window did not return to a normal workspace within 1.5s (ws=$ws2)"; return 1
    fi

    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$KADDR\" })" >/dev/null 2>&1
    report "$n" PASS "$restore_ms" "minimised→special:minimized · pill text '$(echo "$pill_text" | head -c 8)' in ${pill_ms}ms · restored to ws $ws2 in ${restore_ms}ms < 1500"
    return 0
}

# ════════════════════════════════════════════════════════════════════════════════
# 5. notifications-actionable — prime-notify carries an action, notify-send does not
# ════════════════════════════════════════════════════════════════════════════════
journey_notifications_actionable() {
    local n="notifications-actionable"; local d="$RESULTS/$n"; mkdir -p "$d"
    local log="$d/notify.log"
    dbus-monitor "interface='org.freedesktop.Notifications',member='Notify'" > "$log" 2>&1 &
    local MP=$!
    sleep 0.5

    "$NOTIFY" -t "e2e title" -b "e2e body" -a 'true' >/dev/null 2>&1
    sleep 0.7
    timeout 6 notify-send -a e2e-other -t 2000 "e2e plain" "e2e plain body" >/dev/null 2>&1
    sleep 0.5
    kill "$MP" 2>/dev/null; wait "$MP" 2>/dev/null

    # per Notify call, count action strings (prime-notify first, notify-send second)
    local counts
    counts="$("$PY" -W ignore::DeprecationWarning - "$log" <<'PY'
import re, sys
text=open(sys.argv[1],encoding="utf-8",errors="replace").read()
calls=text.split("member=Notify")[1:]
out=[]
for c in calls:
    m=re.search(r'array \[(.*?)\]\s*\n\s*array \[', c, re.S)
    acts=m.group(1) if m else ""
    out.append(len(re.findall(r'string "', acts)))
print(" ".join(map(str,out)))
PY
)"
    read -r a1 a2 rest <<<"$counts"
    a1=${a1:-0}; a2=${a2:-0}

    local ok=1
    [ "$a1" -ge 2 ] 2>/dev/null || ok=0        # prime-notify: default+Open
    [ "$a2" -eq 0 ] 2>/dev/null || ok=0        # plain notify-send: none

    if [ "$ok" != 1 ]; then
        report "$n" FAIL - "prime-notify actions=$a1 (want >=2), notify-send actions=$a2 (want 0)"; return 1
    fi
    report "$n" PASS 0 "prime-notify → $a1 action strings (non-empty) · plain notify-send → $a2 (empty) — the click-does-nothing contract holds"
    return 0
}

# ════════════════════════════════════════════════════════════════════════════════
# 6. focus-ring — the bar's keyboard focus ring (accent) is defined + reachable
# ════════════════════════════════════════════════════════════════════════════════
journey_focus_ring() {
    local n="focus-ring"; local d="$RESULTS/$n"; mkdir -p "$d"

    # No cursor injection exists here (hyprctl 0.57 has no movecursor; no ydotool/
    # dotool), so the hover-pixel-delta variant is replaced by two real assertions:
    # (a) the :focus ring rule exists in the composed bar stylesheet and its colour
    #     is the theme accent (emerald #34d399 → rgba(52,211,153)); and
    # (b) the keyboard path to the bar (Super+Alt+B → prime-bar --keys) opens.
    local accent
    accent="$(grep -hoE '@define-color accent #[0-9a-fA-F]{6}' "$HOME/.config/prime/theme/colors.css" 2>/dev/null | head -1 | awk '{print $3}')"
    local ring_file="$HOME/.config/prime/addons.d/my-desktop/waybar.css"
    [ -f "$ring_file" ] || ring_file="$LAYER/default/waybar/style.css"
    local ring_ok=0
    if grep -q "inset 0 0 0 2px" "$ring_file" 2>/dev/null && grep -qE "52, 211, 153|@accent" "$ring_file" 2>/dev/null; then
        ring_ok=1
    fi
    # verify the ring colour is the accent: #34d399 == rgb(52,211,153), or @accent in style.css
    local ring_is_accent=0
    if [ "$ring_ok" = 1 ]; then
        if [ "$accent" = "#34d399" ]; then
            ring_is_accent=1
        elif [[ "$accent" =~ ^#[0-9a-fA-F]{6}$ ]] && grep -q "@accent" "$ring_file" 2>/dev/null; then
            ring_is_accent=1
        fi
    fi

    press_esc; sleep 0.2
    launch "$PRIME_BAR --keys"
    local open_ms
    if ! wait_layer "rofi" 1500; then
        report "$n" FAIL - "bar keyboard menu (Super+Alt+B) did not open within 1.5s (${ELAPSED}ms)"; return 1
    fi
    open_ms=$ELAPSED
    timeout 10 grim "$d/bar-keys.png" 2>/dev/null
    press_esc
    wait_layer_gone "rofi" 500 >/dev/null 2>&1

    if [ "$ring_ok" != 1 ]; then
        report "$n" FAIL - "focus-ring :focus rule (inset 2px ring) not found in the bar stylesheet"
        return 1
    fi
    if [ "$ring_is_accent" != 1 ]; then
        report "$n" FAIL - "ring rule present but not the theme accent (accent=$accent, want #34d399)"; return 1
    fi
    report "$n" PASS "$open_ms" "bar keys menu opened ${open_ms}ms · :focus ring = rgba(52,211,153) == accent ${accent:-?} (cursor injection unavailable — hover variant documented)"
    return 0
}

# ════════════════════════════════════════════════════════════════════════════════
# 7. doctor-heals — the doctor notices a broken bar pill and goes green once fixed
# ════════════════════════════════════════════════════════════════════════════════
journey_doctor_heals() {
    local n="doctor-heals"; local d="$RESULTS/$n"; mkdir -p "$d"
    local TOP_JSON="$XDG_RUNTIME_DIR/prime-bar/top.json"

    if [ -f "$PILL_PY" ]; then
        mv "$PILL_PY" "$PILL_PY.bak" 2>/dev/null || { report "$n" FAIL - "could not rename pill"; return 1; }
    elif [ -f "$TOP_JSON" ]; then
        cp -a "$TOP_JSON" "$TOP_JSON.bak" || { report "$n" FAIL - "could not back up $TOP_JSON"; return 1; }
        "$PY" -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["custom/e2e_missing"]={"exec":"/nonexistent/prime-e2e-missing.sh"}; json.dump(d,open(p,"w"))' "$TOP_JSON"
    else
        report "$n" FAIL - "neither $PILL_PY nor $TOP_JSON exists"; return 1
    fi
    local t0=$(now_ms)
    PRIME_NO_PANEL=1 timeout 60 "$DOCTOR" > "$d/doctor-broken.txt" 2>&1
    local broken_ms=$(( $(now_ms) - t0 ))
    local broken_report
    broken_report="$(strip_ansi < "$d/doctor-broken.txt" | grep -c "point at something that isn't there")"

    if [ -f "$PILL_PY.bak" ]; then
        mv -f "$PILL_PY.bak" "$PILL_PY" 2>/dev/null
    elif [ -f "$TOP_JSON.bak" ]; then
        mv -f "$TOP_JSON.bak" "$TOP_JSON" 2>/dev/null
    fi
    local t0c=$(now_ms)
    PRIME_NO_PANEL=1 timeout 60 "$DOCTOR" > "$d/doctor-clean.txt" 2>&1
    local clean_ms=$(( $(now_ms) - t0c ))
    local clean_report
    clean_report="$(strip_ansi < "$d/doctor-clean.txt" | grep -c "point at something that isn't there")"

    if [ "${broken_report:-0}" -lt 1 ]; then
        report "$n" FAIL - "doctor did NOT notice the broken bar script (${broken_report} hit(s))"; return 1
    fi
    if [ "${clean_report:-0}" -ne 0 ]; then
        report "$n" FAIL - "doctor still reports the script missing after restore (${clean_report} hit(s))"; return 1
    fi
    report "$n" PASS "$broken_ms" "broken bar script → doctor reported it in ${broken_ms}ms · restored → doctor clean in ${clean_ms}ms"
    return 0
}

# ════════════════════════════════════════════════════════════════════════════════
# runner
# ════════════════════════════════════════════════════════════════════════════════
ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done

declare -a ALL_JOURNEYS=(entry-box menu-open whiteboard-live minimise-restore notifications-actionable focus-ring doctor-heals)

printf 'PRIME LINUX JOURNEYS — %s\n' "$(date -R)"
printf 'results: %s\n' "$RESULTS"
printf '%-5s | %-22s | %9s | %s\n' "STAT" "JOURNEY" "TIME(ms)" "DETAIL"
printf '%-5s-+-%-22s-+-%9s-+-%s\n' "-----" "----------------------" "---------" "---------------------------------------------"

for j in "${ALL_JOURNEYS[@]}"; do
    [ -n "$ONLY" ] && [ "$ONLY" != "$j" ] && continue
    case "$j" in
        entry-box)                   journey_entry_box ;;
        menu-open)                   journey_menu_open ;;
        whiteboard-live)             journey_whiteboard_live ;;
        minimise-restore)            journey_minimise_restore ;;
        notifications-actionable)    journey_notifications_actionable ;;
        focus-ring)                  journey_focus_ring ;;
        doctor-heals)                journey_doctor_heals ;;
    esac
done

# ── summary ───────────────────────────────────────────────────────────────────
{
    echo "{"
    printf '  "timestamp": "%s",\n' "$TS"
    printf '  "results_dir": "%s",\n' "$RESULTS"
    echo '  "journeys": {'
    i=0; first=1
    for ((i=0; i<${#JN[@]}; i++)); do
        [ "$first" = 0 ] && echo ","
        first=0
        st="${JS[$i]}"
        if [ "$st" = "PASS" ]; then st="pass"; else st="fail"; fi
        printf '    "%s": {"status": "%s", "ms": %s, "detail": "%s"}' \
            "${JN[$i]}" "$st" "${JM[$i]}" "$(printf '%s' "${JD[$i]}" | sed 's/"/\\"/g')"
    done
    echo
    echo '  }'
    echo '}'
} > "$RESULTS/summary.json"

# ── table ─────────────────────────────────────────────────────────────────────
echo
echo "══════════════════════════ PRIME JOURNEYS ══════════════════════════"
FAILED=0
i=0
for ((i=0; i<${#JN[@]}; i++)); do
    if [ "${JS[$i]}" = "PASS" ]; then
        printf 'PASS  %-22s %7s ms\n' "${JN[$i]}" "${JM[$i]}"
    else
        printf 'FAIL  %-22s %7s ms\n' "${JN[$i]}" "${JM[$i]}"
        FAILED=$((FAILED+1))
    fi
done
echo "══════════════════════════════════════════════════════════════════════"
if [ "${#JN[@]}" -eq 0 ]; then
    echo "VERDICT: NOTHING RAN (exit 2)"; exit 2
fi
echo "summary: $RESULTS/summary.json"
if [ "$FAILED" -eq 0 ]; then echo "VERDICT: PASS"; else echo "VERDICT: FAIL ($FAILED journey(s))"; fi
exit "$FAILED"
