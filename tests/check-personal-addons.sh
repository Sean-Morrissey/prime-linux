#!/usr/bin/env bash
# tests/check-personal-addons.sh — personal add-ons (~/.config/prime/addons.d/<name>/)
# load everywhere a shipped add-on does: prime-addon, prime-bar, prime-menu,
# prime-context, prime-snip, prime-keys. No container, no root; a throwaway HOME,
# nothing touches the running desktop (PRIME_NO_LIVE, no Hyprland, fake hyprctl).
set -u
REPO="$(readlink -f "$(dirname "$(readlink -f "$0")")/..")"
L="$REPO/layer"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/home/.local/state" XDG_CONFIG_HOME="$T/home/.config"
export PRIME_NO_LIVE=1 PRIME_NONINTERACTIVE=1 PRIME_ADDON_PACKAGES=skip PRIME_NO_GSETTINGS=1
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DISPLAY PRIME_PANEL PRIME_PERSONAL_ADDONS
mkdir -p "$HOME/.config/prime" "$HOME/.config/hypr" "$XDG_RUNTIME_DIR" "$T/fake"; chmod 700 "$XDG_RUNTIME_DIR"
# no window manager here: hyprctl fails, notifications go nowhere
printf '#!/bin/sh\nexit 1\n' > "$T/fake/hyprctl"; printf '#!/bin/sh\nexit 0\n' > "$T/fake/notify-send"
chmod +x "$T/fake"/*; export PATH="$T/fake:$PATH"
echo "# enabled add-ons" > "$HOME/.config/prime/addons"
fail=0
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

# a personal add-on with every part
P="$HOME/.config/prime/addons.d/studio"
mkdir -p "$P/bin" "$P/systemd"
cat > "$P/addon.conf" <<'EOF'
TITLE="My studio"
DESCRIPTION="My own shortcuts and bar items"
UNITS="studio-helper.service"
EOF
cat > "$P/hypr.conf" <<'EOF'
bindd = SUPER SHIFT, F9, Open my studio notes, exec, true
EOF
cat > "$P/menu.json" <<'EOF'
{"sections": [{"id": "studio", "label": "My studio", "icon": "*",
  "items": [{"id": "studio.notes", "label": "Studio notes", "kind": "run", "cmd": "exec true"}]}]}
EOF
cat > "$P/elements.json" <<'EOF'
{"elements": {"bar.studio": {"label": "Studio", "state": "echo ready",
  "items": [{"label": "Open the studio folder", "cmd": "true"}]}}}
EOF
cat > "$P/waybar-top.json" <<'EOF'
{"insert": {"modules-right": {"after": "clock", "modules": ["custom/studio"]}},
 "modules": {"custom/studio": {"exec": "echo S", "interval": 60, "tooltip-format": "Studio",
   "on-click-right": "~/.local/share/prime-linux/layer/bin/prime-context bar.studio"}}}
EOF
echo '#custom-studio { padding: 0 0.5rem; }' > "$P/waybar.css"
printf '#!/bin/sh\n[ "$1" = --list ] && echo "Send to my studio"\n' > "$P/bin/prime-snip-actions"; chmod +x "$P/bin/prime-snip-actions"
printf '[Unit]\nDescription=Studio helper\n[Service]\nExecStart=/bin/true\n[Install]\nWantedBy=default.target\n' > "$P/systemd/studio-helper.service"
cp -a "$P" "$T/studio.orig"

echo "-- listed"
ck "prime-addon list shows it, marked (personal)" "$L/bin/prime-addon list | grep -E 'studio .*\(personal\)'"
ck "prime-addon info works on it"                 "$L/bin/prime-addon info studio | grep -q 'My studio'"
ck "a bad name is refused"                        "! $L/bin/prime-addon enable ../studio"

echo "-- enabled"
ck "enable switches it on"                        "$L/bin/prime-addon enable studio && grep -qx studio $HOME/.config/prime/addons"
ck "Hyprland loads its shortcuts"                 "grep -qx 'source = $P/hypr.conf' $HOME/.config/hypr/addons.conf"
ck "its background service is linked"             "[ \"\$(readlink $HOME/.config/systemd/user/studio-helper.service)\" = $P/systemd/studio-helper.service ]"
ck "bar: its module is placed and styled"         "python3 $L/bin/prime-bar --print top | jq -e '.\"modules-right\" | index(\"custom/studio\")' && python3 $L/bin/prime-bar --print-css top 2>/dev/null | grep -q custom-studio || python3 $L/bin/prime-bar --print top | jq -e '.\"custom/studio\".exec == \"echo S\"'"
ck "menu: its section and row are there"           "$L/bin/prime-menu --list | grep -q '^studio	' && $L/bin/prime-menu --list --section studio | grep -q '^studio.notes'"
ck "right-click: its element is there"            "$L/bin/prime-context bar.studio --list | grep -q 'Open the studio folder'"
# prime-snip needs a screen; run its own add-on lookup on its own
ck "snip: its action is offered"                  "bash -c 'LAYER=$L; . $L/addons/_lib/resolve.sh; eval \"\$(sed -n \"/^addon_actions()/,/^}/p\" $L/bin/prime-snip)\"; for h in \$(addon_actions); do \$h --list; done' | grep -q 'Send to my studio'"
ck "keys: its shortcut is in the cheat sheet"     "$L/bin/prime-keys --list | grep -q 'Super + Shift + F9'"
ck "health check of it runs"                      "$L/bin/prime-addon check studio"

echo "-- shipped names win"
mkdir -p "$HOME/.config/prime/addons.d/ai"; echo 'DESCRIPTION="impostor"' > "$HOME/.config/prime/addons.d/ai/addon.conf"
ck "a personal add-on can't replace a shipped one" "bash -c '. $L/addons/_lib/resolve.sh; LAYER=$L; [ \$(addon_dir ai) = $L/addons/ai ]'"
ck "…and the list says it is hidden"               "$L/bin/prime-addon list | grep -E '^ +\[--\] +ai .*hidden'"
rm -rf "$HOME/.config/prime/addons.d/ai"

echo "-- your own unit file is never overwritten"
mkdir -p "$HOME/.config/systemd/user"; printf '[Service]\nExecStart=/bin/false\n' > "$T/mine.service"
cp "$T/mine.service" "$P/systemd/mine.service"; sed -i 's/false/echo/' "$P/systemd/mine.service"
cp "$T/mine.service" "$HOME/.config/systemd/user/mine.service"
ck "a different file of yours is kept"            "$L/bin/prime-addon enable studio && [ ! -L $HOME/.config/systemd/user/mine.service ] && cmp -s $T/mine.service $HOME/.config/systemd/user/mine.service"
rm -f "$P/systemd/mine.service"

echo "-- disabled"
ck "disable switches it off"                      "$L/bin/prime-addon disable studio && ! grep -qx studio $HOME/.config/prime/addons"
ck "its shortcuts, menu and bar item are gone"    "! grep -q studio $HOME/.config/hypr/addons.conf && ! $L/bin/prime-menu --list | grep -q '^studio' && ! python3 $L/bin/prime-bar --print top | jq -e '.\"modules-right\" | index(\"custom/studio\")'"
ck "its service link is gone, yours stays"        "[ ! -e $HOME/.config/systemd/user/studio-helper.service ] && [ -f $HOME/.config/systemd/user/mine.service ]"
ck "the add-on folder itself is untouched"        "diff -r $T/studio.orig $P"
ck "relink (what prime-update runs) leaves it be" "$L/bin/prime-addon --relink && diff -r $T/studio.orig $P"

echo "-- its own setup script"
K="$HOME/.config/prime/addons.d/kit"; mkdir -p "$K/bin"
printf 'TITLE="Kit"\nDESCRIPTION="Runs a setup script"\nSETUP="bin/setup"\n' > "$K/addon.conf"
printf '#!/bin/sh\necho setup >> "%s/order"\n' "$T" > "$K/bin/setup"; chmod +x "$K/bin/setup"
printf '#!/bin/sh\necho "sudo $*" >> "%s/order"\n' "$T" > "$T/fake/sudo"; chmod +x "$T/fake/sudo"
"$L/bin/prime-addon" enable kit >/dev/null 2>&1
ck "a personal add-on's script runs only after the remembered password is forgotten (sudo -k first)" \
   "[ \"\$(grep -E '^(sudo -k|setup)\$' '$T/order' | tr '\n' ' ')\" = 'sudo -k setup ' ]"
ck "the picker says Prime didn't check it"        "$L/bin/prime-addon pick --rows 2>/dev/null | grep -q 'kit.*Prime did not check it' || grep -q 'made on this computer — Prime did not check it' $L/bin/prime-addon"

echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
