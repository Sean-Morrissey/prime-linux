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

# ── dock, top bar, windows & workspaces, lock & sleep ─────────────────────
ck "workspaces: five on the bar, a click opens it on this screen, no scroll-switching" \
   "grep -q '\"persistent-workspaces\": {\"\\*\": 5}' '$REPO/layer/default/waybar/config.jsonc' && grep -q '\"move-to-monitor\": true' '$REPO/layer/default/waybar/config.jsonc' && ! grep -q 'workspace e[-+]1' '$REPO/layer/default/waybar/config.jsonc' && [ \$(grep -c 'persistent:true' '$REPO/layer/default/hypr/windows.conf') = 5 ]"
ck "apps stay on the workspace they opened on and never pull you away" \
   "grep -q 'focus_on_activate = false' '$REPO/layer/default/hypr/looknfeel.conf' && grep -q 'initial_workspace_tracking = 2' '$REPO/layer/default/hypr/looknfeel.conf'"
ck "Super+number opens the workspace on the screen you're on" "grep -q 'SUPER, 3, Go to workspace 3, focusworkspaceoncurrentmonitor, 3' '$REPO/layer/default/hypr/bindings.conf'"
run workspaces 7 >/dev/null; run workspace_guard '"off"' >/dev/null; run new_windows '"main"' >/dev/null; run snap_keys '"focus"' >/dev/null
ck "how many workspaces, and the guard, land in the Prime block" \
   "grep -q 'workspace = 7, persistent:true' '$C' && grep -q 'workspace = 8, persistent:false' '$C' && grep -q 'focus_on_activate = true' '$C'"
ck "new windows as the main one; Super+arrows can move focus instead" \
   "grep -q 'new_status = master' '$C' && grep -q 'bindd = SUPER, left, Focus the window to the left, movefocus, l' '$C' && grep -q 'bindd = SUPER SHIFT, left, Snap window to the left half, exec, \$bin/prime-snap l' '$C'"
ck "a wrong answer is refused (dock position, workspaces, minutes)" \
   "run dock_position '\"top\"' | grep -q '\"ok\": *false' && run workspaces 0 | grep -q '\"ok\": *false' && run lock_after '\"soon\"' | grep -q '\"ok\": *false'"
run dock_size '"large"' >/dev/null; run dock_mode '"always"' >/dev/null; run dock_position '"left"' >/dev/null
ck "the dock follows its settings (size, always shown, left edge)" \
   "HOME='$H' bash '$REPO/layer/bin/prime-dock' --args | tr '\\n' ' ' | grep -q -- '-x -p left -i 56 -ml 8'"
run clock_format '"24h"' >/dev/null; run clock_seconds '"on"' >/dev/null; run bar_hidden '"tray,media"' >/dev/null
ck "the top bar follows its settings (24-hour clock with seconds, items hidden, 7 workspaces)" "HOME='$H' python3 - '$REPO/layer/bin/prime-bar' <<'PY'
import importlib.machinery as M, importlib.util as U, sys
l = M.SourceFileLoader('pb', sys.argv[1]); m = U.module_from_spec(U.spec_from_loader('pb', l)); l.exec_module(m)
cfg, _, _ = m.build('top')
assert cfg['clock']['format'] == '{:%a %b %e   %H:%M:%S}', cfg['clock']['format']
mods = cfg['modules-left'] + cfg['modules-right']
assert 'tray' not in mods and 'custom/media' not in mods and 'custom/updates' in mods, mods
assert cfg['hyprland/workspaces']['persistent-workspaces'] == {'*': 7}
PY"
run bar_hidden '"nope"' > "$T/bh"
ck "an unknown bar item is refused"           "grep -q '\"ok\": *false' '$T/bh'"
run lock_after 5 >/dev/null; run sleep_after 30 >/dev/null; run screen_off_after '"never"' >/dev/null
ck "lock & sleep timers become the idle timer (lock 5, sleep 30, screens never off)" \
   "grep -q 'timeout = 300\$' '$H/.config/prime/hypridle.conf' && grep -q 'lock-session' '$H/.config/prime/hypridle.conf' && grep -q 'timeout = 1800' '$H/.config/prime/hypridle.conf' && grep -q 'systemctl suspend' '$H/.config/prime/hypridle.conf' && ! grep -q 'dpms off' '$H/.config/prime/hypridle.conf'"
