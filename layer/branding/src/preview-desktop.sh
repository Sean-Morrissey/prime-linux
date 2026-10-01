#!/usr/bin/env bash
# preview-desktop.sh [out-dir] — render the desktop surfaces to PNGs for review:
# the Prime windows (health check, update, About, password, Activity), Spotlight,
# the rofi pickers at two text sizes, and the bar. Runs on a virtual display
# (xvfb-run) with a throwaway HOME, so it never touches the real desktop.
#
# Needs: python3 + GTK 3, rofi, xvfb-run, ImageMagick; for the bar also sway + grim
# + waybar (a headless wlroots session). The lock screen and title bars can't be
# drawn without Hyprland, so lockscreen.png is a faithful MOCK built from the same
# values (layer/default/hypr/hyprlock.conf + the generated sizes) and says so.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; L="$(cd "$HERE/../.." && pwd)"
OUT="${1:-$L/branding/previews}"; mkdir -p "$OUT"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
REAL_HOME="$HOME"
export HOME="$T/home" PRIME_NO_GSETTINGS=1 PRIME_NO_LIVE=1; mkdir -p "$HOME/.config/hypr"
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
# fonts as on Prime: your own font folder still counts, and a catch-all bitmap font
# (Unifont, common on build hosts, never on Prime) must not take the icon glyphs
mkdir -p "$HOME/.config/fontconfig"
cat > "$HOME/.config/fontconfig/fonts.conf" <<EOF
<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig><dir>$REAL_HOME/.local/share/fonts</dir>
<selectfont><rejectfont><glob>*unifont*</glob><pattern><patelt name="family"><string>Unifont CSUR</string></patelt></pattern></rejectfont></selectfont></fontconfig>
EOF
PY=python3
for p in python3 /usr/bin/python3.14 /usr/bin/python3.13 /usr/bin/python3.12; do
    command -v "$p" >/dev/null && "$p" -c 'import gi; gi.require_version("Gtk", "3.0")' 2>/dev/null && { PY="$p"; break; }
done
IM=magick; command -v magick >/dev/null || IM=convert
XV=(xvfb-run -a -s "-screen 0 1600x1000x24")
bash "$L/bin/prime-theme" --apply >/dev/null 2>&1
WALL="$L/wallpapers/prime-emblem.jpg"

# a window card, centred on a blurred wallpaper (what it looks like on the desktop)
stage() {  # stage <card.png> <out.png> [min-width min-height]
    local w="${3:-1100}" h="${4:-720}" cw ch
    [ -s "$1" ] || { echo "  not rendered: $(basename "$2")" >&2; return 1; }
    read -r cw ch < <(identify -format '%w %h' "$1")
    [ $((cw + 200)) -gt "$w" ] && w=$((cw + 200)); [ $((ch + 160)) -gt "$h" ] && h=$((ch + 160))
    $IM "$WALL" -resize "${w}x${h}^" -gravity center -extent "${w}x${h}" -blur 0x18 -brightness-contrast -25x0 \
        \( "$1" \( +clone -background black -shadow 60x16+0+12 \) +swap -background none -layers merge +repage \) \
        -gravity center -composite "$2"
    echo "$2"
}
panel() {  # panel <name> <title> <subtitle> <lines…>
    local name="$1" title="$2" sub="$3"; shift 3
    printf '%s\n' "$@" > "$T/$name.txt"
    "${XV[@]}" "$PY" "$L/bin/prime-panel" --screenshot "$T/$name.png" --title "$title" --subtitle "$sub" -- cat "$T/$name.txt" >/dev/null 2>&1
    stage "$T/$name.png" "$OUT/window-$name.png"
}

panel health "Desktop health check" "Checks the desktop and repairs what it safely can. Your own settings are never changed." \
    "@ok Theme: colours, text size and wallpaper are in place" "@ok Font installed: Inter" \
    "@ok Running: The top bar" "@fix The side bar had stopped — started it again" \
    "@ok Running: Clipboard history (text)" "@ok Tray icons show in the bar" \
    "@bad Window title bars need rebuilding after an update — Update everything does it" \
    "@ok Window settings: no mistakes" "@ok The login screen offers Prime" \
    "@ok Undo for updates is on — pick the earlier state in the start-up menu" \
    "@action Update everything	true" "@summary One thing needs you — the button below fixes it."
panel update "Update everything" "Prime, the system and your apps. A snapshot is taken first, so this can be undone." \
    "@step Updating Prime" "@ok Prime updated" "@step Updating the system" "resolving dependencies..." \
    "@ok System up to date" "@ok The login screen now offers Prime" "@step Updating App Store apps" \
    "@ok App Store apps up to date" "@step Refreshing the desktop" "@ok Window title bars rebuilt for this version" \
    "@ok Desktop refreshed" "@action Check the desktop	true" \
    "@summary All up to date. If anything looks wrong, Super+H checks and repairs the desktop."
mapfile -t about < <(PRIME_PANEL=1 bash "$L/bin/prime-about")
panel about "About Prime" "A fast desktop that sets itself up, explains itself, and can undo a bad update." "${about[@]}"

