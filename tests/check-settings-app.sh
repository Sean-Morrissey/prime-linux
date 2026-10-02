#!/usr/bin/env bash
# tests/check-settings-app.sh — Settings (prime-system-settings): every page builds,
# every Prime tool it opens exists, the mouse/keyboard/touchpad settings land in the
# Prime block of hyprland.conf (and bad values are refused), the password change
# never puts a password on a command line, and the menus lead to it. Throwaway HOME.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; fail=0
APP="$REPO/layer/bin/prime-system-settings"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

# ── what it opens exists ────────────────────────────────────────────────────
missing=""
for c in $(grep -oE '"prime-[a-z-]+"' "$APP" | tr -d '"' | sort -u); do
    case "$c" in prime-gaming|prime-ai-setup) continue ;; esac   # pack tools, checked below
    [ -x "$REPO/layer/bin/$c" ] || missing="$missing $c"
done
ck "every Prime tool Settings opens is in layer/bin${missing:+ (missing:$missing)}" "[ -z '$missing' ]"
ck "the pack tools it uses are in their packs" \
   "[ -x '$REPO/layer/addons/gaming/bin/prime-gaming' ] && [ -x '$REPO/layer/addons/ai/bin/prime-ai-setup' ]"
ck "lists 22 pages, each with search words" \
   "[ \$(python3 '$APP' --list-pages | awk -F'\t' 'NF==3 && \$3!=\"\"' | wc -l) -ge 22 ]"
ck "an unknown page is refused, not opened blank" "! python3 '$APP' --page nope"
ck "mouse, keyboard, processor, graphics, storage, gaming and AI pages exist" \
   "for p in mouse keyboard processor graphics storage gaming assistant display sound network; do python3 '$APP' --list-pages | grep -q \"^\$p	\" || exit 1; done"

# ── the settings toolbox behind the Mouse & Keyboard pages ─────────────────
H="$T/home"; mkdir -p "$H/.config/hypr"; : > "$H/.config/hypr/hyprland.conf"
run() { HOME="$H" "$REPO/layer/bin/prime-settings" run change_setting "{\"setting\":\"$1\",\"value\":$2}"; }
run mouse_speed '"-0.3"' >/dev/null
run left_handed '"on"' >/dev/null
run tap_to_click '"off"' >/dev/null
run key_repeat_rate 40 >/dev/null
run key_repeat_delay 300 >/dev/null
C="$H/.config/hypr/hyprland.conf"
ck "pointer speed lands in the Prime block"   "grep -q 'sensitivity = -0.30' '$C'"
ck "left-handed lands in the Prime block"     "grep -q 'left_handed = true' '$C'"
ck "tap to click off lands in the touchpad block" "grep -q 'tap-to-click = false' '$C'"
ck "key repeat rate and delay land"           "grep -q 'repeat_rate = 40' '$C' && grep -q 'repeat_delay = 300' '$C'"
ck "a pointer speed outside -1…1 is refused"  "run mouse_speed '\"5\"' | grep -q '\"ok\": *false'"
ck "a repeat rate of 500 is refused"          "run key_repeat_rate 500 | grep -q '\"ok\": *false'"

# ── window layout: Free (float, the default) or Tidy (tiled), switched and undone ─
TH="$H/.config/prime/theme/hyprland.conf"
HOME="$H" PRIME_NO_LIVE=1 PRIME_NO_GSETTINGS=1 bash "$REPO/layer/bin/prime-theme" --apply >/dev/null 2>&1
ck "new windows float by default (like a Mac or Windows)" "grep -q '^windowrule = float on, match:class \.\*' '$TH'"
run window_layout '"tidy"' >/dev/null
ck "Tidy: the float rule is gone, so Hyprland tiles"      "! grep -q 'float on, match:class \.\*' '$TH'"
HOME="$H" "$REPO/layer/bin/prime-settings" undo >/dev/null
ck "undo brings Free back"                               "grep -q 'float on, match:class \.\*' '$TH'"
ck "a layout that isn't free or tidy is refused"         "run window_layout '\"sideways\"' | grep -q '\"ok\": *false'"
ck "windows are solid (no see-through unfocused windows)" "grep -q 'inactive_opacity = 1.0' '$REPO/layer/default/hypr/looknfeel.conf'"
ck "games: tearing allowed and adaptive sync on"         "grep -q 'allow_tearing = true' '$REPO/layer/default/hypr/looknfeel.conf' && grep -q 'vrr = 2' '$REPO/layer/default/hypr/looknfeel.conf'"

# ── password change: never on a command line, plain answers ───────────────
cat > "$T/fakepasswd" <<'EOF'
#!/usr/bin/env bash
read -r old; read -r new; read -r again
printf '%s\n' "$*" > "$(dirname "$0")/argv"
[ "$old" = right ] || { echo "passwd: Authentication token manipulation error" >&2; exit 10; }
[ "$new" = "$again" ] && exit 0
EOF
chmod +x "$T/fakepasswd"
pw() { printf '%s\n%s\n%s\n' "$1" "$2" "$3" | PRIME_PASSWD_CMD="$T/fakepasswd" "$REPO/layer/bin/prime-passwd"; }
ck "the right current password changes it"   "pw right newpass1 newpass1 | grep -q 'Password changed'"
ck "no password reaches passwd's command line" "[ -z \"\$(tr -d '\n' < '$T/argv')\" ]"
ck "a wrong current password says so"        "pw wrong newpass1 newpass1 | grep -q \"wasn't right\""
ck "two different new ones are caught first" "pw right newpass1 newpass2 | grep -q \"aren't the same\""
ck "a too-short new one is caught first"     "pw right abc abc | grep -q 'at least 6'"
ck "the app hands passwords over stdin only" "grep -q 'input=text' '$APP' && ! grep -q 'prime-passwd\", *row' '$APP'"

# ── the way in ─────────────────────────────────────────────────────────────
ck "Super+I opens Settings"                  "grep -q 'SUPER, I, Settings.*prime-system-settings' '$REPO/layer/default/hypr/bindings.conf'"
ck "Prime menu → Settings starts with All settings" \
   "jq -e '.sections[] | select(.id==\"settings\") | .items[0].cmd | test(\"prime-system-settings\")' '$REPO/layer/default/menu.json'"
ck "Start menu's Settings button opens it"   "grep -q '\"Settings\", \[os.path.join(BIN, \"prime-system-settings\")\]' '$REPO/layer/bin/prime-start'"
ck "it's in the app list as Settings"        "grep -q '^Name=Settings$' '$REPO/layer/applications/prime-settings.desktop' && grep -q 'prime-system-settings' '$REPO/layer/applications/prime-settings.desktop'"

# ── every page builds (needs GTK 4 + libadwaita and a display) ─────────────
PY="${PRIME_TEST_PY:-python3}"
if "$PY" -c "import gi; gi.require_version('Gtk','4.0'); gi.require_version('Adw','1')" 2>/dev/null && command -v xvfb-run >/dev/null; then
    HOME="$H" PRIME_SETTINGS_DRY=1 timeout 120 xvfb-run -a "$PY" "$APP" --selftest > "$T/st" 2>&1
    ck "all 22 pages build, search finds Mouse & Touchpad" "grep -q '^0 failure' '$T/st' && [ \$(grep -c '  PASS  ' '$T/st') -ge 23 ]"
    grep -q '^0 failure' "$T/st" || grep -E 'FAIL|Error|Traceback' "$T/st" | head -20
else
    echo "  SKIP  page build (no GTK 4 / libadwaita / Xvfb here)"
fi
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
