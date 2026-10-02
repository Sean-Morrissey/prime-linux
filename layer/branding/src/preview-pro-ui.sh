#!/usr/bin/env bash
# preview-pro-ui.sh [out-dir] — render the start menu, Prime Search, the Prime menu, a
# right-click menu and the terminal greeting to PNGs for review. Virtual display
# (xvfb-run) and a throwaway HOME with a handful of sample apps and recent files,
# so it never touches the real desktop.
#
# Needs python3 + GTK 3, rofi, xvfb-run, ImageMagick; the terminal greeting also
# needs a headless Chromium (CHROMIUM=…, default: first one on PATH or Playwright's).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; L="$(cd "$HERE/../.." && pwd)"
OUT="${1:-$L/branding/previews}"; mkdir -p "$OUT"
REAL_HOME="$HOME"
# not under /tmp: Recent (rightly) hides files that live there
T="$(mktemp -d -p "$REAL_HOME" prime-preview.XXXXXX)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run" PRIME_NO_GSETTINGS=1 PRIME_NO_LIVE=1 USER=alex
mkdir -p "$HOME/.config/prime" "$HOME/.local/share/applications" "$XDG_RUNTIME_DIR" "$HOME/Documents" "$HOME/Pictures"
chmod 700 "$XDG_RUNTIME_DIR"; unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
IM=magick; command -v magick >/dev/null || IM=convert
PY=python3
for p in python3 /usr/bin/python3.14 /usr/bin/python3.13 /usr/bin/python3.12; do
    command -v "$p" >/dev/null && "$p" -c 'import gi; gi.require_version("Gtk", "3.0")' 2>/dev/null && { PY="$p"; break; }
done
# GDK_BACKEND=x11: some GTK builds probe a Wayland/portal backend first and fail
# outright instead of falling back, even with no WAYLAND_DISPLAY set and nothing
# but Xvfb's X11 to talk to — force the backend Xvfb actually provides.
XV=(xvfb-run -a -s "-screen 0 1600x1000x24" env GDK_BACKEND=x11)
mkdir -p "$HOME/.config/fontconfig"   # your fonts, and no catch-all bitmap font stealing icon glyphs
cat > "$HOME/.config/fontconfig/fonts.conf" <<EOF
<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig><dir>$REAL_HOME/.local/share/fonts</dir>
<selectfont><rejectfont><glob>*unifont*</glob><pattern><patelt name="family"><string>Unifont CSUR</string></patelt></pattern></rejectfont></selectfont></fontconfig>
EOF
bash "$L/bin/prime-theme" --apply >/dev/null 2>&1
mkdir -p "$HOME/.config/gtk-3.0"
printf '[Settings]\ngtk-icon-theme-name=%s\ngtk-application-prefer-dark-theme=1\ngtk-font-name=Inter 10\n' \
    Papirus-Dark > "$HOME/.config/gtk-3.0/settings.ini"
printf 'name: "Alex Rivera"\n' > "$HOME/.config/prime/identity.yaml"

app() {  # app <id> <Name> <icon> <comment>
    printf '[Desktop Entry]\nType=Application\nName=%s\nIcon=%s\nComment=%s\nExec=true\n' "$2" "$3" "$4" \
        > "$HOME/.local/share/applications/$1.desktop"
}
app nemo "Files" system-file-manager "Browse your files"
app firefox "Firefox" firefox "Browse the web"
app kitty "Terminal" utilities-terminal "For typing commands"
app org.gnome.Software "App Store" org.gnome.Software "Install apps with a click"
app prime-settings "Settings" preferences-system "Wi-Fi, sound, displays and more"
app org.gnome.TextEditor "Text Editor" org.gnome.TextEditor "Write notes and plain text"
app org.gnome.Calculator "Calculator" accessories-calculator "Sums, big and small"
app steam "Steam" steam "Games"
app spotify "Spotify" spotify-client "Music"
app libreoffice-writer "Writer" libreoffice-writer "Documents and essays"
app obsidian "Obsidian" obsidian "Notes that link together"
app discord "Discord" discord "Chat with friends"
printf 'nemo\nfirefox\nkitty\norg.gnome.Software\nprime-settings\norg.gnome.TextEditor\nsteam\nspotify\nlibreoffice-writer\nobsidian\ndiscord\norg.gnome.Calculator\n' \
    > "$HOME/.config/prime/pinned"
