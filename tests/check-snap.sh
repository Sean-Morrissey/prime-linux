#!/usr/bin/env bash
# tests/check-snap.sh — Super+arrows snap the window to that side: out of full screen
# first, back into place if it was floating, then moved. A stand-in hyprctl records
# what Hyprland would be asked; nothing real is touched.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
mkdir -p "$T/bin"
cat > "$T/bin/hyprctl" <<STUB
#!/bin/sh
if [ "\$1" = activewindow ]; then cat "$T/win"; exit 0; fi
echo "\$*" >> "$T/calls"
STUB
chmod +x "$T/bin/hyprctl"
snap() { rm -f "$T/calls"; printf '%s' "$1" > "$T/win"; PATH="$T/bin:$PATH" bash "$REPO/layer/bin/prime-snap" "$2"; }

snap '{"floating":false,"fullscreen":0}' l
ck "a tiled window just moves left (becomes the main window)" "[ \"\$(cat '$T/calls')\" = 'dispatch movewindow l' ]"
snap '{"floating":true,"fullscreen":0}' r
ck "a floating window snaps back into place, then moves"      "[ \"\$(cat '$T/calls')\" = \"\$(printf 'dispatch togglefloating\ndispatch movewindow r')\" ]"
snap '{"floating":false,"fullscreen":2}' u
ck "a full-screen window leaves full screen first"            "head -1 '$T/calls' | grep -qx 'dispatch fullscreen 0' && tail -1 '$T/calls' | grep -qx 'dispatch movewindow u'"
snap '{"floating":false,"fullscreen":1}' d
ck "a maximised window is un-maximised first"                 "head -1 '$T/calls' | grep -qx 'dispatch fullscreen 1'"
snap '{}' l
ck "no window: nothing happens"                               "[ ! -e '$T/calls' ]"
ck "a wrong direction is refused"                             "! PATH='$T/bin:$PATH' bash '$REPO/layer/bin/prime-snap' sideways"
ck "Super+arrows snap and Super+F toggles full screen"        "grep -q 'SUPER, left,.*prime-snap l' '$REPO/layer/default/hypr/bindings.conf' && grep -q 'SUPER, F, .*fullscreen, 0' '$REPO/layer/default/hypr/bindings.conf'"
ck "main window left, new ones share the right half"          "grep -q 'layout = master' '$REPO/layer/default/hypr/looknfeel.conf' && grep -q 'new_status = slave' '$REPO/layer/default/hypr/looknfeel.conf' && grep -q 'mfact = 0.5\$' '$REPO/layer/default/hypr/looknfeel.conf'"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
