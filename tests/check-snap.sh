#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"   # never the real home or session (tests/sandbox.sh)
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
ck "the stand-in side bar hides and floats over windows (no gap by the top bar)" "out=\$(HOME='$T' PRIME_SIDE_AUTOHIDE=1 PATH='$T/bin:$PATH' python3 -c 'import importlib.machinery as M,importlib.util as U,json,os;l=M.SourceFileLoader(\"pb\",\"$REPO/layer/bin/prime-bar\");m=U.module_from_spec(U.spec_from_loader(\"pb\",l));l.exec_module(m);os.execvp=lambda *a: print(a[1][2]);m.sys.argv=[\"x\",\"side\"];m.main()') && jq -e '.start_hidden == true and .exclusive == false' \"\$out\""
ck "the dock appears whenever the pointer touches the bottom edge" "bash '$REPO/layer/bin/prime-dock' --args | tr '\\n' ' ' | grep -q -- '-d .*-hd 0 '"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
