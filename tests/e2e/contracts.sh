#!/usr/bin/env bash
# contracts.sh — Prime Linux desktop contract tests.
#
# Each contract asserts one guarantee about the desktop that must not regress.
# Run with:  bash contracts.sh
# Results land in results/<timestamp>/contracts/ ; exit non-zero on any failure.
#
# Contract 1  notifications-carry-actions : prime-notify's Notify call carries a
#              non-empty actions array; bare notify-send sends an EMPTY one.
# Contract 2  contrast-budget             : WCAG contrast of fg / fg_dim /
#              fg_faint / workspace dot, computed from the real CSS, >= 4.5:1.
# Contract 3  text-scale-propagates       : every font target is wired to
#              prime-theme's size() and the three rofi themes resolve
#              var(prime-font-body).
# Contract 4  keyboard-reachability       : every surface has a keyboard path.
# Contract 5  layer-tree-clean            : the shipped layer git tree is clean.
# Contract 6  no-portability-leaks        : no /home/sean/ or machine-specific
#              strings in the shipped menu/element JSON.
# Contract 7  plugin-version-gate         : the saved Hyprland commit matches the
#              running one and the hyprpm watch timer is enabled + active.

set -u

# ── paths ────────────────────────────────────────────────────────────────────
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME:-/home/sean}"
LAYER="$HOME_DIR/.local/share/prime-linux/layer"
REPO_LAYER="$(cd "$SELF/../../layer" 2>/dev/null && pwd || echo "$LAYER")"
# Inside the VM, install.sh has installed HEAD into $LAYER, so test $LAYER strictly.
# On the host before merge, $LAYER is the last released commit and must stay clean,
# so check $LAYER first and fall back to $REPO_LAYER for pre-merge branch files.
if [ "${PRIME_E2E_VM:-0}" = "1" ]; then
  CHECK_LAYER="$LAYER"
else
  CHECK_LAYER="$REPO_LAYER"
fi
TS="$(date +%Y%m%d-%H%M%S)"
RESULTS="$SELF/results/$TS/contracts"
mkdir -p "$RESULTS"

LAYER_CSS="$LAYER/default/waybar/style.css"
OVERRIDE_CSS="$HOME_DIR/.config/prime/addons.d/my-desktop/waybar.css"
THEME_DIR="$HOME_DIR/.config/prime/theme"
GEN="$LAYER/bin/prime-theme"

# ── environment for live checks (hyprctl, dbus, wtype) ───────────────────────
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && \
    export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr/" 2>/dev/null | head -1)"
[ -z "${WAYLAND_DISPLAY:-}" ] && export WAYLAND_DISPLAY="wayland-1"

# ── a Prime command, found the way the desktop session finds it ─────────────
# The session's PATH is the systemd user manager's (environment.d puts
# ~/.local/bin on it); an ssh or cron shell on stock Arch does not have it.
SESSION_PATH="$(systemctl --user show-environment 2>/dev/null | sed -n 's/^PATH=//p')"
prime_cmd() {   # prime_cmd <name> → absolute path on the session PATH, or nothing
  PATH="${SESSION_PATH:+$SESSION_PATH:}$PATH" command -v "$1" 2>/dev/null
}

