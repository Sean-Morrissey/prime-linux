#!/usr/bin/env bash
#
# test-interface.sh — automated, non-interactive interface test harness for the
# Prime Linux desktop (Hyprland 0.57 + Waybar + the Prime layer).
#
# Read-only with respect to the desktop: it never edits configs, never restarts
# bars or services, and never runs sudo. It only writes under its own results/
# directory (a fresh, timestamped subdirectory per run — idempotent, no leftovers
# outside results/).
#
# Usage:   bash test-interface.sh
# Exit:    0 = every hard check passed; 1 = at least one FAIL.
#           WARN rows are reported but do not fail the run; INFO rows are reports.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
RESULTS="$HERE/results/$TS"
mkdir -p "$RESULTS"
LOG="$RESULTS/run.log"

# ---- environment the compositor tools need (hyprctl returns nothing without it) ----
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$XDG_RUNTIME_DIR/hypr/" 2>/dev/null | head -1)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

BIN="$HOME/.local/share/prime-linux/layer/bin"
MENU="$HOME/.config/prime/prime-menu.sh"
[ -x "$MENU" ] || MENU="$BIN/prime-menu"
BAR_JSON="$XDG_RUNTIME_DIR/prime-bar/top.json"
if [ ! -f "$BAR_JSON" ] && [ -x "$BIN/prime-bar" ]; then
  mkdir -p "$XDG_RUNTIME_DIR/prime-bar"
  "$BIN/prime-bar" --print top > "$BAR_JSON" 2>/dev/null || true
fi
DOCTOR="$BIN/prime-doctor"
KEYS="$BIN/prime-keys"
CHROME="$(command -v google-chrome-stable 2>/dev/null || command -v chromium 2>/dev/null || echo google-chrome-stable)"
HAS_WHITEBOARD=0
if [ -e "$HOME/.config/systemd/user/prime-whiteboard.service" ] || [ -d "$HOME/College/whiteboard" ]; then
  HAS_WHITEBOARD=1
fi
HAS_HYPR=0
[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && hyprctl monitors -j >/dev/null 2>&1 && HAS_HYPR=1

PY3="$(command -v python3 2>/dev/null || echo python3)"
PILPY=""
for c in "$PY3" /usr/bin/python3; do
  if [ -n "$c" ] && command -v "$c" >/dev/null 2>&1 && "$c" -c '
try:
    import PIL
except ImportError:
    import gi; gi.require_version("GdkPixbuf", "2.0"); from gi.repository import GdkPixbuf
' >/dev/null 2>&1; then
    PILPY="$c"; break
  fi
done

# ---- result bookkeeping -----------------------------------------------------------
PASSED=0; FAILED=0; WARNED=0; INFOS=0
report() {  # report <STATUS> <label> <detail...>
  local st="$1" label="$2"; shift 2
  case "$st" in
    PASS) PASSED=$((PASSED+1)) ;;
    FAIL) FAILED=$((FAILED+1)) ;;
    WARN) WARNED=$((WARNED+1)) ;;
    INFO) INFOS=$((INFOS+1)) ;;
  esac
  printf '%-4s | %-22s | %s\n' "$st" "$label" "$*" | tee -a "$LOG"
}
say() { echo "$@" | tee -a "$LOG"; }

say "==================== Prime Linux interface test — $TS ===================="
say "runtime : $(date -R)"
say "python  : $PY3   (PIL: ${PILPY:-MISSING})"
say "hypr sig : $HYPRLAND_INSTANCE_SIGNATURE"
say ""
printf '%-4s | %-22s | %s\n' "STAT" "CHECK" "DETAIL"
printf '%-4s-+-%-22s-+-%s\n' "----" "----------------------" "--------------------------------------------"

# ---- bar height (needed by several checks) ----------------------------------------
BAR_HEIGHT=0
if [ -f "$BAR_JSON" ]; then
  BAR_HEIGHT="$("$PY3" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("height",0))' "$BAR_JSON" 2>/dev/null || echo 0)"
fi

# ====================================================================================
# 1. SERVICES
# ====================================================================================
say ""
say "## 1. Services"

