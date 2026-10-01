#!/usr/bin/env bash
# Checks run inside a fresh install (by install-in-container.sh, or by hand).
set -u
P="$HOME/.local/share/prime-linux"; L="$P/layer"; fail=0
ck() { if eval "$2" >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

ck "installed copy exists"                 "[ -x $L/bin/prime-menu ]"
ck "hyprland.conf seeded and sources Prime" "grep -q prime-linux ~/.config/hypr/hyprland.conf"
ck "hardware/monitors/addons files exist"   "[ -f ~/.config/hypr/hardware.conf ] && [ -f ~/.config/hypr/monitors.conf ] && [ -f ~/.config/hypr/addons.conf ]"
ck "theme files generated"                  "[ -f ~/.config/prime/theme/colors.css ] && [ -f ~/.config/prime/theme/hyprland.conf ] && [ -f ~/.config/prime/theme/hyprpaper.conf ]"
ck "emblem generated in the accent"         "grep -q f87171 ~/.config/prime/theme/mark.svg && [ -s ~/.config/prime/theme/mark.png ]"
ck "app-list entries installed, paths filled" "[ -f ~/.local/share/applications/prime-menu.desktop ] && ! grep -q @LAYER@ ~/.local/share/applications/prime-*.desktop"
ck "bar logo path expanded"                 "$L/bin/prime-bar --print top | jq -e '.\"image#logo\".path | startswith(\"/\")'"
ck "Hyprland accepts the whole config"      "Hyprland --verify-config -c ~/.config/hypr/hyprland.conf"
ck "every bind has a description"           "! grep -hE '^bind[a-z]* =' $L/default/hypr/*.conf $L/addons/*/hypr.conf"
ck "top bar config builds"                  "$L/bin/prime-bar --print top | jq -e '.\"modules-right\" | length > 5'"
ck "side bar config builds"                 "$L/bin/prime-bar --print side | jq -e '.\"modules-left\" | length > 0'"
ck "menu: every row resolves"               "$L/bin/prime-menu --check | tail -1 | grep -q 'every row resolves'"
ck "right-click menus list items"           "$L/bin/prime-context bar.audio --list | grep -q mixer"
ck "spotlight self-test"                    "python3 $L/bin/prime-spotlight --query notes"
ck "services linked"                        "[ -L ~/.config/systemd/user/prime-bar@.service ]"
ck "commands on PATH dir"                   "[ -L ~/.local/bin/prime-update ]"
ck "pacman backup hook installed"           "[ -f /etc/pacman.d/hooks/zz-prime-desktop-backup.hook ]"
ck "desktop backup works"                   "$L/bin/prime-desktop-backup save test && ls ~/.config-backups/desktop/*_test.tar.gz"
ck "accent switch rewrites colours"         "$L/bin/prime-theme --set-accent 60a5fa && grep -q 60a5fa ~/.config/prime/theme/colors.css"
ck "add-on enable (no setup) + bar merge"   "echo ai >> ~/.config/prime/addons && $L/bin/prime-addon --relink && grep -q addons/ai ~/.config/hypr/addons.conf && $L/bin/prime-bar --print top | jq -e '.\"modules-left\" | index(\"custom/ask\")'"
ck "config still valid with add-on"        "Hyprland --verify-config -c ~/.config/hypr/hyprland.conf"
ck "right-click gets Ask rows with add-on"  "$L/bin/prime-context bar.cpu --list | grep -q 'Ask Prime'"
ck "no trace of the author's machine"      "! grep -rIl -e /home/sean -e '\\bsean\\b' $L ~/.config/hypr ~/.config/kitty ~/.config/prime"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
