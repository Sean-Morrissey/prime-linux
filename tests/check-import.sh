#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"   # never the real home or session (tests/sandbox.sh)
# tests/check-import.sh — prime-import on a realistic hand-built desktop
# (tests/fixtures/legacy-desktop, synthetic): dry run changes nothing, apply
# brings everything over (no secrets, no clashing keys, every bind described),
# Hyprland accepts the result, and undo puts the old setup back byte for byte.
# No container, no root; a throwaway HOME; never touches the running desktop.
set -u
REPO="$(readlink -f "$(dirname "$(readlink -f "$0")")/..")"
L="$REPO/layer"; FIX="$REPO/tests/fixtures/legacy-desktop/home"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/home/.local/state"
export PRIME_NO_LIVE=1 PRIME_NONINTERACTIVE=1 PRIME_NO_GSETTINGS=1
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DISPLAY PRIME_PANEL PRIME_PERSONAL_ADDONS XDG_CONFIG_HOME
mkdir -p "$XDG_RUNTIME_DIR" "$T/fake"; chmod 700 "$XDG_RUNTIME_DIR"
printf '#!/bin/sh\nexit 1\n' > "$T/fake/hyprctl"; printf '#!/bin/sh\nexit 0\n' > "$T/fake/notify-send"
chmod +x "$T/fake"/*; export PATH="$T/fake:$PATH"
KEY='FAKEFAKEFAKE0000test0000notareal'
fail=0
ck() { if ( eval "$2" ) >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/        /' "$T/out" | head -15; fail=$((fail+1)); fi; }

# the old desktop, and Prime installed for this account (the layer, nothing else yet)
cp -a "$FIX" "$HOME"
chmod 600 "$HOME/.hermes/.env"
mkdir -p "$HOME/Pictures/Wallpapers" "$HOME/.local/share" "$HOME/.config/prime"
cp "$L/wallpapers/prime-aurora.jpg" "$HOME/Pictures/Wallpapers/aurora.jpg"
ln -s "$REPO" "$HOME/.local/share/prime-linux"
( umask 077; printf 'sk-FAKE-ai-key-for-the-test-%s\n' "$KEY" > "$HOME/.config/prime/ai.key" )
cp "$HOME/.config/prime/ai.key" "$T/ai.key.orig"

# every file, link and folder under the settings import touches: type, mode, content / target
tree() {
    python3 - "$HOME" "$@" <<'PY'
import hashlib, os, stat, sys
home, roots = sys.argv[1], sys.argv[2:]
for r in roots:
    top = os.path.join(home, r)
    if not os.path.lexists(top):
        print(f"{r} -"); continue
    for root, dirs, files in os.walk(top):
        dirs.sort()
        for n in sorted(dirs + files):
            p = os.path.join(root, n); rel = os.path.relpath(p, home); st = os.lstat(p)
            if stat.S_ISLNK(st.st_mode): what = "link " + os.readlink(p)
            elif stat.S_ISDIR(st.st_mode): what = "dir"
            else: what = "file " + hashlib.sha256(open(p, "rb").read()).hexdigest()[:16]
            print(f"{rel} {oct(st.st_mode & 0o7777)} {what}")
PY
}
SAVED=(.config/hypr .config/waybar .config/rofi .config/swaync .config/kitty .config/prime .config/systemd/user .hermes)
tree "${SAVED[@]}" > "$T/before.txt"
find "$HOME" -printf '%P\n' | sort > "$T/all-before.txt"
A="$HOME/.config/prime/addons.d/my-desktop"

echo "-- dry run"
ck "dry run explains the plan"                  "$L/bin/prime-import --dry-run > $T/plan.txt && grep -q 'Open Steam' $T/plan.txt && grep -q 'clash' $T/plan.txt && grep -q 'HDMI-A-2' $T/plan.txt"
ck "dry run changes nothing at all"            "find $HOME -printf '%P\n' | sort | diff - $T/all-before.txt && tree ${SAVED[*]} | diff - $T/before.txt"
ck "dry run never prints a secret"             "! grep -q $KEY $T/plan.txt"

echo "-- apply"
ck "apply runs"                                 "$L/bin/prime-import --apply --yes"
ck "a private backup and a restore script"      "d=\$(ls -d $HOME/.config-backups/import-*) && [ \$(stat -c %a \$d) = 700 ] && [ \$(stat -c %a \$d/before.tar.gz) = 600 ] && [ -x \$d/restore.sh ] && ls $HOME/.config-backups/desktop/*_before-import.tar.gz"
ck "the backup never holds the AI key"          "! tar -tzf $HOME/.config-backups/import-*/before.tar.gz | grep -q ai.key && ! tar -tzf $HOME/.config-backups/desktop/*_before-import.tar.gz | grep -q ai.key"
ck "listed as a personal add-on, switched on"   "$L/bin/prime-addon list | grep -E 'my-desktop .*\(personal\)' && grep -qx my-desktop $HOME/.config/prime/addons"
ck "app shortcuts came over, described"         "grep -q '^bindd = SUPER, F1, Open Steam, exec, steam' $A/hypr.conf && grep -q '^bindd = SUPER, F2, Open Spotify' $A/hypr.conf && grep -q '^bindd = SUPER, F3, Open Discord' $A/hypr.conf && grep -q '^bindd = SUPER, F4, Open Obsidian' $A/hypr.conf"
ck "push-to-talk pair kept (press + release)"   "grep -qE '^bind(ed|de) = , F13, .*ptt.sh start' $A/hypr.conf && grep -qE '^bindr[a-z]*d[a-z]* = , F13, .*let go.*ptt.sh stop' $A/hypr.conf"
ck "every active bind is a bindd"               "! grep -E '^bind[a-z]* *=' $A/hypr.conf | grep -vE '^bind[a-z]*d[a-z]* *='"
ck "clashes are reported and switched off"      "grep -q '^# bindd = SUPER SHIFT, S, .*Prime.s: Screenshot' $A/hypr.conf && grep -q '^# bindd = SUPER ALT, G' $A/hypr.conf && grep -q '^# bindd = SUPER, B, Open Firefox' $A/hypr.conf"
ck "no key is bound twice (Prime + packs + yours)" "[ -z \"\$(awk 'FNR==1{insub=0} /^submap[ \t]*=[ \t]*reset/{insub=0; next} /^submap[ \t]*=/{insub=1; next} insub{next} /^bind[a-z]* =/{print}' $L/default/hypr/*.conf $L/addons/*/hypr.conf $A/hypr.conf | sed -E 's/^bind([a-z]*) *= *([^,]*),([^,]*),.*/\\2,\\3,\\1/; s/,[a-qs-z]*\$//; s/ *, */,/g' | tr a-z A-Z | sort | uniq -d)\" ]"
ck "Prime's own shortcuts weren't copied"       "! grep -qE 'killactive|, Return,|workspace, 1\$' $A/hypr.conf"
ck "screens → monitors.conf"                    "grep -qx 'monitor = HDMI-A-2, 1920x1080@144, 0x0, 1' $HOME/.config/hypr/monitors.conf && grep -qx 'monitor = HDMI-A-1, 1920x1080@60, 1920x0, 1' $HOME/.config/hypr/monitors.conf"
ck "workspaces 1-5 / 6-10 per screen → hardware.conf" "[ \$(grep -cE '^workspace = ([1-5]), monitor:HDMI-A-2' $HOME/.config/hypr/hardware.conf) = 5 ] && [ \$(grep -cE '^workspace = ([6-9]|10), monitor:HDMI-A-1' $HOME/.config/hypr/hardware.conf) = 5 ]"
ck "graphics env → hardware.conf"               "grep -qx 'env = MESA_VK_DEVICE_SELECT,1002:7590' $HOME/.config/hypr/hardware.conf && grep -q AMD_VULKAN_ICD $HOME/.config/hypr/hardware.conf"
ck "window rules in today's format"             "grep -qxF 'windowrule = workspace 6 silent, match:class ^(discord)\$' $A/hypr.conf && grep -qxF 'windowrule = float on, match:class ^(prime-whiteboard)\$' $A/hypr.conf && ! grep -q windowrulev2 $A/hypr.conf"
ck "own programs start; Prime's aren't doubled" "grep -q 'exec-once = ~/.hermes/scripts/hermes-daemon.sh' $A/hypr.conf && grep -q 'syncthing' $A/hypr.conf && ! grep -qE 'exec-once = .*(waybar|launch.sh|hyprpaper|swaync|nm-applet|cliphist|polkit)' $A/hypr.conf"
ck "keyboard layouts → keyboard.conf"           "grep -q 'kb_layout = us,de' $HOME/.config/hypr/keyboard.conf"
ck "wallpaper + accent → theme.conf"            "grep -q 'WALL=.*Pictures/Wallpapers/aurora.jpg' $HOME/.config/prime/theme.conf && grep -qx 'ACCENT=a78bfa' $HOME/.config/prime/theme.conf && grep -q a78bfa $HOME/.config/prime/theme/colors.css"
ck "bar: your items, not Prime's or unused ones" "jq -e '.modules | has(\"custom/hermes\") and has(\"custom/speak\") and has(\"temperature\") and (has(\"custom/gpu\") | not) and (has(\"pulseaudio\") | not) and (has(\"custom/apple-menu\") | not)' $A/waybar-top.json && jq -e '.modules | has(\"custom/whiteboard\") and has(\"custom/ledger\") and has(\"custom/weather\")' $A/waybar-side.json"
ck "bar: their styles, not the old bar's"       "grep -q '#custom-hermes' $A/waybar.css && grep -q '#custom-whiteboard' $A/waybar.css && grep -q '@define-color pill' $A/waybar.css && ! grep -qE 'window#waybar|@define-color unused|#clock' $A/waybar.css"
ck "the bar builds with them"                   "python3 $L/bin/prime-bar --print top | jq -e '.\"modules-right\" | index(\"custom/speak\")' && python3 $L/bin/prime-bar --print side | jq -e '.\"modules-left\" | index(\"custom/whiteboard\")'"
ck "services managed by the add-on"             "[ -f $A/systemd/prime-speak.service ] && [ -f $A/systemd/prime-whiteboard.service ] && grep -q 'UNITS=\"prime-speak.service prime-whiteboard.service\"' $A/addon.conf && [ \"\$(readlink $HOME/.config/systemd/user/prime-speak.service)\" = $A/systemd/prime-speak.service ]"
ck "a service holding a key is left alone"      "[ ! -e $A/systemd/hermes-gateway.service ] && [ ! -L $HOME/.config/systemd/user/hermes-gateway.service ] && grep -q 'hermes-gateway.service' $A/import-report.txt"
ck "no secret copied anywhere Prime wrote"      "! grep -rq $KEY $A $HOME/.config/hypr/monitors.conf $HOME/.config/hypr/hardware.conf $HOME/.config/hypr/keyboard.conf $HOME/.config/hypr/hyprland.conf $HOME/.config/prime/theme.conf $HOME/.config/prime/theme $HOME/.config/hypr/addons.conf"
ck "the old .env stays where it was, untouched" "[ \$(stat -c %a $HOME/.hermes/.env) = 600 ] && ! find $HOME/.config -name .env | grep -q ."
ck "nothing deleted: old files renamed or kept" "[ -f $HOME/.config/hypr/hyprland.conf.before-prime ] && [ -f $HOME/.config/hypr/conf/keybinds.conf ] && [ -f $HOME/.config/waybar/config ] && [ -f $HOME/.hermes/scripts/ptt.sh ]"
ck "the settings file is Prime's now"           "grep -q prime-linux $HOME/.config/hypr/hyprland.conf"
ck "Super+/ lists your shortcuts"               "$L/bin/prime-keys --list | grep -q 'Super + F1 .*Open Steam'"
ck "a second apply is refused until undone"     "! $L/bin/prime-import --apply --yes"
if command -v Hyprland >/dev/null 2>&1; then
ck "Hyprland accepts the result"                "Hyprland --verify-config -c $HOME/.config/hypr/hyprland.conf | tee $T/verify.txt | tail -3; grep -qi 'config ok' $T/verify.txt"
else
echo "  SKIP  Hyprland isn't installed here — --verify-config not run"
fi