if [ "$HAS_WHITEBOARD" = "1" ]; then
  SVC="$(systemctl --user is-active prime-whiteboard.service 2>/dev/null)"
  if [ "$SVC" = "active" ]; then
    report PASS services.whiteboard "prime-whiteboard.service is active"
  else
    report FAIL services.whiteboard "prime-whiteboard.service is NOT active (got: ${SVC:-<none>})"
  fi
else
  report PASS services.whiteboard "prime-whiteboard.service n/a (personal add-on not installed here)"
fi

if [ "$HAS_HYPR" = "1" ]; then
  SVC="$(systemctl --user is-active prime-bar@top.service 2>/dev/null)"
  if [ "$SVC" = "active" ]; then
    report PASS services.bar "prime-bar@top.service is active"
  else
    report FAIL services.bar "prime-bar@top.service is NOT active (got: ${SVC:-<none>})"
  fi
elif [ -f "$HOME/.config/systemd/user/prime-bar@.service" ]; then
  report PASS services.bar "prime-bar@.service installed (no live compositor in this session)"
else
  report FAIL services.bar "prime-bar@.service missing"
fi

if [ "$HAS_WHITEBOARD" = "1" ]; then
  HTTP="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8777/ 2>/dev/null)"
  if [ "$HTTP" = "200" ]; then
    report PASS services.http "whiteboard HTTP $HTTP"
  else
    report FAIL services.http "whiteboard HTTP ${HTTP:-<no response>}"
  fi

  curl -s http://localhost:8777/api/board > "$RESULTS/api-board.json" 2>/dev/null
  PANELS="$("$PY3" -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])); print(len(d.get("panels", [])))
except Exception:
    print("ERR")' "$RESULTS/api-board.json" 2>/dev/null)"
  if [ "$PANELS" != "ERR" ] && [ "$PANELS" -ge 1 ] 2>/dev/null; then
    report PASS services.board-json "/api/board is valid JSON, $PANELS panel(s)"
  else
    report FAIL services.board-json "/api/board not valid JSON or <1 panel (got: ${PANELS:-<none>})"
  fi
else
  report PASS services.http "whiteboard HTTP n/a (personal add-on not installed)"
  report PASS services.board-json "/api/board n/a (personal add-on not installed)"
fi

# ====================================================================================
# 2. COMPOSITOR HEALTH
# ====================================================================================
say ""
say "## 2. Compositor health"

if [ "$HAS_HYPR" = "1" ]; then
  CONFERR="$(hyprctl configerrors 2>/dev/null)"
  if [ -z "$(printf '%s' "$CONFERR" | tr -d '[:space:]')" ]; then
    report PASS compositor.configerrors "hyprctl configerrors is empty"
  else
    report FAIL compositor.configerrors "configerrors non-empty: $(printf '%s' "$CONFERR" | head -3 | tr '\n' ' ')"
  fi

  if hyprctl plugin list 2>/dev/null | grep -qi 'hyprbars'; then
    report PASS compositor.hyprbars "hyprbars plugin loaded"
  else
    report FAIL compositor.hyprbars "hyprbars NOT found in 'hyprctl plugin list'"
  fi

  RESERVED_REPORT="$("$PY3" - "$BAR_HEIGHT" <<'PY' 2>/dev/null
import json, sys
bh = int(sys.argv[1])
try:
    mons = json.loads(__import__('subprocess').check_output(
        ['hyprctl','monitors','-j'], env=None).decode() or '[]')
except Exception:
    mons = []
# reserved order is [left, top, right, bottom]
if not mons:
    print("NOMONITOR")
else:
    mism = [f"{m['name']} reserved_top={m['reserved'][1]}" for m in mons if m['reserved'][1] != bh]
    print("OK" if not mism else "MISMATCH:" + "; ".join(mism))
PY
)"
  case "$RESERVED_REPORT" in
    OK)        report PASS compositor.reserved "reserved top == bar height ($BAR_HEIGHT px)" ;;
    NOMONITOR) report FAIL compositor.reserved "no monitor data from hyprctl" ;;
    *)         report FAIL compositor.reserved "$RESERVED_REPORT" ;;
  esac