# ── result bookkeeping ───────────────────────────────────────────────────────
declare -a T_NAMES=() T_STATUS=() T_NOTES=()
record() { T_NAMES+=("$1"); T_STATUS+=("$2"); T_NOTES+=("${3:-}"); }
ok()   { echo "    ✓ $*"; }
bad()  { echo "    ✗ $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# Contract 1 — notifications-carry-actions
# ─────────────────────────────────────────────────────────────────────────────
contract_notifications() {
  local rc=0 log1="$RESULTS/notify-prime.log" log2="$RESULTS/notify-bare.log" n1=0 n2=0 stub_pid=""

  # prime-notify must be on the session's PATH: that is how every caller reaches it
  local PN; PN="$(prime_cmd prime-notify)"
  if [ -n "$PN" ]; then
    ok "prime-notify is on the session PATH ($PN)"
  else
    bad "prime-notify is not on the session PATH (systemctl --user show-environment)"; rc=1
    PN=prime-notify
  fi

  # If no notification daemon owns org.freedesktop.Notifications (e.g. headless VM
  # without a Wayland compositor for swaync), run a minimal DBus responder so
  # notify-send can complete its Notify method call instead of failing DBus activation.
  if ! gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
       --method org.freedesktop.DBus.NameHasOwner org.freedesktop.Notifications 2>/dev/null | grep -q true; then
    python3 - <<'PY' >/dev/null 2>&1 &
import dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName("org.freedesktop.Notifications", bus)
class Stub(dbus.service.Object):
    _id = 0
    @dbus.service.method("org.freedesktop.Notifications", in_signature="", out_signature="as")
    def GetCapabilities(self): return ["actions", "body"]
    @dbus.service.method("org.freedesktop.Notifications", in_signature="susssasa{sv}i", out_signature="u")
    def Notify(self, app, rep, icon, summary, body, actions, hints, timeout):
        Stub._id += 1; return Stub._id
    @dbus.service.method("org.freedesktop.Notifications", in_signature="u", out_signature="")
    def CloseNotification(self, nid): pass
    @dbus.service.method("org.freedesktop.Notifications", in_signature="", out_signature="ssss")
    def GetServerInformation(self): return ("prime-stub", "prime", "1.0", "1.2")
s = Stub(bus, "/org/freedesktop/Notifications")
GLib.MainLoop().run()
PY
    stub_pid=$!
    sleep 0.5
  fi

  # prime-notify with an action
  ( timeout 8 dbus-monitor --session "interface='org.freedesktop.Notifications'" > "$log1" 2>/dev/null & )
  sleep 1
  "$PN" -t "Contract test" -b "actions must be non-empty" -a 'true' >/dev/null 2>&1
  sleep 1
  n1="$(awk '
      /^method call .*member=Notify/ { seen=0; collecting=0; n=0; next }
      !seen && /array \[/ { collecting=1; seen=1; next }
      collecting && /^[[:space:]]*\]/ { print n; collecting=0; next }
      collecting && /string "/ { n++ }
    ' "$log1" | head -1)"
  n1="${n1:-0}"

  # bare notify-send (the regression class: click does nothing)
  ( timeout 8 dbus-monitor --session "interface='org.freedesktop.Notifications'" > "$log2" 2>/dev/null & )
  sleep 1
  notify-send "Contract test" "bare notify-send" >/dev/null 2>&1
  sleep 1
  [ -n "$stub_pid" ] && kill "$stub_pid" 2>/dev/null || true
  n2="$(awk '
      /^method call .*member=Notify/ { seen=0; collecting=0; n=0; next }
      !seen && /array \[/ { collecting=1; seen=1; next }
      collecting && /^[[:space:]]*\]/ { print n; collecting=0; next }
      collecting && /string "/ { n++ }
    ' "$log2" | head -1)"
  n2="${n2:-0}"

  if [ "$n1" -ge 1 ] && grep -q 'string "default"' "$log1" && grep -q 'string "Open"' "$log1"; then
    ok "prime-notify Notify call carries actions: ['default','Open'] ($n1 action string(s))"
  else
    bad "prime-notify Notify call actions missing (got $n1 action string(s))"; rc=1
  fi

  if [ "$n2" -eq 0 ]; then
    ok "bare notify-send sends an EMPTY actions array (regression class documented)"
  else
    bad "bare notify-send unexpectedly sent $n2 action string(s)"; rc=1
  fi
  return $rc
}

# ─────────────────────────────────────────────────────────────────────────────
# Contract 2 — contrast-budget (reads the real CSS, computes WCAG)
# ─────────────────────────────────────────────────────────────────────────────
contract_contrast() {
  python3 - "$LAYER_CSS" "$OVERRIDE_CSS" <<'PY'
import re, sys
layer, override = sys.argv[1], sys.argv[2]

def parse_colors(text):
    d = {}
    for m in re.finditer(r'@define-color\s+([A-Za-z0-9_]+)\s+([^;]+);', text):
        d[m.group(1)] = m.group(2).strip()
    return d

def parse_ws_dot(text):
    m = re.search(r'#workspaces\s+button\s*\{[^}]*color:\s*([^;}]+)', text)
    return m.group(1).strip() if m else None

colors = {}
ws_dot = None
# cascade order: layer defines, override wins
import os
for path in (layer, override):
    if not os.path.exists(path):   # the personal add-on override is optional
        continue
    t = open(path).read()
    colors.update(parse_colors(t))
    w = parse_ws_dot(t)
    if w:
        ws_dot = w

def to_rgba(val):
    m = re.match(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([0-9.]+)\s*)?\)', val)
    if m:
        return (int(m.group(1)), int(m.group(2)), int(m.group(3)),
                float(m.group(4)) if m.group(4) else 1.0)
    m = re.match(r'#([0-9a-fA-F]{6})', val)
    if m:
        h = m.group(1)
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 1.0)
    m = re.match(r'#([0-9a-fA-F]{3})', val)
    if m:
        h = m.group(1)
        return (int(h[0]*2, 16), int(h[1]*2, 16), int(h[2]*2, 16), 1.0)
    raise ValueError("unparsable colour: %r" % val)