echo "-- undo"
ck "undo runs"                                  "$L/bin/prime-import --undo"
ck "the old setup is back, exactly"             "tree ${SAVED[*]} | diff $T/before.txt -"
ck "the AI key is still there"                  "cmp $T/ai.key.orig $HOME/.config/prime/ai.key && [ \$(stat -c %a $HOME/.config/prime/ai.key) = 600 ]"
ck "undo again changes nothing"                 "$L/bin/prime-import --undo && tree ${SAVED[*]} | diff $T/before.txt -"
ck "apply → undo round-trips a second time"     "$L/bin/prime-import --apply --yes && $L/bin/prime-import --undo && tree ${SAVED[*]} | diff $T/before.txt -"

echo "-- the installer offers it"
H2="$T/home2"; cp -a "$FIX" "$H2"; find "$H2" -printf '%P %m\n' | sort > "$T/h2.txt"
if command -v pacman >/dev/null 2>&1; then
ck "install.sh --dry-run shows the import plan, changes nothing" "HOME=$H2 XDG_STATE_HOME= bash $REPO/install.sh --dry-run --no-packages > $T/inst.txt 2>&1; grep -q 'bring it along' $T/inst.txt && grep -q 'Open Steam' $T/inst.txt && find $H2 -printf '%P %m\n' | sort | diff - $T/h2.txt"
else
echo "  SKIP  no pacman here — install.sh --dry-run not run"
fi

echo "-- after the installer (old settings in its backup)"
B="$HOME/.config-backups/prime-install-20260101-000000"
mkdir -p "$B/hypr"; cp "$HOME/.config/hypr/hyprland.conf" "$B/hypr/hyprland.conf"
cp "$L/seed/hypr/hyprland.conf" "$HOME/.config/hypr/hyprland.conf"
ck "finds the saved copy by itself"             "$L/bin/prime-import --dry-run | grep -q 'prime-install-20260101-000000' && $L/bin/prime-import --dry-run | grep -q 'Open Discord'"
ck "--from reads a given folder"                "$L/bin/prime-import --dry-run --from $B | grep -q 'Open Obsidian'"
rm -f "$HOME/.local/share/prime-linux"
ck "apply needs Prime installed first"          "! $L/bin/prime-import --apply --yes --from $B"

echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
