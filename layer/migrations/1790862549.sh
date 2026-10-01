#!/usr/bin/env bash
# keyboard layouts get their own file (Settings → Keyboard layout writes it)
#
# Installs from before 2026-10-01 have no ~/.config/hypr/keyboard.conf and
# their hyprland.conf doesn't source it. Create it from the layout the system
# was installed with (localectl), and add the source line just after the
# add-ons line — above "Your changes", so anything the user set still wins.
CONF="$HOME/.config/hypr/hyprland.conf"
KB="$HOME/.config/hypr/keyboard.conf"
if [ ! -f "$KB" ]; then
    layout="$(localectl status 2>/dev/null | sed -n 's/^ *X11 Layout: *//p' | tr -d ' ')"
    mkdir -p "$(dirname "$KB")"
    printf '# Keyboard layouts — written by Settings → Keyboard layout (prime-keyboard).\n# Switch between them with Super+Ctrl+Space. You can edit this file too.\ninput {\n    kb_layout = %s\n}\n' "${layout:-us}" > "$KB"
fi
[ -f "$CONF" ] || exit 0
grep -q 'hypr/keyboard.conf' "$CONF" && exit 0
line='source = ~/.config/hypr/keyboard.conf'
if grep -q '^source = ~/.config/hypr/addons.conf' "$CONF"; then
    sed -i "\#^source = ~/.config/hypr/addons.conf#a $line" "$CONF"
elif grep -q 'prime-linux/layer/default/hypr/prime.conf' "$CONF"; then
    sed -i "\#prime-linux/layer/default/hypr/prime.conf#a $line" "$CONF"
fi
# a hyprland.conf that no longer mentions Prime at all is the user's own: leave it
exit 0