BG = (12, 12, 16)  # #0c0c10 — the bar's solid background

def lum(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

def rel(rgb):
    return 0.2126 * lum(rgb[0]) + 0.7152 * lum(rgb[1]) + 0.0722 * lum(rgb[2])

def contrast(rgba):
    r, g, b, a = rgba
    cr = a * r + (1 - a) * BG[0]
    cg = a * g + (1 - a) * BG[1]
    cb = a * b + (1 - a) * BG[2]
    l1, l2 = rel((cr, cg, cb)), rel(BG)
    if l1 < l2:
        l1, l2 = l2, l1
    return (l1 + 0.05) / (l2 + 0.05)

# all targets are small text (<= 0.8125rem normal weight), so the 4.5:1 bar applies
LIMIT = 4.5
targets = [("fg", colors.get("fg")), ("fg_dim", colors.get("fg_dim")),
           ("fg_faint", colors.get("fg_faint")), ("workspace dot", ws_dot)]
fails = 0
for name, val in targets:
    if val is None:
        print(f"    ✗ {name}: token not found in the CSS"); fails += 1; continue
    try:
        rgba = to_rgba(val)
    except ValueError as e:
        print(f"    ✗ {name}: {e}"); fails += 1; continue
    ratio = contrast(rgba)
    if ratio >= LIMIT:
        print(f"    ✓ {name}: {val} -> {ratio:.2f}:1 (>= {LIMIT}:1)")
    else:
        print(f"    ✗ {name}: {val} -> {ratio:.2f}:1 (below {LIMIT}:1)"); fails += 1
sys.exit(1 if fails else 0)
PY
  local rc=$?
  # Appearance overhaul contract rows: 3 surface greys, 1 accent, 1 ink white, 1 secondary grey, radius scale
  local app_css="$CHECK_LAYER/default/waybar/style.css"
  if grep -q '#0c0c10' "$app_css" && grep -q '#14141a' "$app_css" && grep -q '#ececef' "$app_css" && grep -q '#a1a1a6' "$app_css"; then
    ok "appearance palette tokens present in waybar/style.css (#0c0c10, #14141a, #ececef, #a1a1a6)"
  else
    bad "appearance palette tokens missing in waybar/style.css"; rc=1
  fi
  if grep -q '540px' "$CHECK_LAYER/default/rofi/menu.rasi" && ! grep -q '780px' "$CHECK_LAYER/bin/prime-menu"; then
    ok "Prime menu width is stable across root and sub-pages (540px, no 780px jump)"
  else
    bad "Prime menu width jump detected"; rc=1
  fi
  return $rc
}

