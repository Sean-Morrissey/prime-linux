#!/usr/bin/env bash
# tests/check-window.sh — minimising actually hides the window.
#
# Hyprland has no minimise. The usual stand-in moves the window into a special
# workspace, but a special workspace draws on top of whichever desktop is active
# and Hyprland only hides one once its last window leaves — never when one
# arrives. So minimising while the peek is open leaves the window on screen, and
# it then follows you to every desktop. prime-window closes the overlay after
# every move, which is the whole fix.
#
# A fake hyprctl records what was asked for; a throwaway HOME; no display, no
# compositor, nothing touches the running desktop.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; L="$REPO/layer"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if ( eval "$2" ) >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -4; fail=$((fail+1)); fi; }
mkdir -p "$T/bin" "$T/home" "$T/fix"
export HOME="$T/home" PATH="$T/bin:$PATH" CALLS="$T/calls" FIX="$T/fix"
export XDG_STATE_HOME="$HOME/.local/state" XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache" XDG_DATA_HOME="$HOME/.local/share"
export XDG_RUNTIME_DIR="$HOME/.run"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

# the compositor: $FIX/special says whether the minimised overlay is on screen,
# $FIX/clients is what is minimised right now
cat > "$T/bin/hyprctl" <<'F'
#!/usr/bin/env bash
case " $* " in
  *" monitors "*) printf '[{"focused":true,"activeWorkspace":{"id":3},"specialWorkspace":{"name":"%s"}}]\n' "$(cat "$FIX/special")" ;;
  *" activewindow "*) printf '{"address":"0xaaa"}\n' ;;
  *" clients "*) cat "$FIX/clients" ;;
esac
exit 0
F
printf '#!/usr/bin/env bash\necho "dispatch $*" >> "$CALLS"\n' > "$T/bin/prime-hypr-fake"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/notify-send"
chmod +x "$T/bin"/*
# prime-window calls the prime-hypr next to it, so shadow that one
BINDIR="$T/layerbin"; mkdir -p "$BINDIR"
cp "$L/bin/prime-window" "$BINDIR/"
cp "$T/bin/prime-hypr-fake" "$BINDIR/prime-hypr"; chmod +x "$BINDIR/prime-hypr"
printf '#!/usr/bin/env bash\ncat > "$FIX/offered"\nhead -1 "$FIX/choose" 2>/dev/null\n' > "$BINDIR/prime-rofi"
chmod +x "$BINDIR/prime-rofi"
W="$BINDIR/prime-window"
echo '[]' > "$FIX/clients"; echo "special:minimized" > "$FIX/special"

echo "== minimising"
: > "$CALLS"; bash "$W" minimise >/dev/null 2>&1
ck "the window goes to the minimised desktop"  "grep -q 'movetoworkspacesilent special:minimized,address:0xaaa' $CALLS"
ck "…and the overlay is shut behind it"        "grep -q 'togglespecialworkspace minimized' $CALLS"

echo "none" > "$FIX/special"
: > "$CALLS"; bash "$W" minimise >/dev/null 2>&1
ck "overlay already down: it is left alone"    "! grep -q togglespecialworkspace $CALLS"
: > "$CALLS"; bash "$W" minimise 0xbbb >/dev/null 2>&1
ck "a named window minimises, not the focused one" "grep -q 'address:0xbbb' $CALLS && ! grep -q '0xaaa' $CALLS"

echo "== bringing one back"
echo "special:minimized" > "$FIX/special"
printf '[{"address":"0xaaa","class":"Firefox","title":"A page","workspace":{"name":"special:minimized"}}]\n' > "$FIX/clients"
: > "$CALLS"; bash "$W" restore >/dev/null 2>&1
ck "one minimised window comes straight back"  "grep -q 'movetoworkspacesilent 3,address:0xaaa' $CALLS"
ck "…to the desktop you are on now"            "grep -q ' 3,address' $CALLS"
ck "…the overlay is shut"                      "grep -q 'togglespecialworkspace minimized' $CALLS"
ck "…and it gets the focus"                    "grep -q 'focuswindow address:0xaaa' $CALLS"

printf '[{"address":"0xaaa","class":"Firefox","title":"A page","workspace":{"name":"special:minimized"}},
         {"address":"0xbbb","class":"Files","title":"Home","workspace":{"name":"special:minimized"}}]\n' > "$FIX/clients"
printf '0xbbb  Files — Home\n' > "$FIX/choose"
: > "$CALLS"; bash "$W" restore >/dev/null 2>&1
ck "more than one: you pick, and it says which" "grep -q 0xbbb $FIX/offered && grep -q Firefox $FIX/offered"
ck "…and the one you picked comes back"         "grep -q 'movetoworkspacesilent 3,address:0xbbb' $CALLS"

echo '[]' > "$FIX/clients"
: > "$CALLS"; bash "$W" restore >/dev/null 2>&1
ck "nothing minimised: says so, moves nothing" "[ ! -s $CALLS ]"

echo "== putting a window on another desktop"
printf '[{"address":"0xccc","class":"Steam","title":"Library","workspace":{"id":2}}]\n' > "$FIX/clients"
printf '4  ·  empty\n' > "$FIX/choose"
: > "$CALLS"; bash "$W" send-to >/dev/null 2>&1
ck "the chooser lists every desktop"           "[ \$(grep -c '·' $FIX/offered) = 5 ]"
ck "…says what is on them"                     "grep -q 'Steam' $FIX/offered"
ck "…and marks where you are"                  "grep -q 'you are here' $FIX/offered"
ck "the window moves to the one you picked"    "grep -q 'movetoworkspace 4,address:0xaaa' $CALLS"

echo "== it is wired into the desktop"
ck "Super+minus minimises through it"          "grep -q 'SUPER, minus, Minimise window, exec, \$bin/prime-window minimise' $L/default/hypr/bindings.conf"
ck "the title bar's − button too"              "grep -q 'prime-window minimise' $L/default/hypr/plugins.conf"
ck "bringing one back has a shortcut"          "grep -q 'prime-window restore' $L/default/hypr/bindings.conf"
ck "and every shortcut is described"           "! grep -E '^bindd? = .*prime-window' $L/default/hypr/bindings.conf | grep -qE '^bind = '"

echo
[ "$fail" -eq 0 ] && echo "ALL PASSED" || echo "$fail FAILED"
exit $((fail > 0))
