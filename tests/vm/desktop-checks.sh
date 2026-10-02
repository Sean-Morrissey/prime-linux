#!/usr/bin/env bash
# Runs INSIDE the test VM, in the logged-in Prime (Hyprland) session, over SSH
# (tests/vm/run.sh copies it in). The things a friend sees first: the bar, the
# P-logo Start menu, Prime Search, the Prime menu and the P.R.I.M.E terminal
# greeting — each one is opened for real and looked for on screen.
set -u
L="$HOME/.local/share/prime-linux/layer"
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "    ✓ $1"; else echo "    ✗ $1"; fi; }
layer_up() { # layer_up <namespace> — a layer-shell surface with that name is mapped (waits up to 15 s)
    for _ in $(seq 30); do
        hyprctl -j layers | jq -e --arg n "$1" '[.. | objects | select(.namespace? == $n)] | length > 0' >/dev/null && return 0
        sleep 0.5
    done; return 1
}
gone() { for _ in $(seq 20); do pgrep -f "$1" >/dev/null || return 0; sleep 0.5; done; return 1; }

ck 'bar: top bar on screen, dock waiting at the bottom' 'layer_up waybar && pgrep -f "^nwg-dock-hyprland|/nwg-dock-hyprland"'
ck 'bar: the P logo opens the Start menu'    '"$L/bin/prime-bar" --print top | jq -e "[.. | objects | select(has(\"on-click\")) | .\"on-click\" | select(test(\"prime-start\"))] | length > 0"'
ck 'Start menu (P logo, Super+X) opens'      '( setsid "$L/bin/prime-start" >/tmp/start.log 2>&1 & ); layer_up prime-start'
grim /tmp/start-menu.png 2>/dev/null
# (match the Start program itself: the dock's command line names prime-start too)
ck 'Start menu closes again (toggle)'        '"$L/bin/prime-start"; gone "python3? [^ ]*bin/prime-start"'
ck 'Prime Search (Super+Space) opens'           '( setsid "$L/bin/prime-spotlight" >/tmp/spotlight.log 2>&1 & ); layer_up prime-spotlight'
grim /tmp/spotlight.png 2>/dev/null
pkill -f bin/prime-spotlight; gone bin/prime-spotlight
ck 'Prime menu (Super+Alt+Space) opens'      '( setsid "$L/bin/prime-menu" >/tmp/menu.log 2>&1 & ); layer_up rofi'
grim /tmp/prime-menu.png 2>/dev/null
pkill -x rofi; sleep 1
ck 'Prime menu: every row resolves'          '"$L/bin/prime-menu" --check | tail -1 | grep -q "every row resolves"'
# what a new terminal prints, from the greeting through the user's own shell (bash here),
# on a terminal-sized pty (fastfetch drops the logo on a 0-column one)
ck 'terminal greeting spells P.R.I.M.E'      'timeout 30 script -qc "stty cols 120 rows 40; SHELL=/bin/bash $L/bin/prime-terminal-shell" /dev/null </dev/null > /tmp/greeting.txt 2>&1; grep -q "verything" /tmp/greeting.txt'
ck 'a terminal window opens (kitty)'         '( setsid kitty >/dev/null 2>&1 & ); for i in $(seq 20); do hyprctl -j clients | jq -e "map(select(.class==\"kitty\")) | length > 0" && exit 0; sleep 0.5; done; exit 1'
sleep 2; grim /tmp/terminal.png 2>/dev/null; pkill -x kitty

# short diagnostics for anything that failed above, so a red run explains itself
echo "    -- diagnostics"
pgrep -x hyprpaper >/dev/null || { echo "    hyprpaper is not running; its last words:"
    journalctl --user -b --no-pager 2>/dev/null | grep -i hyprpaper | tail -15 | sed 's/^/      /'
    grep -ih hyprpaper /run/user/"$(id -u)"/hypr/*/hyprland.log 2>/dev/null | tail -10 | sed 's/^/      /'
    timeout 5 hyprpaper -c ~/.config/prime/theme/hyprpaper.conf 2>&1 | tail -15 | sed 's/^/      /'; }
grep -q verything /tmp/greeting.txt 2>/dev/null || { echo "    terminal output was:"; head -30 /tmp/greeting.txt | cat -v | sed 's/^/      /'; }
exit 0