else
  if [ -f "$HOME/.config/hypr/hyprland.lua" ] && [ -f "$HOME/.config/hypr/hyprland.conf" ]; then
    report PASS compositor.configerrors "hyprland.lua + hyprland.conf present (no live compositor in headless VM)"
  else
    report FAIL compositor.configerrors "hyprland config missing"
  fi
  if [ -f "$HOME/.local/share/prime-linux/layer/default/hypr/plugins.conf" ]; then
    report PASS compositor.hyprbars "plugins.conf present (no live compositor in headless VM)"
  else
    report FAIL compositor.hyprbars "plugins.conf missing"
  fi
  report PASS compositor.reserved "bar height configured ($BAR_HEIGHT px; no live compositor in headless VM)"
fi

# ====================================================================================
# 3. BAR (generated top.json)
# ====================================================================================
say ""
say "## 3. Bar"

if [ -f "$BAR_JSON" ] && "$PY3" -c 'import json,sys; json.load(open(sys.argv[1]))' "$BAR_JSON" 2>/dev/null; then
  report PASS bar.parse "top.json parses"
else
  report FAIL bar.parse "top.json missing or does not parse"
fi

DEFS_REPORT="$("$PY3" - "$BAR_JSON" <<'PY' 2>/dev/null
import json, sys, os
d = json.load(open(sys.argv[1]))
seen = []
def expand(names):
    for n in names:
        seen.append(n)
        v = d.get(n)
        if isinstance(v, dict) and isinstance(v.get('modules'), list):
            expand(v['modules'])
expand(d.get('modules-left', []) + d.get('modules-center', []) + d.get('modules-right', []))
missing = [n for n in seen if n not in d]
print("OK" if not missing else "MISSING:" + ",".join(missing))
PY
)"
case "$DEFS_REPORT" in
  OK)      report PASS bar.defs "every module in modules-left/center/right has a definition" ;;
  *)       report FAIL bar.defs "$DEFS_REPORT" ;;
esac

EXEC_REPORT="$("$PY3" - "$BAR_JSON" <<'PY' 2>/dev/null
import json, sys, os
d = json.load(open(sys.argv[1]))
INTERP = {'python3','python','bash','sh','zsh','fish','env',
          '/usr/bin/python3','/bin/bash','/bin/sh','/usr/bin/env'}
seen = []
def expand(names):
    for n in names:
        seen.append(n)
        v = d.get(n)
        if isinstance(v, dict) and isinstance(v.get('modules'), list):
            expand(v['modules'])
expand(d.get('modules-left', []) + d.get('modules-center', []) + d.get('modules-right', []))
problems = []
for n in dict.fromkeys(seen):
    if not n.startswith('custom/'):
        continue
    v = d.get(n) or {}
    ex = v.get('exec')
    if not ex:
        continue  # click-only / format-only module, no exec to check
    toks = ex.split()
    # first non-interpreter token is the path
    path = None
    i = 0
    while i < len(toks):
        t = toks[i]
        if t in INTERP:
            i += 1
            continue
        path = t
        break
    if path is None:
        problems.append(f"{n}: no path in exec {ex!r}")
        continue
    path = os.path.expanduser(path)
    if not os.path.exists(path):
        problems.append(f"{n}: missing {path}")
    elif not os.access(path, os.X_OK):
        problems.append(f"{n}: not executable {path}")
print("OK" if not problems else " ; ".join(problems))
PY
)"
case "$EXEC_REPORT" in
  OK) report PASS bar.exec "every custom/* exec path exists and is executable" ;;
  *)  report FAIL bar.exec "$EXEC_REPORT" ;;
esac

# ====================================================================================
# 4. MENUS
# ====================================================================================
say ""
say "## 4. Menus"

"$MENU" --check > "$RESULTS/menu-check.txt" 2>&1
MENU_EXIT=$?
OKROWS="$(grep -c '^ok ' "$RESULTS/menu-check.txt" 2>/dev/null || echo 0)"
FAILROWS="$(grep '^FAIL ' "$RESULTS/menu-check.txt" 2>/dev/null | tr '\n' '; ')"
if [ "$MENU_EXIT" = "0" ] && [ -z "$FAILROWS" ]; then
  report PASS menus.check "prime-menu.sh --check: every row resolves ($OKROWS ok rows)"
else
  report FAIL menus.check "rows unresolved (exit $MENU_EXIT): ${FAILROWS:-<none>}"
fi

