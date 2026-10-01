#!/usr/bin/env bash
# Pack checks, run inside a fresh install (by packs-in-container.sh, or by hand in a
# throwaway account). Enables every pack non-interactively, checks what each one
# adds, then disables it again and checks it's all gone.
#
#   PRIME_ADDON_PACKAGES=check (default) resolve packages + Flathub ids, install nothing
#   PRIME_ADDON_PACKAGES=install          really install everything (slow, many GB)
set -u
P="$HOME/.local/share/prime-linux"; L="$P/layer"; A="$L/bin/prime-addon"; fail=0
export PRIME_NONINTERACTIVE=1 PRIME_GPU="${PRIME_GPU:-none}" PRIME_ADDON_PACKAGES="${PRIME_ADDON_PACKAGES:-check}"
export PRIME_GIT_NAME="Alex Example" PRIME_GIT_EMAIL="alex@example.com"
PACKS="gaming coding creator student"
LOGS="${TMPDIR:-/tmp}/prime-pack-logs"; mkdir -p "$LOGS"
ck() { if eval "$2" >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
sections() { "$L/bin/prime-menu" --list | cut -f1; }

echo "== pack files ($PRIME_ADDON_PACKAGES mode, GPU=$PRIME_GPU)"
for p in $PACKS; do
    d="$L/addons/$p"
    ck "$p: addon.conf is a pack"          "( . $d/addon.conf; [ \"\$KIND\" = pack ] && [ -n \"\$DESCRIPTION\" ] && [ -n \"\$TITLE\" ] )"
    ck "$p: JSON files parse"              "for f in $d/*.json; do jq -e . \$f; done"
    ck "$p: scripts parse"                 "for f in $d/bin/*; do bash -n \$f; done"
    ck "$p: every bind has a description"  "! grep -E '^bind' $d/hypr.conf | grep -vE '^bind[a-z]*d[a-z]* ='"
    ck "$p: shows in the Packs list"       "$A list | grep -E '^\s+\[off\]\s+$p '"
    ck "$p: info explains it"              "$A info $p | grep -q 'Packages for this computer'"
done
ck "coding: fish/zsh snippets parse"       "{ ! command -v fish || fish -n $L/addons/coding/shell/coding.fish; } && { ! command -v zsh || zsh -n $L/addons/coding/shell/coding.zsh; } && bash -n $L/addons/coding/shell/coding.bash"

echo "== enable each pack (non-interactive)"
for p in $PACKS; do
    ck "$p: enable"                        "$A enable $p > $LOGS/enable-$p.log 2>&1"
    ck "$p: enable again (idempotent)"     "$A enable $p > $LOGS/enable2-$p.log 2>&1 && [ \$(grep -cx $p ~/.config/prime/addons) = 1 ]"
    ck "$p: listed as on"                  "$A list | grep -E '^\s+\[on\]\s+$p '"
    ck "$p: shortcuts sourced"             "grep -q addons/$p/hypr.conf ~/.config/hypr/addons.conf"
    ck "$p: menu section appears"          "sections | grep -qx $p"
    ck "$p: health check runs"             "$A check $p | grep -qE '✓|!'"
    [ "$PRIME_ADDON_PACKAGES" = install ] && ck "$p: health check passes" "$A check $p > $LOGS/check-$p.log 2>&1"
done
[ $fail = 0 ] || { echo "-- enable logs:"; tail -n 15 "$LOGS"/enable-*.log; }

if [ "$PRIME_ADDON_PACKAGES" = check ]; then
    echo "== packages resolve for every kind of graphics card"
    for g in amd intel nvidia nouveau "intel nvidia"; do
        for p in gaming creator; do
            ck "$p with GPU '$g'"     "PRIME_GPU='$g' $A enable $p > $LOGS/gpu-$p.log 2>&1"
        done
    done
fi

echo "== all packs on together"
ck "Hyprland accepts the config with every pack"  "Hyprland --verify-config -c ~/.config/hypr/hyprland.conf"
ck "menu: every row resolves"                     "$L/bin/prime-menu --check | tail -1 | grep -q 'every row resolves'"
ck "top bar builds with pack modules"             "$L/bin/prime-bar --print top | jq -e '(.\"modules-right\" | index(\"custom/perf\")) and (.\"modules-center\" | index(\"custom/focus\"))'"
ck "no shortcut is bound twice"                   "! grep -hE '^bind' $L/default/hypr/*.conf $L/addons/*/hypr.conf | sed -E 's/^[a-z]+ *= *([^,]*),([^,]*),.*/\1,\2/;s/ +/ /g' | tr a-z A-Z | sort | uniq -d | grep ."
ck "pack .desktop entries installed, paths filled" "[ -f ~/.local/share/applications/prime-performance-mode.desktop ] && [ -f ~/.local/share/applications/prime-focus-mode.desktop ] && ! grep -q @LAYER@ ~/.local/share/applications/prime-*.desktop"

echo "== what each pack set up"
ck "gaming: FPS overlay config written, hidden by default" "grep -qx no_display ~/.config/MangoHud/MangoHud.conf"
ck "gaming: FPS overlay toggles"            "$L/addons/gaming/bin/prime-gaming hud on && [ \$($L/addons/gaming/bin/prime-gaming hud status) = on ] && $L/addons/gaming/bin/prime-gaming hud off && [ \$($L/addons/gaming/bin/prime-gaming hud status) = off ]"
ck "gaming: multilib switched on"           "pacman-conf --repo-list | grep -qx multilib"
ck "gaming: perf bar output is JSON"        "$L/addons/gaming/bin/prime-gaming perf bar | jq -e .text"
ck "coding: git identity from the interview" "[ \"\$(git config --global user.email)\" = alex@example.com ]"
ck "coding: git defaults set"               "[ \"\$(git config --global init.defaultBranch)\" = main ]"
ck "coding: ~/Projects + sidebar bookmark"  "[ -d ~/Projects ] && grep -q \"file://\$HOME/Projects\" ~/.config/gtk-3.0/bookmarks"
ck "coding: shell hook added exactly once"  "[ \$(grep -c '# prime:coding\$' ~/.bashrc) = 1 ]"
ck "coding: container sub-IDs"              "grep -q \"^\$(id -un):\" /etc/subuid"
ck "coding: new project made with git"      "$L/addons/coding/bin/prime-coding new 'My First App' && [ -d ~/Projects/my-first-app/.git ]"
ck "student: Study folders"                 "[ -d ~/Study/Notes ] && [ -d ~/Study/Reading ] && [ -d ~/Study/Assignments ] && [ -d ~/Study/Classes ]"
ck "student: Obsidian opens ~/Study/Notes"  "jq -e '.vaults[] | select(.path == \"'\$HOME'/Study/Notes\")' ~/.config/obsidian/obsidian.json"
ck "student: focus bar hidden when off"     "[ \"\$($L/addons/student/bin/prime-student focus bar | jq -r .text)\" = '' ]"
ck "student: tutor explains it needs the AI add-on" "! $L/addons/student/bin/prime-student tutor hello"
ck "creator: hardware report runs"          "$L/addons/creator/bin/prime-creator hw; true"

echo "== disable each pack"
for p in $PACKS; do
    ck "$p: disable"                        "$A disable $p > $LOGS/disable-$p.log 2>&1"
    ck "$p: off in the list"                "$A list | grep -E '^\s+\[off\]\s+$p '"
    ck "$p: shortcuts gone"                 "! grep -q addons/$p/ ~/.config/hypr/addons.conf"
    ck "$p: menu section gone"              "! sections | grep -qx $p"
    ck "$p: disable again is harmless"      "$A disable $p"
done
ck "coding: shell hook removed"             "! grep -q '# prime:coding\$' ~/.bashrc"
ck "pack .desktop entries removed"          "[ ! -f ~/.local/share/applications/prime-performance-mode.desktop ] && [ ! -f ~/.local/share/applications/prime-focus-mode.desktop ]"
ck "Hyprland config still valid"            "Hyprland --verify-config -c ~/.config/hypr/hyprland.conf"
[ "$PRIME_ADDON_PACKAGES" = install ] && ck "disable lists the apps that stay" "grep -q 'still on your computer' $LOGS/disable-gaming.log"
ck "no trace of the author's machine"       "! grep -rIl -e /home/sean -e '\\bsean\\b' $L/addons $L/bin/prime-addon"

echo; [ $fail = 0 ] && echo "ALL PACK CHECKS PASSED" || echo "$fail PACK CHECKS FAILED (logs: $LOGS)"; exit $fail