# ─────────────────────────────────────────────────────────────────────────────
# Contract 3 — text-scale-propagates
# ─────────────────────────────────────────────────────────────────────────────
contract_text_scale() {
  local rc=0 line v

  # capture current values of the seven targets
  echo "    -- current values (the one control is Theme → Text size) --"
  line="$(grep -m1 'prime-font-body:' "$THEME_DIR/fonts.rasi" 2>/dev/null | sed -E 's/^[[:space:]]*//')"; echo "    fonts.rasi prime-font-body = ${line:-<missing>}"
  line="$(grep -m1 '^font_size' "$THEME_DIR/kitty.conf" 2>/dev/null | sed -E 's/^[[:space:]]*//')"; echo "    kitty.conf font_size       = ${line:-<missing>}"
  line="$(grep -m1 'font-size:' "$THEME_DIR/dock.css" 2>/dev/null | sed -E 's/^[[:space:]]*//')"; echo "    dock.css font-size         = ${line:-<missing>}"
  line="$(grep -m1 '^\$prime_titlebar_text' "$THEME_DIR/hyprland.conf" 2>/dev/null | sed -E 's/^[[:space:]]*//')"; echo "    hyprland.conf titlebar     = ${line:-<missing>}"
  line="$(grep -m1 '^\$prime_font_clock' "$THEME_DIR/hyprlock.conf" 2>/dev/null | sed -E 's/^[[:space:]]*//')"; echo "    hyprlock.conf clock font   = ${line:-<missing>}"
  echo "    gsettings font-name        = $(gsettings get org.gnome.desktop.interface font-name 2>/dev/null)"
  line="$(grep -m1 '^gtk-font-name' "$HOME_DIR/.config/gtk-3.0/settings.ini" 2>/dev/null)"; echo "    gtk-3.0/settings.ini        = ${line:-<missing>}"

  # all seven targets must be derived from prime-theme's size() function
  echo "    -- wiring to prime-theme size() (grep the generator) --"
  v="$(grep -nE 'prime-font-body:[[:space:]]*"Inter .*\$\(size ' "$GEN" 2>/dev/null | head -1)"; \
      [ -n "$v" ] && ok "[1/7] fonts.rasi prime-font-body wired → $GEN:${v%%:*}" || { bad "[1/7] fonts.rasi prime-font-body NOT wired to size()"; rc=1; }
  v="$(grep -nE 'font_size[[:space:]]+\$\(size ' "$GEN" 2>/dev/null | head -1)"; \
      [ -n "$v" ] && ok "[2/7] kitty font_size wired → $GEN:${v%%:*}" || { bad "[2/7] kitty font_size NOT wired to size()"; rc=1; }
  v="$(grep -nE 'font-size: .*\$\(size ' "$GEN" 2>/dev/null | head -1)"; \
      [ -n "$v" ] && ok "[3/7] dock.css font-size wired → $GEN:${v%%:*}" || { bad "[3/7] dock.css font-size NOT wired to size()"; rc=1; }
  v="$(grep -nE 'prime_titlebar_text[[:space:]]*=[[:space:]]*\$\((i?size) ' "$GEN" 2>/dev/null | head -1)"; \
      [ -n "$v" ] && ok "[4/7] hyprland.conf \$prime_titlebar_text wired → $GEN:${v%%:*}" || { bad "[4/7] hyprland.conf \$prime_titlebar_text NOT wired to isize()/size()"; rc=1; }
  v="$(grep -nE 'prime_font_clock[[:space:]]*=[[:space:]]*\$\((i?size) ' "$GEN" 2>/dev/null | head -1)"; \
      [ -n "$v" ] && ok "[5/7] hyprlock.conf \$prime_font_clock wired → $GEN:${v%%:*}" || { bad "[5/7] hyprlock.conf \$prime_font_clock NOT wired to isize()/size()"; rc=1; }
  v="$(grep -nE 'font-name .*\$\(size ' "$GEN" 2>/dev/null | head -1)"; \
      [ -n "$v" ] && ok "[6/7] gsettings font-name wired → $GEN:${v%%:*}" || { bad "[6/7] gsettings font-name NOT wired to size()"; rc=1; }
  # GTK3 is not written by prime-theme: the layer is a shipped checkout that the
  # next update overwrites, so the bridge lives in user space — a path unit fires
  # prime-text-sync whenever the generated fonts.rasi changes. Test the mechanism
  # by driving it, not by grepping for a string.
  local keep probe got TS
  TS="$(prime_cmd prime-text-sync)"; TS="${TS:-$HOME_DIR/.local/bin/prime-text-sync}"
  keep="$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")"
  gsettings set org.gnome.desktop.interface font-name 'Inter 12' 2>/dev/null
  "$TS" >/dev/null 2>&1
  got="$(grep -m1 '^gtk-font-name=' "$HOME_DIR/.config/gtk-3.0/settings.ini" 2>/dev/null | cut -d= -f2-)"
  gsettings set org.gnome.desktop.interface font-name "$keep" 2>/dev/null
  "$TS" >/dev/null 2>&1
  if [ "$got" = "Inter 12" ]; then
    ok "gtk-3.0/settings.ini follows the Text size value (probe Inter 12 -> ini Inter 12, restored to $keep)"
  else
    bad "gtk-3.0/settings.ini did NOT follow the Text size value (probe wrote Inter 12, ini says '${got:-<missing>}') — run $TS"
    rc=1
  fi
  if systemctl --user is-enabled prime-text-sync.path >/dev/null 2>&1; then
    ok "prime-text-sync.path enabled (fires on every generated theme change)"
  else
    bad "prime-text-sync.path is not enabled — GTK3 will drift unless the sync is run by hand"
    rc=1
  fi

  # the three rofi themes must resolve var(prime-font-body)
  # (prime-menu, prime-spotlight and prime-rofi load $LAYER/default/rofi/*.rasi;
  # a personal ~/.config/rofi/prime-*.rasi copy is checked too when it exists)
  local t f dump
  for t in spotlight menu bar; do
    for f in "$LAYER/default/rofi/$t.rasi" "$HOME_DIR/.config/rofi/prime-$t.rasi"; do
      [ "$f" = "$LAYER/default/rofi/$t.rasi" ] || [ -f "$f" ] || continue
      dump="$(rofi -theme "$f" -dump-theme 2>/dev/null)"
      if echo "$dump" | grep -q 'prime-font-body:' && echo "$dump" | grep -q 'var(prime-font-body)'; then
        ok "rofi theme ${f/#$HOME_DIR/\~} resolves var(prime-font-body)"
      else
        bad "rofi theme ${f/#$HOME_DIR/\~} does not resolve var(prime-font-body) (dump missing the var reference or its definition)"
        rc=1
      fi
    done
  done
  return $rc
}