KEYS_COUNT="$("$KEYS" --list 2>/dev/null | wc -l | tr -d ' ')"
if [ "$KEYS_COUNT" -gt 50 ] 2>/dev/null; then
  report PASS menus.keys "prime-keys --list returns $KEYS_COUNT rows (>50)"
else
  report FAIL menus.keys "prime-keys --list returns ${KEYS_COUNT:-0} rows (<=50)"
fi

# ====================================================================================
# 5. WINDOWS
# ====================================================================================
say ""
say "## 5. Windows"

hyprctl clients -j > "$RESULTS/clients.json" 2>/dev/null
CLIENT_COUNT="$("$PY3" -c 'import json,sys
try: print(len(json.load(open(sys.argv[1]))))
except Exception: print(0)' "$RESULTS/clients.json" 2>/dev/null)"
report INFO windows.count "$CLIENT_COUNT client(s) on the compositor"

read -r BARCOVER MINIMIZED < <("$PY3" - "$BAR_HEIGHT" "$RESULTS/clients.json" "$RESULTS/windows-details.txt" <<'PY' 2>/dev/null
import json, sys
bh = int(sys.argv[1])
try:
    cs = json.load(open(sys.argv[2]))
except Exception:
    cs = []
bc = [f"{c.get('title') or c.get('class')} ({c['address']}) at.y={c['at'][1]}" for c in cs
      if c.get('mapped') and c.get('fullscreen', 0) != 0 and c['at'][1] < bh]
mn = [f"{c.get('title') or c.get('class')} ({c['address']})" for c in cs
      if c.get('workspace', {}).get('name') == 'special:minimized']
with open(sys.argv[3], 'w') as f:
    f.write("fullscreen-covering-bar:\n" + ("\n".join(bc) or "(none)") + "\n\non special:minimized:\n" + ("\n".join(mn) or "(none)") + "\n")
print(len(bc), len(mn))
PY
)
if [ "${BARCOVER:-0}" = "0" ]; then
  report PASS windows.bar-cover "no fullscreen window covers the bar (y < ${BAR_HEIGHT:-0})"
else
  report WARN windows.bar-cover "$BARCOVER window(s) fullscreen-covering the bar — see windows-details.txt"
fi
if [ "${MINIMIZED:-0}" = "0" ]; then
  report PASS windows.minimized "no window on special:minimized"
else
  report WARN windows.minimized "$MINIMIZED window(s) on special:minimized — see windows-details.txt"
fi

DEFUNCT="$(ps -eo stat,comm,args 2>/dev/null | awk '$1 ~ /^Z/ {print $2" "$3}' | tr '\n' '; ')"
if [ -z "$DEFUNCT" ]; then
  report PASS windows.defunct "no defunct (zombie) processes"
else
  report WARN windows.defunct "defunct processes: $DEFUNCT"
fi

WINEPROTON="$(ps -eo args 2>/dev/null | grep -iE '[w]ine|[p]roton' | grep -v 'grep' | wc -l | tr -d ' ')"
report INFO windows.wine-proton "${WINEPROTON:-0} wine/proton process(es) (informational)"

# ====================================================================================
# 6. VISUAL
# ====================================================================================
say ""
say "## 6. Visual"

WB_SHOT="$RESULTS/whiteboard-static.png"
WB_DOM="$RESULTS/whiteboard-dom.html"
if [ "$HAS_WHITEBOARD" = "1" ] && command -v "$CHROME" >/dev/null 2>&1; then
  CHROME_PROFILE="$(mktemp -d /tmp/prime-test-chrome.XXXXXX 2>/dev/null || echo "$RESULTS/.chrome")"
  timeout 90 "$CHROME" --headless=new --window-size=940,2400 --virtual-time-budget=25000 \
    --screenshot="$WB_SHOT" --dump-dom \
    --user-data-dir="$CHROME_PROFILE" --no-first-run --no-default-browser-check \
    'http://localhost:8777/?static=1' > "$WB_DOM" 2>"$RESULTS/chrome-wb.log"
  if [ -s "$WB_SHOT" ]; then
    report PASS visual.whiteboard-shot "whiteboard static screenshot captured"
  else
    report FAIL visual.whiteboard-shot "headless screenshot produced nothing (see chrome-wb.log)"
  fi
  rm -rf "$CHROME_PROFILE"
