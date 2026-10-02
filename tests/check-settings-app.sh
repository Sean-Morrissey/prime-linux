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

# ── window layout: Tidy (snap into place, the default) or Free (float), switched and undone ─
TH="$H/.config/prime/theme/hyprland.conf"
HOME="$H" PRIME_NO_LIVE=1 PRIME_NO_GSETTINGS=1 bash "$REPO/layer/bin/prime-theme" --apply >/dev/null 2>&1
ck "by default windows snap into place (nothing forced to float)" "! grep -q 'float on, match:class \.\*' '$TH'"
run window_layout '"free"' >/dev/null
ck "Free: windows float, open at a sensible size, in the middle" "grep -q '^windowrule = float on, match:class \.\*' '$TH' && grep -q '^windowrule = size 62% 70%' '$TH'"
HOME="$H" "$REPO/layer/bin/prime-settings" undo >/dev/null
ck "undo brings Tidy back"                               "! grep -q 'float on, match:class \.\*' '$TH'"
ck "a layout that isn't free or tidy is refused"         "run window_layout '\"sideways\"' | grep -q '\"ok\": *false'"
ck "windows are solid (no see-through unfocused windows)" "grep -q 'inactive_opacity = 1.0' '$REPO/layer/default/hypr/looknfeel.conf'"
ck "games: tearing allowed and adaptive sync on"         "grep -q 'allow_tearing = true' '$REPO/layer/default/hypr/looknfeel.conf' && grep -q 'vrr = 2' '$REPO/layer/default/hypr/looknfeel.conf'"

# ── Graphics and Processor read real numbers (a made-up AMD card and Ryzen in /sys) ─
F="$T/fakesys"; D="$F/sys/class/drm/card1/device"
mkdir -p "$D/hwmon/hwmon3" "$F/amdgpu" "$F/sys/class/hwmon/hwmon2"
ln -sfn "$F/amdgpu" "$D/driver"
echo 17163091968 > "$D/mem_info_vram_total"; echo 2147483648 > "$D/mem_info_vram_used"; echo 37 > "$D/gpu_busy_percent"
echo 54000 > "$D/hwmon/hwmon3/temp1_input"; echo 142000000 > "$D/hwmon/hwmon3/power1_average"
printf '0: 500Mhz\n1: 2620Mhz *\n' > "$D/pp_dpm_sclk"
for c in 0 1; do mkdir -p "$F/sys/devices/system/cpu/cpu$c/cpufreq"; echo 4950000 > "$F/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq"; done
echo 5000000 > "$F/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"; echo amd-pstate-epp > "$F/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver"
echo k10temp > "$F/sys/class/hwmon/hwmon2/name"; echo 61000 > "$F/sys/class/hwmon/hwmon2/temp1_input"
HW="$(PRIME_SYS_ROOT="$F" python3 "$APP" --hardware)"
ck "graphics card: driver, how busy, video memory, speed, temperature, power" \
   "echo '$HW' | grep -q 'gpu card1 · amdgpu · busy 37% · vram 2.1 GB/17 GB · clock 2620 MHz · temp 54 °C · power 142 W'"
ck "processor: speed now and at most, how it's tuned, temperature" "echo '$HW' | grep -q 'cpu 4.95 GHz (max 5.0) · amd-pstate-epp' && echo '$HW' | grep -q '61 °C'"

# ── screens: modes best first, rules written for one screen without touching others ─
ck "screen modes: highest resolution, then highest refresh, first; duplicates gone" "python3 - '$APP' <<'PY'
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader('s', sys.argv[1]); sp = importlib.util.spec_from_loader('s', l)
m = importlib.util.module_from_spec(sp); l.exec_module(m)
mon = {'availableModes': ['1920x1080@60.00Hz', '2560x1440@59.95Hz', '2560x1440@165.00Hz', '2560x1440@164.96Hz', '1920x1080@144.00Hz']}
got = [v for _l, v in m.modes_of(mon)]
assert got == ['2560x1440@165.00', '2560x1440@59.95', '1920x1080@144.00', '1920x1080@60.00'], got
assert m.monitor_line('DP-1', '2560x1440@165.00', 0, 0, 1.25) == 'DP-1, 2560x1440@165.00, 0x0, 1.25'
assert m.monitor_line('DP-1', '2560x1440@165.00', 0, 0, 1.0, 2) == 'DP-1, 2560x1440@165.00, 0x0, 1, vrr, 2'
PY"
MC="$T/monitors.conf"; printf '# Screens\nmonitor = HDMI-A-1, 1920x1080@60, 2560x0, 1\nmonitor = DP-1, preferred, 0x0, 1\n' > "$MC"
python3 - "$APP" "$MC" <<'PY'
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader('s', sys.argv[1]); sp = importlib.util.spec_from_loader('s', l)
m = importlib.util.module_from_spec(sp); l.exec_module(m)
m.save_monitor('DP-1', 'DP-1, 2560x1440@165.00, 0x0, 1', sys.argv[2])
m.save_monitor('DP-2', 'DP-2, 1920x1080@60.00, 5120x0, 1', sys.argv[2])
PY
ck "saving one screen replaces only its own line" "grep -qx 'monitor = DP-1, 2560x1440@165.00, 0x0, 1' '$MC' && grep -qx 'monitor = HDMI-A-1, 1920x1080@60, 2560x0, 1' '$MC' && [ \$(grep -c 'DP-1' '$MC') = 1 ]"
ck "a new screen is added, the comment kept"     "grep -qx 'monitor = DP-2, 1920x1080@60.00, 5120x0, 1' '$MC' && head -1 '$MC' | grep -q '^# Screens'"

# ── sound devices from PipeWire (a stand-in wpctl) ─────────────────────────────
W="$T/wbin"; mkdir -p "$W"
cat > "$W/wpctl" <<'EOF'
#!/bin/sh
[ "$1" = status ] || exit 0
cat <<'S'
Audio
 ├─ Devices:
 │      42. Navi 48 HDMI/DP Audio Controller    [alsa]
 ├─ Sinks:
 │      55. Navi 48 HDMI/DP Audio Controller Digital Stereo (HDMI) [vol: 0.70]
 │  *   57. Starship/Matisse HD Audio Controller Analog Stereo [vol: 0.40]
 ├─ Sources:
 │  *   58. Starship/Matisse HD Audio Controller Analog Stereo [vol: 1.00]
 ├─ Filters:
 └─ Streams:
Video
 ├─ Sinks:
 │      90. Not audio
S
EOF
chmod +x "$W/wpctl"
ck "speakers listed, the default one known (and video devices ignored)" "PATH='$W':\$PATH python3 - '$APP' <<'PY'
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader('s', sys.argv[1]); sp = importlib.util.spec_from_loader('s', l)
m = importlib.util.module_from_spec(sp); l.exec_module(m)
outs, d = m.audio_devices('Sinks')
assert [i for i, _ in outs] == ['55', '57'] and d == '57', (outs, d)
ins, di = m.audio_devices('Sources')
assert ins == [('58', 'Starship/Matisse HD Audio Controller Analog Stereo')] and di == '58', ins
PY"
ck "FreeSync and game tearing are undoable settings" \
   "run vrr '\"always\"' | grep -q '\"ok\": true' && grep -q 'vrr = 1' '$H/.config/hypr/hyprland.conf' && run game_tearing '\"off\"' | grep -q '\"ok\": true' && grep -q 'allow_tearing = false' '$H/.config/hypr/hyprland.conf'"
ck "a FreeSync value that isn't off/fullscreen/always is refused" "run vrr '\"sometimes\"' | grep -q '\"ok\": *false'"

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