ck "login starts the idle timer from those settings" "grep -qx 'exec-once = \$bin/prime-idle' '$REPO/layer/default/hypr/autostart.conf'"
ck "undo brings the last timer back"          "HOME='$H' '$REPO/layer/bin/prime-settings' run undo_last '{}' | grep -q '\"ok\": true' && grep -q 'dpms off' '$H/.config/prime/hypridle.conf'"
ck "Settings' window styles are the ones the toolbox knows" "python3 - '$APP' '$REPO/layer/bin/prime-settings' <<'PY'
import importlib.machinery as M, importlib.util as U, sys
def load(n, p):
    l = M.SourceFileLoader(n, p); m = U.module_from_spec(U.spec_from_loader(n, l)); l.exec_module(m); return m
a, b = load('a', sys.argv[1]), load('b', sys.argv[2])
assert a.LOOK_VALUES == b.LOOKS and [v for _, v in a.LOOKS] == list(b.LOOKS), (a.LOOK_VALUES, b.LOOKS)
PY"

# ── Wi-Fi & Network, Sound and Printers: Prime's own pages (fake nmcli, pactl, CUPS) ──
FK="$T/fakes"; mkdir -p "$FK"
cat > "$FK/nmcli" <<'FAKE'
#!/bin/sh
case "$*" in
  *"NAME,TYPE,ACTIVE connection show"*) printf 'Home Wi-Fi:802-11-wireless:yes\nCafe\\:Guest:802-11-wireless:no\nSchool VPN:vpn:no\nwg0:wireguard:yes\nWired 1:802-3-ethernet:no\n' ;;
  *"radio"*) echo enabled ;;
  *"--active"*) echo "Home Wi-Fi:802-11-wireless:wlan0" ;;
  *"show-password"*) printf 'SSID: Prime-desk\nPassword: s3cret99\n' ;;
esac
FAKE
cat > "$FK/pactl" <<'FAKE'
#!/bin/sh
case "$*" in
  *"list cards"*) echo '[{"name":"alsa_card.pci-0000_03_00.1","properties":{"device.description":"Navi 48 HDMI Audio"},"active_profile":"output:hdmi-stereo","profiles":{"off":{"description":"Off","available":true},"output:hdmi-stereo":{"description":"Digital Stereo (HDMI)","available":true},"output:hdmi-surround":{"description":"Digital Surround 5.1 (HDMI)","available":false}}},{"name":"one_profile","properties":{"device.description":"Webcam mic"},"active_profile":"a","profiles":{"a":{"description":"A","available":true}}}]' ;;
  *"list sinks"*) echo '[{"index":55,"name":"alsa_output.hdmi","description":"Screen speakers"},{"index":57,"name":"alsa_output.analog","description":"Headphones"}]' ;;
  *"list sink-inputs"*) echo '[{"index":9,"sink":57,"properties":{"application.name":"Firefox"},"volume":{"front-left":{"value_percent":"80%"}}}]' ;;
esac
FAKE
cat > "$FK/lpstat" <<'FAKE'
#!/bin/sh
case "$1" in
  -p) printf 'printer Office_Laser is idle.  enabled since Fri\nprinter Old_Inkjet disabled since Thu -\n' ;;
  -d) echo "system default destination: Office_Laser" ;;
  -o) echo "Office_Laser-42   sam   1024   Fri 02 Oct 2026" ;;