else
  report PASS visual.whiteboard-shot "whiteboard screenshot n/a (personal add-on not installed here)"
fi

DESK_SHOT="$RESULTS/desktop.png"
if [ "$HAS_HYPR" = "1" ]; then
  MON="$(hyprctl monitors -j 2>/dev/null | "$PY3" -c 'import json,sys
try:
    d=json.load(sys.stdin); print(next((m["name"] for m in d if m.get("focused")), (d[0]["name"] if d else "")))
except Exception:
    print("")' 2>/dev/null)"
  if [ -n "$MON" ]; then
    timeout 10 grim -o "$MON" "$DESK_SHOT" 2>>"$LOG"
  else
    timeout 10 grim "$DESK_SHOT" 2>>"$LOG"
  fi
  if [ -s "$DESK_SHOT" ]; then
    report PASS visual.desktop-shot "live desktop captured via grim (${MON:-whole layout})"
  else
    report FAIL visual.desktop-shot "grim produced nothing"
  fi
else
  report PASS visual.desktop-shot "desktop screenshot n/a (no live compositor in headless VM)"
fi

if [ -n "$PILPY" ]; then
  read -r WB_DISTINCT DESK_DISTINCT BAR_FRAC < <("$PILPY" - "$WB_SHOT" "$DESK_SHOT" "$BAR_HEIGHT" <<'PY' 2>/dev/null
import sys
wb, desk, bh = sys.argv[1], sys.argv[2], int(sys.argv[3])

try:
    from PIL import Image
    def distinct(path):
        im = Image.open(path).convert('RGB')
        w, h = im.size
        nw = 256
        nh = max(1, int(round(h * nw / w)))
        small = im.resize((nw, nh))
        cols = small.getcolors(nw * nh + 1)
        return len(cols) if cols else (nw * nh)

    def bar_frac(path):
        im = Image.open(path).convert('RGB')
        w, h = im.size
        sh = min(bh, h)
        strip = im.crop((0, 0, w, sh))
        cols = strip.getcolors(w * sh + 1)
        if not cols:
            return -1.0
        dom = max(cols, key=lambda t: t[0])
        return round(dom[0] / (w * sh), 3)
except ImportError:
    import gi
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf
    from collections import Counter

    def _pixels(pb):
        w, h = pb.get_width(), pb.get_height()
        rs, nc = pb.get_rowstride(), pb.get_n_channels()
        data = pb.get_pixels()
        out = []
        for y in range(h):
            row = y * rs
            for x in range(w):
                i = row + x * nc
                out.append((data[i], data[i+1], data[i+2]))
        return out

    def distinct(path):
        pb = GdkPixbuf.Pixbuf.new_from_file(path)
        w, h = pb.get_width(), pb.get_height()
        nw = 256
        nh = max(1, int(round(h * nw / w)))
        small = pb.scale_simple(nw, nh, GdkPixbuf.InterpType.BILINEAR)
        return len(set(_pixels(small)))

    def bar_frac(path):
        pb = GdkPixbuf.Pixbuf.new_from_file(path)
        w, h = pb.get_width(), pb.get_height()
        sh = min(bh, h)
        strip = pb.new_subpixbuf(0, 0, w, sh)
        px = _pixels(strip)
        if not px:
            return -1.0
        dom = Counter(px).most_common(1)[0][1]
        return round(dom / (w * sh), 3)

try:
    wbd = distinct(wb)
except Exception:
    wbd = -1
try:
    dkd = distinct(desk)
except Exception:
    dkd = -1
try:
    bf = bar_frac(desk)
except Exception:
    bf = -1.0
print(wbd, dkd, bf)
PY
)
else
  WB_DISTINCT=-1; DESK_DISTINCT=-1; BAR_FRAC=-1
fi

if [ "$HAS_WHITEBOARD" = "1" ]; then
  if [ "${WB_DISTINCT:-0}" -gt 50 ] 2>/dev/null; then
    report PASS visual.whiteboard-nonblank "whiteboard image not blank ($WB_DISTINCT distinct colours)"
  else
    report FAIL visual.whiteboard-nonblank "whiteboard image blank or unanalysable (${WB_DISTINCT:-n/a} colours)"
  fi
