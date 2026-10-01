#!/usr/bin/env bash
# tests/check-menus.sh — the Prime menu and the right-click menus, driven through a
# stand-in rofi that records what it was given and answers like rofi does. No
# display, no install: everything runs in a throwaway HOME.
#
# Holds: labels with & < > reach rofi escaped (they rendered as "DDD"), our own
# <span> markup survives, the choice comes back by index (-format i), the update
# count is said with the right plural, and the start menu self-tests.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; L="$REPO/layer"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { rm -f "$T/rofi.answered"; if eval "$2" >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -6; fail=$((fail+1)); fi; }
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run" PRIME_NO_GSETTINGS=1
mkdir -p "$HOME/.config/prime" "$T/run" "$T/bin"; chmod 700 "$T/run"
unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE

# the stand-in: saves its arguments and rows; the first time it is asked it answers
# with ROFI_PICK (a row index), after that it cancels like Esc (so Back can't loop)
cat > "$T/bin/rofi" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ROFI_LOG.args"
cat > "$ROFI_LOG.rows"
[ -n "${ROFI_PICK:-}" ] && [ ! -e "$ROFI_LOG.answered" ] || exit 1
: > "$ROFI_LOG.answered"
echo "$ROFI_PICK"
EOF
chmod +x "$T/bin/rofi"
export PATH="$T/bin:$PATH" ROFI_LOG="$T/rofi"

cat > "$T/menu.json" <<'EOF'
{ "sections": [
  { "id": "style", "label": "Style & repair", "icon": "󰸉",
    "items": [ { "id": "s.one", "label": "Fix <this> & that", "hint": "R&D", "kind": "run", "cmd": "echo one" },
               { "id": "s.two", "label": "Second", "kind": "run", "cmd": "echo two" } ] },
  { "id": "solo", "label": "Solo", "icon": "",
    "items": [ { "id": "solo.a", "label": "Only", "kind": "run", "cmd": "echo a" } ] } ] }
EOF
echo '{"text":"1"}' > "$T/run/waybar-updates.json"
export PRIME_MENU="$T/menu.json" PRIME_MENU_DRY=1

echo "== Prime menu"
ck "root rows escape & and keep our markup" \
   "ROFI_PICK= bash $L/bin/prime-menu; grep -q 'Style &amp; repair' $T/rofi.rows && ! grep -q 'Style & repair' $T/rofi.rows && grep -q '<span' $T/rofi.rows"
ck "icons sit in a fixed-width column with a gap" \
   "grep -q 'font_family=\"JetBrainsMono Nerd Font Mono\"' $T/rofi.rows && grep -q '</span>   Style' $T/rofi.rows"
ck "one thing / one update: singular" \
   "grep -q '1 thing<' $T/rofi.rows && grep -A1 -- '-mesg' $T/rofi.args | grep -qx '1 update waiting' && ! grep -q '1 updates' $T/rofi.args"
ck "the prompt is a plain breadcrumb, not a glyph" \
   "grep -A1 -- '^-p$' $T/rofi.args | tail -1 | grep -qx 'Prime'"
ck "rofi answers with an index (-format i)"      "grep -qx -- '-format' $T/rofi.args && grep -A1 -- '^-format$' $T/rofi.args | tail -1 | grep -qx i"
ck "section rows escape label and hint"         "ROFI_PICK= bash $L/bin/prime-menu --section style; grep -q 'Fix &lt;this&gt; &amp; that' $T/rofi.rows && grep -q 'R&amp;D' $T/rofi.rows"
ck "picking row 1 runs that row, escaped label or not" \
   "ROFI_PICK=1 bash $L/bin/prime-menu --section style | grep -qx 'RUN: echo one'"
ck "picking ‹ Back (row 0) goes back to the sections" \
   "ROFI_PICK=0 timeout 5 bash $L/bin/prime-menu --section style; [ \$? = 0 ] && grep -q 'Style &amp; repair' $T/rofi.rows"
ck "--list keeps its shape (id, icon + label)"  "bash $L/bin/prime-menu --list | grep -qP '^style\t󰸉 Style & repair$'"

echo "== Right-click menus"
cat > "$T/elements.json" <<'EOF'
{ "generic_items": [], "utility_items": [ { "id": "copy", "label": "Copy this value", "kind": "copy" } ],
  "fallback": { "label": "This item", "state": "" },
  "elements": { "bar.test": { "label": "Q&A <beta>", "state": "echo 'a & b'",
    "items": [ { "label": "Open R&D", "cmd": "true" } ] } } }
EOF
export PRIME_ELEMENTS="$T/elements.json"
ck "rows and the live value are escaped; separators stay markup" \
   "ROFI_PICK= bash $L/bin/prime-context bar.test; grep -q 'Open R&amp;D' $T/rofi.rows && grep -q '<span alpha' $T/rofi.rows && grep -A1 -- '-mesg' $T/rofi.args | grep -q 'Q&amp;A &lt;beta&gt; — a &amp; b'"
ck "right-click answers by index too"           "grep -A1 -- '^-format$' $T/rofi.args | tail -1 | grep -qx i"

echo "== Start menu"
PY=python3
for p in python3 /usr/bin/python3 /usr/bin/python3.14 /usr/bin/python3.13 /usr/bin/python3.12; do
    command -v "$p" >/dev/null && "$p" -c 'import gi; gi.require_version("Gtk", "3.0")' 2>/dev/null && { PY="$p"; break; }
done
GUI=""; [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && command -v xvfb-run >/dev/null && GUI="xvfb-run -a"
ck "prime-start self-test (pins, search, recents, window)" "$GUI $PY $L/bin/prime-start --selftest"
ck "the logo opens it, the right-click menu stays"  "grep -A8 '\"image#logo\"' $L/default/waybar/config.jsonc | grep -q 'on-click\": \"[^\"]*prime-start\"' && grep -A8 '\"image#logo\"' $L/default/waybar/config.jsonc | grep -q 'prime-context bar.logo'"
ck "it has a described shortcut (listed by Super+/)" "grep -qE '^bindd = SUPER, X, Start menu.*prime-start' $L/default/hypr/bindings.conf"
ck "Spotlight and Start are blurred like rofi"      "grep -qx 'layerrule = blur prime-spotlight' $L/default/hypr/looknfeel.conf && grep -qx 'layerrule = blur prime-start' $L/default/hypr/looknfeel.conf"

echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