# the password box sudo opens (prime-askpass), drawn offscreen
cat > "$T/askpass.py" <<'PYEOF'
import os, sys, time, importlib.machinery, importlib.util
sys.dont_write_bytecode = True
ld = importlib.machinery.SourceFileLoader("pp", os.environ["PANEL"])
pp = importlib.util.module_from_spec(importlib.util.spec_from_loader("pp", ld)); ld.exec_module(pp)
from gi.repository import Gtk
Gtk.init_check(sys.argv); pp.install_css()
win, card = pp.card_window("Password — Prime")
pp.header(card, "Your password, please", "Prime needs your password to install the system updates.")
body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8); body.set_name("header")
e = Gtk.Entry(); e.set_visibility(False); e.set_text("hunter22"); e.set_position(-1); e.select_region(-1, -1); body.pack_start(e, False, False, 0)
c = Gtk.Label(label="Caps Lock is on", xalign=0.0); c.set_name("capslock"); body.pack_start(c, False, False, 0)
card.pack_start(body, False, False, 0)
f = Gtk.Box(spacing=8); f.set_name("footer")
ok = Gtk.Button(label="Continue"); ok.get_style_context().add_class("suggested")
f.pack_end(ok, False, False, 0); f.pack_end(Gtk.Button(label="Cancel"), False, False, 0)
card.pack_end(f, False, False, 0)
off = Gtk.OffscreenWindow()
if off.get_screen().get_rgba_visual(): off.set_visual(off.get_screen().get_rgba_visual())
win.remove(card); card.set_size_request(460, -1); off.add(card); off.show_all()
for _ in range(30):
    while Gtk.events_pending(): Gtk.main_iteration_do(False)
    time.sleep(0.01)
off.get_pixbuf().savev(sys.argv[1], "png", [], [])
PYEOF
PANEL="$L/bin/prime-panel" "${XV[@]}" "$PY" "$T/askpass.py" "$T/askpass.png" >/dev/null 2>&1 && stage "$T/askpass.png" "$OUT/window-password.png" 900 520

"${XV[@]}" "$PY" "$L/bin/prime-activity" --screenshot "$T/activity.png" >/dev/null 2>&1 && stage "$T/activity.png" "$OUT/window-activity.png"
PATH="$(dirname "$(command -v "$PY")"):$PATH" "${XV[@]}" "$PY" "$L/bin/prime-spotlight" --screenshot "$T/spot.png" --query note >/dev/null 2>&1 \
    && stage "$T/spot.png" "$OUT/spotlight.png" 1100 640

# rofi pickers: the Text size picker at Default and at Larger (proves fonts.rasi drives them)
picker() {  # picker <out> <prompt> <hint> <rows…>
    local out="$1" prompt="$2" hint="$3"; shift 3
    printf '%s\n' "$@" > "$T/rows"
    xvfb-run -a -s "-screen 0 1600x1000x24" bash -c '
        "$0" -dmenu -i -no-custom -p "$1" -theme "$2" -mesg "$3" < "$4" & r=$!
        sleep 2; import -window root "$5" 2>/dev/null || xwd -root -silent | convert xwd:- "$5"; kill $r' \
        rofi "$prompt" "$L/default/rofi/spotlight.rasi" "$hint" "$T/rows" "$T/picker.png" 2>/dev/null
    $IM "$T/picker.png" -trim +repage "$T/picker-t.png" 2>/dev/null && stage "$T/picker-t.png" "$out" 1100 560
}
ROWS=("Small" "Default   (current)" "Large" "Larger")
picker "$OUT/picker-text-size-default.png" "󰛖 Text size" "one size for the whole desktop: bar, menus, notifications, lock screen, apps  ·  Esc keeps it" "${ROWS[@]}"
bash "$L/bin/prime-theme" --set-text larger >/dev/null 2>&1
picker "$OUT/picker-text-size-larger.png" "󰛖 Text size" "one size for the whole desktop: bar, menus, notifications, lock screen, apps  ·  Esc keeps it" \
    "Small" "Default" "Large" "Larger   (current)"
bash "$L/bin/prime-theme" --set-text default >/dev/null 2>&1
picker "$OUT/picker-wifi.png" "󰖩 Wi-Fi" "Enter joins  ·  Esc closes  ·  type to filter" \
    "󰄬  Home  —  connected · strong signal · secured" "󰤨  Café Lumen  —  good signal · open" \
    "󰤨  Library-Guest  —  weak signal · secured" "󰑓  Look for networks again" "󰖪  Turn Wi-Fi off"
picker "$OUT/picker-bar-keys.png" "Bar" "↑↓ move  ·  Enter opens that item's menu  ·  Esc closes  ·  type to filter" \
    $(python3 "$L/bin/prime-bar" --keys --list | cut -f2 | head -9 | tr ' ' '\240')