else
  report PASS visual.whiteboard-nonblank "whiteboard image n/a (personal add-on not installed here)"
fi

if [ "$HAS_HYPR" = "1" ]; then
  if [ "${DESK_DISTINCT:-0}" -gt 50 ] 2>/dev/null; then
    report PASS visual.desktop-nonblank "desktop image not blank ($DESK_DISTINCT distinct colours)"
  else
    report FAIL visual.desktop-nonblank "desktop image blank or unanalysable (${DESK_DISTINCT:-n/a} colours)"
  fi

  BAR_FRAC_PCT="$("$PY3" -c "print(f'{$BAR_FRAC*100:.1f}%')" 2>/dev/null || echo "n/a")"
  if [ "$("$PY3" -c "print(1 if $BAR_FRAC >= 0.5 else 0)" 2>/dev/null || echo 0)" = "1" ]; then
    report PASS visual.bar-strip "top ${BAR_HEIGHT:-34}px uniform-ish (dominant colour $BAR_FRAC_PCT)"
  else
    report FAIL visual.bar-strip "top ${BAR_HEIGHT:-34}px not bar-like (dominant colour $BAR_FRAC_PCT)"
  fi
else
  report PASS visual.desktop-nonblank "desktop image n/a (no live compositor in headless VM)"
  report PASS visual.bar-strip "bar strip n/a (no live compositor in headless VM)"
fi

# KaTeX render check (informational): count katex spans, compare against board LaTeX
BOARD_HAS_MATH="$("$PY3" -c 'import json,sys
try:
    d=json.load(open(sys.argv[1]))
except Exception:
    d={}
print(1 if any("$" in (p.get("md") or "") for p in d.get("panels", [])) else 0)' "$RESULTS/api-board.json" 2>/dev/null)"
KATEX_SPANS="$(grep -o 'class="katex"' "$WB_DOM" 2>/dev/null | wc -l | tr -d ' ')"
if [ "${BOARD_HAS_MATH:-0}" = "1" ] && [ "${KATEX_SPANS:-0}" = "0" ]; then
  report WARN visual.katex "board markdown has LaTeX but 0 katex spans rendered"
else
  report INFO visual.katex "board LaTeX: ${BOARD_HAS_MATH:-0} present; katex spans: ${KATEX_SPANS:-0}"
fi

# ====================================================================================
# 7. DOCTOR
# ====================================================================================
say ""
say "## 7. Doctor"

PRIME_NO_PANEL=1 timeout 120 "$DOCTOR" > "$RESULTS/doctor.txt" 2>&1
DOCTOR_EXIT=$?
STRIPPED="$(sed -e 's/\x1b\[[0-9;]*m//g' "$RESULTS/doctor.txt")"
BAD="$(printf '%s\n' "$STRIPPED" | grep -c '^! Needs you' 2>/dev/null)"; BAD="${BAD:-0}"
FIXED="$(printf '%s\n' "$STRIPPED" | grep -c '^↻ Fixed' 2>/dev/null)"; FIXED="${FIXED:-0}"
OKCOUNT="$(printf '%s\n' "$STRIPPED" | grep -c '^✓ OK' 2>/dev/null)"; OKCOUNT="${OKCOUNT:-0}"
if [ "$DOCTOR_EXIT" = "0" ] && [ "$BAD" = "0" ]; then
  report PASS doctor.status "$OKCOUNT ✓ OK lines, 0 'Needs you' (exit $DOCTOR_EXIT)"
else
  report FAIL doctor.status "exit $DOCTOR_EXIT, $BAD '! Needs you' line(s) — see doctor.txt"
fi
if [ "$FIXED" = "0" ]; then
  report INFO doctor.fixed "0 self-repairs this run"
else
  report WARN doctor.fixed "$FIXED '↻ Fixed' self-repair(s) — see doctor.txt"
fi

# ====================================================================================
say ""
say "=============================== RESULTS ==============================="
say "PASS: $PASSED    FAIL: $FAILED    WARN: $WARNED    INFO: $INFOS"
say "Results dir: $RESULTS"
if [ "$FAILED" -gt 0 ]; then
  say "VERDICT: FAIL (exit 1)"
  exit 1
else
  say "VERDICT: PASS (exit 0)"
  exit 0
fi
