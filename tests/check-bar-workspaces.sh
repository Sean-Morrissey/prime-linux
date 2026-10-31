#!/usr/bin/env bash
# tests/check-bar-workspaces.sh — the workspace dots keep working across the
# Hyprland 0.57 / waybar split (docs/HYPRLAND-057-PORT.md). prime-bar swaps
# hyprland/workspaces for ext/workspaces only where the click is actually broken,
# and puts it back the moment waybar ships the fix. No container, no root; a
# throwaway HOME, a fake hyprctl and waybar, nothing touches the running desktop.
set -u
REPO="$(readlink -f "$(dirname "$(readlink -f "$0")")/..")"
L="$REPO/layer"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run" XDG_CONFIG_HOME="$T/home/.config"
# the throwaway HOME carries the XDG dirs with it: without this the tools under
# test read and write the real ~/.config, ~/.local/state and ~/.cache
export XDG_STATE_HOME="$HOME/.local/state" XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache" XDG_DATA_HOME="$HOME/.local/share"
export PRIME_NO_LIVE=1 PRIME_NONINTERACTIVE=1
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DISPLAY
mkdir -p "$HOME/.config/prime" "$XDG_RUNTIME_DIR" "$T/fake" "$T/noaddons"
chmod 700 "$XDG_RUNTIME_DIR"
echo "# enabled add-ons" > "$HOME/.config/prime/addons"
export PRIME_PERSONAL_ADDONS="$T/noaddons"
fail=0
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

# fake hyprctl/waybar: the versions come from $HYPR_V/$BAR_V, every call is logged,
# and the compositor reports no workspaces at all so persistent ones must be made.
cat > "$T/fake/hyprctl" <<'EOF'
#!/bin/sh
echo "hyprctl $*" >> "$CALLS"
case "$1 ${2:-}" in
  "version -j") printf '{"tag":"v%s"}\n' "$HYPR_V" ;;
  "version "*)  printf 'Hyprland %s built from branch v%s\n' "$HYPR_V" "$HYPR_V" ;;
  "workspaces "*) echo '[]' ;;
  "eval "*) echo ok ;;
esac
EOF
printf '#!/bin/sh\necho "waybar $*" >> "$CALLS"\necho "Waybar v$BAR_V"\n' > "$T/fake/waybar"
chmod +x "$T/fake"/*; export PATH="$T/fake:$PATH"
export CALLS="$T/calls"

# print the top bar as prime-bar would build it on the given Hyprland + waybar
bar() { HYPR_V="$1" BAR_V="$2" python3 "$L/bin/prime-bar" --print top; }
has() { python3 -c "import json,sys; sys.exit(0 if '$2' in json.load(open('$1')) else 1)"; }
opt() { python3 -c "import json; print(json.load(open('$1')).get('$2',{}).get('$3',''))"; }

echo "== Hyprland 0.57 with waybar 0.15.0: the click is broken, so swap the module"
bar 0.57.0 0.15.0 > "$T/057.json"
ck "ext/workspaces replaces hyprland/workspaces" "has $T/057.json ext/workspaces && ! has $T/057.json hyprland/workspaces"
ck "it is the module the bar lists, in place" \
   "python3 -c \"import json; m=json.load(open('$T/057.json'))['modules-left']; assert 'ext/workspaces' in m and 'hyprland/workspaces' not in m\""
ck "clicking a dot activates that workspace" "[ \"\$(opt $T/057.json ext/workspaces on-click)\" = activate ]"
ck "the minimised-windows desktop is not a dot" \
   "python3 -c \"import json; assert json.load(open('$T/057.json'))['ext/workspaces']['ignore-hidden'] is True\""
ck "the dots stay in number order, not creation order" \
   "python3 -c \"import json; m=json.load(open('$T/057.json'))['ext/workspaces']; assert m['sort-by-name'] is True and m['sort-by-id'] is False\""
ck "scrolling and right-click still go through prime-hypr" \
   "opt $T/057.json ext/workspaces on-scroll-up | grep -q prime-hypr && opt $T/057.json ext/workspaces on-click-right | grep -q prime-context"
ck "the dots stay dots, not names" "[ \"\$(opt $T/057.json ext/workspaces format)\" = '{icon}' ]"
ck "the right-click menu is still bar.workspaces" \
   "HYPR_V=0.57.0 BAR_V=0.15.0 python3 $L/bin/prime-bar --keys --list | grep -q '^bar.workspaces'"

echo "== Hyprland 0.56: nothing is broken there, so nothing changes"
bar 0.56.2 0.15.0 > "$T/056.json"
ck "the shipped hyprland/workspaces is left alone" "has $T/056.json hyprland/workspaces && ! has $T/056.json ext/workspaces"

echo "== once waybar ships Alexays/Waybar#5013, the workaround retires itself"
bar 0.57.0 0.16.0 > "$T/new.json"
ck "waybar 0.16 on 0.57: back to hyprland/workspaces" "has $T/new.json hyprland/workspaces && ! has $T/new.json ext/workspaces"
bar '' '' > "$T/unknown.json"
ck "versions it cannot read: the shipped bar, untouched" "has $T/unknown.json hyprland/workspaces"

echo "== a bar that drew its own dots gets real workspaces to draw"
mkdir -p "$HOME/.config/waybar"
python3 - "$L/default/waybar/config.jsonc" "$HOME/.config/waybar/config.jsonc" <<'EOF'
import json, re, sys
cfg = json.loads(re.sub(r'(?m)^\s*//.*$', "", open(sys.argv[1]).read()))
cfg["hyprland/workspaces"]["persistent-workspaces"] = {"HDMI-A-1": [6, 7], "*": 2}
json.dump(cfg, open(sys.argv[2], "w"))
EOF
: > "$CALLS"
bar 0.57.0 0.15.0 > "$T/persist.json"
ck "the ones on a named screen become persistent workspaces there" \
   "grep -q 'workspace' $CALLS && grep -q 'monitor:HDMI-A-1' $CALLS && grep -q 'persistent:true' $CALLS"
ck "a plain count becomes persistent workspaces on every screen" \
   "grep -qE '(\[==\[|\")2, persistent:true' $CALLS"
ck "the bar no longer asks waybar to invent them" \
   "python3 -c \"import json; assert 'persistent-workspaces' not in json.load(open('$T/persist.json'))['ext/workspaces']\""

echo
[ "$fail" -eq 0 ] && echo "ALL PASSED" || echo "$fail FAILED"
exit $((fail > 0))