# ─────────────────────────────────────────────────────────────────────────────
# Contract 4 — keyboard-reachability
# ─────────────────────────────────────────────────────────────────────────────
contract_keyboard() {
  local rc=0
  local -a BIND_FILES=(
    "$LAYER/default/hypr/bindings.conf"
    "$CHECK_LAYER/default/hypr/bindings.conf"
    "$HOME_DIR/.config/prime/addons.d/my-desktop/hypr.conf"
    "$HOME_DIR/.config/hypr/hyprland.conf"
  )
  local f extra
  for f in "$HOME_DIR"/.config/hypr/*.conf; do [ -f "$f" ] && BIND_FILES+=("$f"); done

  # find_bind <command-regex> — prints "MODS + KEY" of the first matching bind
  find_bind() {
    grep -hE '^[[:space:]]*bind[a-z]*[[:space:]]*=' "${BIND_FILES[@]}" 2>/dev/null \
      | grep -m1 -E "$1" \
      | sed -E 's/^[^=]*=[[:space:]]*//; s/,[[:space:]]*/,/g' \
      | awk -F',' '{ print $1 " + " $2 }'
  }

  local b
  # bar
  b="$(find_bind 'prime-bar --keys')"
  if [ -n "$b" ]; then ok "bar → $b (prime-bar --keys)"; else bad "bar has no keyboard path"; rc=1; fi
  # Prime menu
  b="$(find_bind 'prime-start( |$|--)')"
  if [ -n "$b" ]; then ok "Prime menu → $b (prime-start)"; else bad "Prime menu has no keyboard path"; rc=1; fi
  # typing box
  b="$(find_bind 'prime-spotlight')"
  if [ -n "$b" ]; then ok "typing box → $b (prime-spotlight)"; else bad "typing box has no keyboard path"; rc=1; fi
  # whiteboard — no direct bind; reached through the Start menu (SUPER X)
  b="$(find_bind 'prime-board|whiteboard')"
  if [ -n "$b" ]; then
    ok "whiteboard → $b"
  elif grep -q '"prime.board"' "$HOME_DIR/.config/prime/menu.json" 2>/dev/null; then
    ok "whiteboard → (indirect) SUPER X → Start menu → \"Whiteboard\" (menu.json: prime.board)"
  elif ! [ -e "$HOME_DIR/.config/systemd/user/prime-whiteboard.service" ] && ! prime_cmd prime-board >/dev/null \
       && ! grep -rqs 'prime-board\|whiteboard' "$HOME_DIR/.config/prime/addons.d" "$HOME_DIR/.config/waybar" 2>/dev/null; then
    ok "whiteboard → n/a: not installed here (it ships in a personal add-on, not the layer)"
  else
    bad "whiteboard has no keyboard path"; rc=1
  fi
  # dock / minimised windows
  b="$(find_bind 'togglespecialworkspace|restore-minimised')"
  if [ -n "$b" ]; then ok "dock/minimised windows → $b"; else bad "dock/minimised windows has no keyboard path"; rc=1; fi
  # settings
  b="$(find_bind 'prime-system-settings')"
  if [ -n "$b" ]; then ok "settings → $b (prime-system-settings)"; else bad "settings has no keyboard path"; rc=1; fi
  # desktop context menu (Menu key)
  b="$(find_bind ',[[:space:]]*Menu,.*prime-desktop-menu')"
  if [ -n "$b" ]; then ok "desktop context menu (keyboard) → $b (prime-desktop-menu)"; else bad "desktop context menu has no Menu key path"; rc=1; fi
  # reduce motion (Super+Alt+R) + blur toggle + swaync transition-time 0
  b="$(find_bind 'prime-toggle-animations')"
  if [ -n "$b" ] && grep -q 'decoration:blur:enabled' "$CHECK_LAYER/bin/prime-toggle-animations" && grep -q '"transition-time":[[:space:]]*0' "$CHECK_LAYER/default/swaync/config.json"; then
    ok "reduce motion → $b (prime-toggle-animations + blur + swaync transition-time 0)"
  else
    bad "reduce motion incomplete (bind=$b)"; rc=1
  fi
  # screen reader (Super+Alt+Escape)
  b="$(find_bind 'prime-screen-reader')"
  if [ -n "$b" ] && [ -x "$CHECK_LAYER/bin/prime-screen-reader" ]; then
    ok "screen reader → $b (prime-screen-reader)"
  else
    bad "screen reader bind or script missing"; rc=1
  fi
  # control centre (Super+Ctrl+P)
  b="$(find_bind 'prime-control')"
  if [ -n "$b" ] && [ -x "$CHECK_LAYER/bin/prime-control" ]; then
    ok "control centre → $b (prime-control)"
  else
    bad "control centre bind or script missing"; rc=1
  fi

  # actually press one — the typing box (SUPER space → prime-spotlight)
  # Only press on the live desktop when explicitly allowed or inside the VM.
  echo "    -- pressing the typing box bind --"
  local SPOT="$LAYER/bin/prime-spotlight" pid="" found=0
  if [ "${PRIME_E2E_VM:-0}" != "1" ] && [ "${PRIME_E2E_ALLOW_LIVE:-0}" != "1" ]; then
    ok "live press skipped on active host session (bind verified statically; set PRIME_E2E_VM=1 or PRIME_E2E_ALLOW_LIVE=1 to press)"
  elif hyprctl layers -j >/dev/null 2>&1; then
    hyprctl dispatch "hl.dsp.exec_cmd('$SPOT')" >/dev/null 2>&1
    local i
    for i in $(seq 1 12); do
      sleep 0.4
      pid="$(hyprctl layers -j 2>/dev/null | jq -r '.. | objects | select(.namespace=="prime-spotlight") | .pid' 2>/dev/null | head -1)"
      [ -n "$pid" ] && { found=1; break; }
    done
    if [ "$found" = 1 ]; then
      ok "pressed SUPER space → Spotlight surface appeared (prime-spotlight layer, pid $pid)"
      kill "$pid" 2>/dev/null; sleep 0.5
    else
      bad "pressed SUPER space but the Spotlight surface did not appear"; rc=1
    fi
  else
    echo "    ! no live Hyprland session (hyprctl unreachable) — press step skipped"
  fi
  return $rc
}