for f in "Documents/History essay.docx" "Documents/Budget 2026.ods" "Pictures/Mountains.jpg" "Documents/Notes.md"; do : > "$HOME/$f"; done
{ echo '<?xml version="1.0"?><xbel version="1.0">'
  n=0; for f in "Documents/History essay.docx" "Documents/Budget 2026.ods" "Pictures/Mountains.jpg" "Documents/Notes.md" ".cache/junk.png"; do
      printf '<bookmark href="file://%s/%s" visited="2026-10-01T1%d:00:00Z"/>\n' "$HOME" "${f// /%20}" "$n"; n=$((n+1)); done
  echo '</xbel>'; } > "$HOME/.local/share/recently-used.xbel"

stage() {  # stage <card.png> <out.png> — the card on a blurred wallpaper
    local cw ch; [ -s "$1" ] || { echo "  not rendered: $(basename "$2")" >&2; return 1; }
    read -r cw ch < <(identify -format '%w %h' "$1")
    $IM "$L/wallpapers/prime-tide.jpg" -resize "$((cw + 160))x$((ch + 140))^" -gravity center \
        -extent "$((cw + 160))x$((ch + 140))" -blur 0x18 -brightness-contrast -20x0 \
        "$1" -gravity center -composite "$2" && echo "$2"
}

"${XV[@]}" "$PY" "$L/bin/prime-start" --screenshot "$T/start.png" >/dev/null 2>&1; stage "$T/start.png" "$OUT/start-menu.png"
"${XV[@]}" "$PY" "$L/bin/prime-start" --screenshot "$T/start-all.png" --all >/dev/null 2>&1; stage "$T/start-all.png" "$OUT/start-menu-all-apps.png"
"${XV[@]}" "$PY" "$L/bin/prime-start" --screenshot "$T/start-q.png" --query te >/dev/null 2>&1; stage "$T/start-q.png" "$OUT/start-menu-search.png"
"${XV[@]}" "$PY" "$L/bin/prime-spotlight" --screenshot "$T/spot.png" --query "" >/dev/null 2>&1; stage "$T/spot.png" "$OUT/spotlight-recent.png"
"${XV[@]}" "$PY" "$L/bin/prime-spotlight" --screenshot "$T/spot-q.png" --query "te" >/dev/null 2>&1; stage "$T/spot-q.png" "$OUT/spotlight.png"

# rofi boxes: run the real script, photograph the screen, close it
shoot() {  # shoot <out.png> <command…>
    local out="$1"; shift
    "${XV[@]}" bash -c '"$@" & r=$!; sleep 3; import -window root "'"$T/shot.png"'"; kill $r; pkill -x rofi; wait' _ "$@" >/dev/null 2>&1
    $IM "$T/shot.png" -trim +repage "$T/shot-t.png" 2>/dev/null && stage "$T/shot-t.png" "$out"
}
echo '{"text":"1"}' > "$XDG_RUNTIME_DIR/waybar-updates.json"
shoot "$OUT/prime-menu.png" bash "$L/bin/prime-menu"
shoot "$OUT/prime-menu-settings.png" bash "$L/bin/prime-menu" --section settings
shoot "$OUT/right-click-menu.png" bash "$L/bin/prime-context" bar.clock

# the screen saver: a pure Cairo render to a PNG, no display needed
"$PY" "$L/bin/prime-screensaver" --screenshot "$OUT/screensaver.png" >/dev/null