esac
FAKE
printf '#!/bin/sh\necho "ipp://Brother%%20HL-L2350._ipp._tcp.local/"\necho "ipps://Office_Laser.local:631/ipp/print"\necho "nonsense"\n' > "$FK/driverless"
for c in wpctl bluetoothctl; do printf '#!/bin/sh\nexit 0\n' > "$FK/$c"; done
chmod +x "$FK"/*
# load the Settings module and run a snippet against it: mod '<python>'
mod() { python3 -c "import importlib.machinery as M, importlib.util as U, sys
l = M.SourceFileLoader('s', '$APP'); m = U.module_from_spec(U.spec_from_loader('s', l)); l.exec_module(m)
$1"; }
ck "network: saved Wi-Fi, VPNs (WireGuard too) and wired read right, a ':' in a name kept" \
   "PATH='$FK':\$PATH mod \"c = m.nm_connections()
assert ('Home Wi-Fi', 'wifi', True) in c and ('Cafe:Guest', 'wifi', False) in c, c
assert ('School VPN', 'vpn', False) in c and ('wg0', 'vpn', True) in c and ('Wired 1', 'wired', False) in c, c\""
mkdir -p "$T/vpn"; printf 'client\nremote vpn.school.edu 1194\n' > "$T/vpn/school.ovpn"
printf '[Interface]\nPrivateKey = abc\n[Peer]\n' > "$T/vpn/wg.conf"; printf 'client\nremote x 1\n' > "$T/vpn/ovpn.conf"; echo hello > "$T/vpn/notes.conf"
ck "a VPN file is recognised by what's in it (OpenVPN, WireGuard); anything else is refused" \
   "mod \"assert [m.vpn_file_type('$T/vpn/' + f) for f in ('school.ovpn', 'wg.conf', 'ovpn.conf', 'notes.conf')] == ['openvpn', 'wireguard', 'openvpn', '']\""
ck "sound: device modes (only ones that work; a one-mode device left out), where each app plays" \
   "PATH='$FK':\$PATH mod \"cards = m.sound_cards()
assert len(cards) == 1 and cards[0][1] == 'Navi 48 HDMI Audio' and cards[0][2] == 'output:hdmi-stereo', cards
assert [p for p, _ in cards[0][3]] == ['off', 'output:hdmi-stereo'], cards
assert m.sink_names()[57] == ('alsa_output.analog', 'Headphones') and m.stream_sinks() == {9: 57}\""
ck "printers: yours, the default, what's printing, and new ones nearby (not ones already added)" \
   "PATH='$FK':\$PATH mod \"assert m.printers() == ([('Office_Laser', True), ('Old_Inkjet', False)], 'Office_Laser'), m.printers()
assert m.print_jobs() == [('Office_Laser-42', 'Office_Laser')]
assert m.printers_nearby() == [('Brother_HL-L2350', 'ipp://Brother%20HL-L2350._ipp._tcp.local/')], m.printers_nearby()\""
ck "a hidden network's password goes in on stdin, never on the command line (and isn't printed)" \
   "out=\$(PRIME_SETTINGS_DRY=1 mod \"m.act('nmcli', '--ask', 'device', 'wifi', 'connect', 'Lab', 'hidden', 'yes', stdin='hunter22\\\\n')\") && grep -q 'ACT nmcli --ask device wifi connect Lab hidden yes (+1 line(s) on stdin)' <<<\"\$out\" && ! grep -q hunter22 <<<\"\$out\""
ck "adding a printer checks its name and address first (nothing odd gets through)" \
   "PRIME_PRINTER_DRY=1 bash '$REPO/layer/bin/prime-printer' add Brother_HL ipp://brother.local/ipp/print | grep -q 'RUN lpadmin -p Brother_HL -E -v ipp://brother.local/ipp/print -m everywhere' && ! PRIME_PRINTER_DRY=1 bash '$REPO/layer/bin/prime-printer' add 'x;rm' ipp://a/ && ! PRIME_PRINTER_DRY=1 bash '$REPO/layer/bin/prime-printer' add ok 'file:///etc/shadow' && ! PRIME_PRINTER_DRY=1 bash '$REPO/layer/bin/prime-printer' remove '../x'"
ck "the everyday jobs are on Prime's own pages (the system's tools are only a last row)" \
   "grep -q 'Join a hidden network' '$APP' && grep -q 'Add a VPN from a file' '$APP' && grep -q 'Look for printers' '$APP' && grep -q 'plays through' '$APP'"

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
    # again with fake network, sound and printing tools, so the new rows are really built
    HOME="$H" PATH="$FK:$PATH" PRIME_SETTINGS_DRY=1 timeout 120 xvfb-run -a "$PY" "$APP" --selftest > "$T/st2" 2>&1
    ck "every page builds with Wi-Fi, VPNs, sound devices and printers present" "grep -q '^0 failure' '$T/st2'"
    grep -q '^0 failure' "$T/st2" || grep -E 'FAIL|Error|Traceback' "$T/st2" | head -20
    ck "all 29 pages build, search finds Mouse & Touchpad" "grep -q '^0 failure' '$T/st' && [ \$(grep -c '  PASS  ' '$T/st') -ge 30 ]"
    grep -q '^0 failure' "$T/st" || grep -E 'FAIL|Error|Traceback' "$T/st" | head -20
else
    echo "  SKIP  page build (no GTK 4 / libadwaita / Xvfb here)"
    # CI sets PRIME_REQUIRE_GUI=1: there a skip would hide that no page was built
    [ "${PRIME_REQUIRE_GUI:-0}" = 1 ] && { echo "  FAIL  PRIME_REQUIRE_GUI=1 but the pages couldn't be built"; fail=$((fail+1)); }
fi
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