# ─────────────────────────────────────────────────────────────────────────────
# Contract 5 — layer-tree-clean
# ─────────────────────────────────────────────────────────────────────────────
contract_layer_clean() {
  local dirty
  dirty="$(git -C "$LAYER/.." status --porcelain 2>&1)"
  if [ -z "$dirty" ]; then
    ok "shipped layer tree is clean (git status --porcelain empty)"
    return 0
  fi
  bad "shipped layer tree is dirty — the next update overwrites these local fixes:"
  echo "$dirty" | sed 's/^/    ✗   /'
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Contract 6 — no-portability-leaks
# ─────────────────────────────────────────────────────────────────────────────
contract_portability() {
  # Scans the TREES THAT GET INSTALLED ELSEWHERE, not this user's own state.
  # ~/.config/prime/menu.json is this machine's data by definition — a path like
  # /home/sean/.config/... in it is correct, not a leak, and prime-menu --check
  # resolves those paths literally, so rewriting them to $HOME breaks the menu.
  # What must never leak is anything shipped: the layer tree and the repo copy.
  local hits
  hits="$(grep -rnH -E '/home/sean/|RX 9060 XT|"card1"' \
        "$LAYER" \
        "$HOME_DIR/Projects/prime-linux/layer" \
        --include='*.json' --include='*.jsonc' --include='*.conf' \
        --include='*.sh' --include='*.py' 2>/dev/null \
        | grep -v '/tests/' | head -20)"
  if [ -z "$hits" ]; then
    ok "shipped layer has no /home/sean/, GPU model or card1 hardcoded (user state exempt by design)"
  else
    bad "portability leaks in shipped files (these would ship to another machine):"
    echo "$hits" | while IFS= read -r l; do echo "    ✗   $l"; done
    return 1
  fi
  # Also verify shipped workstream tools pass their non-interactive self-checks
  local t_rc=0
  if "$CHECK_LAYER/bin/prime-control" --check >/dev/null 2>&1; then
    ok "prime-control --check passes (5 tabs, Quiet/Balanced/Gaming switch, LACT support)"
  else
    bad "prime-control --check failed"; t_rc=1
  fi
  if [ -x "$CHECK_LAYER/bin/prime-gaming-check" ] && bash -n "$CHECK_LAYER/bin/prime-gaming-check" 2>/dev/null; then
    ok "prime-gaming-check is executable and valid bash"
  else
    bad "prime-gaming-check missing or invalid"; t_rc=1
  fi
  if "$CHECK_LAYER/bin/prime-switch" --check >/dev/null 2>&1; then
    ok "prime-switch --check passes (Windows/macOS switching guide & keybind parity table)"
  else
    bad "prime-switch --check failed"; t_rc=1
  fi
  if "$CHECK_LAYER/bin/prime-rea" --check >/dev/null 2>&1; then
    ok "prime-rea --check passes (Reverse engineering menu section & launcher)"
  else
    bad "prime-rea --check failed"; t_rc=1
  fi
  return $t_rc
}

# ─────────────────────────────────────────────────────────────────────────────
# Contract 7 — plugin-version-gate
# ─────────────────────────────────────────────────────────────────────────────
contract_version_gate() {
  local rc=0 saved="" running
  for sp in "${XDG_STATE_HOME:-$HOME_DIR/.local/state}/prime/hyprland-commit" "$HOME_DIR/.hermes/state/hyprland-commit"; do
    [ -s "$sp" ] && { saved="$(tr -d '[:space:]' < "$sp")"; break; }
  done
  running="$(hyprctl version 2>/dev/null | grep -oE 'commit [0-9a-f]+' | awk '{print $2}' | head -1)"
  if [ -n "$running" ]; then
    if [ -n "$saved" ] && [ "$saved" = "$running" ]; then
      ok "hyprland-commit ($saved) matches the running Hyprland ($running)"
    else
      bad "version gate mismatch: saved=$saved running=$running (a Hyprland bump would be missed mid-session)"; rc=1
    fi
  else
    local DOC; DOC="$(prime_cmd prime-hyprpm-doctor)"; DOC="${DOC:-$LAYER/bin/prime-hyprpm-doctor}"
    if [ -x "$DOC" ] && grep -q -- '--if-version-changed' "$DOC"; then
      ok "no live Hyprland session (hyprctl unreachable) — prime-hyprpm-doctor --if-version-changed present ($DOC)"
    else
      bad "prime-hyprpm-doctor missing or lacks --if-version-changed"; rc=1
    fi
  fi
  local en act
  en="$(systemctl --user is-enabled prime-hyprpm-watch.timer 2>/dev/null)"
  act="$(systemctl --user is-active prime-hyprpm-watch.timer 2>/dev/null)"
  if [ "$en" = "enabled" ] && [ "$act" = "active" ]; then
    ok "prime-hyprpm-watch.timer is enabled and active"
  else
    bad "prime-hyprpm-watch.timer not enabled+active (enabled=$en active=$act)"; rc=1
  fi
  return $rc
}

# ─────────────────────────────────────────────────────────────────────────────
main() {
  echo "Prime Linux contract suite — $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Results: $RESULTS"
  echo

  local rc=0 c=0
  echo "[1] notifications-carry-actions"
  contract_notifications; c=$?; [ $c -ne 0 ] && rc=1; record "notifications-carry-actions" "$([ $c -eq 0 ] && echo PASS || echo FAIL)"
  echo
  echo "[2] contrast-budget"
  contract_contrast; c=$?; [ $c -ne 0 ] && rc=1; record "contrast-budget" "$([ $c -eq 0 ] && echo PASS || echo FAIL)"
  echo
  echo "[3] text-scale-propagates"
  contract_text_scale; c=$?; [ $c -ne 0 ] && rc=1; record "text-scale-propagates" "$([ $c -eq 0 ] && echo PASS || echo FAIL)"
  echo
  echo "[4] keyboard-reachability"
  contract_keyboard; c=$?; [ $c -ne 0 ] && rc=1; record "keyboard-reachability" "$([ $c -eq 0 ] && echo PASS || echo FAIL)"
  echo
  echo "[5] layer-tree-clean"
  contract_layer_clean; c=$?; [ $c -ne 0 ] && rc=1; record "layer-tree-clean" "$([ $c -eq 0 ] && echo PASS || echo FAIL)"
  echo
  echo "[6] no-portability-leaks"
  contract_portability; c=$?; [ $c -ne 0 ] && rc=1; record "no-portability-leaks" "$([ $c -eq 0 ] && echo PASS || echo FAIL)"
  echo
  echo "[7] plugin-version-gate"
  contract_version_gate; c=$?; [ $c -ne 0 ] && rc=1; record "plugin-version-gate" "$([ $c -eq 0 ] && echo PASS || echo FAIL)"

  echo
  echo "════════════════════════════════════════════════════════════"
  echo "SUMMARY"
  echo "════════════════════════════════════════════════════════════"
  local i
  for i in "${!T_NAMES[@]}"; do
    printf "  %-28s %s\n" "${T_NAMES[$i]}" "${T_STATUS[$i]}"
  done
  local p f
  p=$(printf '%s\n' "${T_STATUS[@]}" | grep -c PASS)
  f=$(printf '%s\n' "${T_STATUS[@]}" | grep -c FAIL)
  echo "────────────────────────────────────────────────────────────"
  echo "  PASS: $p   FAIL: $f"
  echo
  [ "$rc" -eq 0 ] && echo "ALL CONTRACTS PASS" || echo "CONTRACT FAILURES DETECTED (exit $rc)"
  return $rc
}

main "$@"
exit $?