# the terminal greeting: the real logo file beside a sample module list, drawn by Chromium
CHROMIUM="${CHROMIUM:-$(command -v chromium || command -v chromium-browser || ls /opt/pw-browsers/chromium-*/chrome-linux/chrome 2>/dev/null | head -1)}"
if [ -n "$CHROMIUM" ] && [ -x "$CHROMIUM" ]; then
    python3 - "$L/branding/terminal/prime-logo.txt" "$T/greeting.html" <<'PYEOF'
import html, re, sys
logo = open(sys.argv[1], encoding="utf-8").read().rstrip("\n").split("\n")
def ansi(line):
    out, style = [], ""
    for part in re.split(r"(\x1b\[[0-9;]*m)", line):
        m = re.fullmatch(r"\x1b\[([0-9;]*)m", part)
        if m:
            c = m.group(1)
            style = "" if c in ("0", "") else ("color:#fff;font-weight:700" if c == "1;97" else
                    "color:rgb(%s,%s,%s)" % tuple(c.split(";")[2:5]))
        elif part:
            out.append(f'<span style="{style}">{html.escape(part)}</span>')
    return "".join(out)
keys = [("alex@prime", None), ("─" * 18, None), ("System", "CachyOS Linux x86_64"), ("Computer", "Framework Laptop 16"),
        ("Kernel", "6.17.2-cachyos"), ("On for", "2 hours, 14 mins"), ("Apps", "1243 (pacman), 12 (flatpak)"),
        ("Shell", "fish 4.1"), ("Screen", "1920x1080 · 1920x1080"), ("Desktop", "Hyprland"), ("Terminal", "kitty 0.43"),
        ("Processor", "AMD Ryzen 7 7840HS (16) @ 5.1 GHz"), ("Graphics", "AMD Radeon 780M"), ("Memory", "6.1 GiB / 30.6 GiB (20%)"),
        ("Disk", "212 GiB / 931 GiB (23%) - btrfs"), ("Battery", "86% [AC connected]"), ("", None), ("COLORS", None)]
pad_top, rows = 2, max(len(keys), 2 + len(logo))
left = [""] * pad_top + [ansi(l) for l in logo] + [""] * rows
lines = []
for i in range(rows):
    k = keys[i] if i < len(keys) else ("", None)
    if k[0] == "COLORS":
        right = "".join(f'<span style="background:{c}">   </span>' for c in
                        ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#cba6f7", "#94e2d5", "#bac2de"])
    elif k[1] is None:
        right = f'<span style="color:rgb(96,165,250);font-weight:700">{html.escape(k[0])}</span>' if i == 0 else html.escape(k[0])
    else:
        right = f'<span style="color:rgb(134,152,251);font-weight:700">{k[0]}</span>  {html.escape(k[1])}'
    lines.append(f'<div class="l"><span class="logo">{left[i]}</span>{right}</div>')
open(sys.argv[2], "w").write(f"""<!doctype html><meta charset=utf-8><style>
body{{margin:0;background:#16161c;color:#d8d8de;font:15px/1.12 'JetBrainsMono Nerd Font','DejaVu Sans Mono',monospace}}
.t{{padding:18px 22px;width:max-content}} .l{{white-space:pre;height:1.12em}} .logo{{display:inline-block;width:22ch;padding-left:2ch}}
.p{{color:#9a9aa3}}</style><div class=t><div class="l p">~ ❯ <span style="color:#fff">fish</span></div>{''.join(lines)}
<div class="l p">~ ❯ </div></div>""")
PYEOF
    "$CHROMIUM" --headless=new --no-sandbox --disable-gpu --hide-scrollbars --window-size=760,540 \
        --screenshot="$T/greeting.png" "file://$T/greeting.html" >/dev/null 2>&1
    $IM "$T/greeting.png" -trim +repage -bordercolor '#16161c' -border 18 "$OUT/terminal-greeting.png" && echo "$OUT/terminal-greeting.png"
fi