# the bar, for real: waybar in a headless wlroots session (its own session bus;
# Bluetooth is left out because it needs the system bus, which a preview hasn't got)
if command -v sway >/dev/null && command -v grim >/dev/null && command -v waybar >/dev/null; then
    RUN="$T/run"; mkdir -p -m 700 "$RUN" "$HOME/.local/share/prime-linux"
    ln -sfn "$L" "$HOME/.local/share/prime-linux/layer"      # the bar's commands live there
    XDG_RUNTIME_DIR="$RUN" python3 "$L/bin/prime-bar" --print top >/dev/null
    jq '."modules-right" -= ["bluetooth"]' "$RUN/prime-bar/top.json" > "$RUN/preview.json"
    printf 'output HEADLESS-1 resolution 1600x200\noutput * bg %s fill\n' "$WALL" > "$T/sway.conf"
    XDG_RUNTIME_DIR="$RUN" WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
        sway -c "$T/sway.conf" >/dev/null 2>&1 & SW=$!
    sleep 3
    sock="$(ls "$RUN" | grep -m1 '^wayland-')"
    XDG_RUNTIME_DIR="$RUN" WAYLAND_DISPLAY="$sock" timeout 12 dbus-run-session -- \
        waybar -c "$RUN/preview.json" -s "$RUN/prime-bar/top.css" >/dev/null 2>&1 &
    sleep 9
    XDG_RUNTIME_DIR="$RUN" WAYLAND_DISPLAY="$sock" grim -g "0,0 1600x56" "$T/bar.png" 2>/dev/null \
        && $IM "$T/bar.png" -resize 200% "$OUT/bar.png" && echo "$OUT/bar.png"
    kill $SW 2>/dev/null; wait 2>/dev/null
fi

# lock screen: a mock built from the same numbers (hyprlock itself needs Hyprland)
eval "$(sed -n 's/^\$\(prime_font_[a-z]*\) = \([0-9]*\)$/\1=\2/p' "$HOME/.config/prime/theme/hyprlock.conf")"
pt() { echo $(( $1 * 4 / 3 )); }     # hyprlock sizes are points; the mock is drawn at 96 dpi
W=1600; H=1000; cx=$((W/2)); cy=$((H/2))
rsvg-convert -w 64 -h 64 "$HOME/.config/prime/theme/mark.svg" -o "$T/mark.png" 2>/dev/null || cp "$L/branding/png/mark-64.png" "$T/mark.png"
$IM "$WALL" -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" -blur 0x10 -modulate 60,115 \
    "$T/mark.png" -gravity center -geometry +0-300 -composite \
    -fill 'rgba(255,255,255,0.90)' -font Inter-SemiBold -pointsize "$(pt $prime_font_name)" -annotate +0-240 "Prime" \
    -fill 'rgba(255,255,255,0.95)' -font Inter-Bold -pointsize "$(pt $prime_font_clock)" -annotate +0-130 "9:41" \
    -fill 'rgba(200,200,205,0.85)' -font Inter-Regular -pointsize "$(pt $prime_font_date)" -annotate +0-45 "Thursday, October 1" \
    -fill 'rgb(15,15,15)' -stroke '#f87171' -strokewidth 2 -draw "roundrectangle $((cx-150)),$((cy+34)) $((cx+150)),$((cy+86)) 26,26" -stroke none \
    -fill 'rgb(240,240,240)' -font Inter-Regular -pointsize 26 -annotate +0+60 "•  •  •  •  •  •" \
    -fill 'rgba(251,191,36,0.95)' -font Inter-Medium -pointsize "$(pt $prime_font_hint)" -annotate +0+115 "Caps Lock is on" \
    -fill 'rgba(200,200,205,0.70)' -font Inter-Regular -pointsize "$(pt $prime_font_hint)" -gravity south -annotate +0+40 "Type your password and press Enter to unlock" \
    -fill 'rgba(255,255,255,0.35)' -pointsize 14 -gravity northwest -annotate +16+12 "MOCK — drawn from hyprlock.conf's values; the real screen is drawn by hyprlock" \
    "$OUT/lockscreen.png" && echo "$OUT/lockscreen.png"

# window title bars: the three buttons, each with its symbol (mock, same colours and glyphs)
$IM -size 360x60 'xc:rgba(20,20,26,0.95)' \
    -fill '#ff5f57' -draw 'circle 26,30 26,37' -fill '#ffbd2e' -draw 'circle 52,30 52,37' -fill '#28c840' -draw 'circle 78,30 78,37' \
    -fill 'rgba(0,0,0,0.65)' -font DejaVu-Sans-Bold -pointsize 11 -gravity northwest \
    -annotate +21+22 '✕' -annotate +48+21 '−' -annotate +48+21 '' -annotate +74+21 '+' \
    -fill '#e4e4e7' -font Inter-Medium -pointsize 15 -gravity center -annotate +40+0 'Documents — Files' \
    -fill 'rgba(255,255,255,0.35)' -pointsize 10 -gravity southeast -annotate +6+3 'MOCK of hyprbars' \
    -resize 200% "$OUT/titlebar-buttons.png" && echo "$OUT/titlebar-buttons.png"
