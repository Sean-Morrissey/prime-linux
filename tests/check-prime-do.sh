#!/usr/bin/env bash
# tests/check-prime-do.sh — Prime does everyday requests without AI (prime-do), Spotlight
# shows them first, the Ask box tries them before the model, and a screenshot never
# asks anything before it is saved (prime-snip). Throwaway HOME, fake capture tools.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; fail=0
DO="$REPO/layer/bin/prime-do"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
top() { python3 "$DO" --match "$1" | head -1 | cut -f1,3; }

# ── plain words → the right action, every word understood ──────────────────
while IFS='|' read -r phrase want; do
    got="$(top "$phrase")"
    ck "\"$phrase\" → $want" "[ '$got' = '$want	1.0' ]"
done <<'EOF'
wifi off|wifi-off
please turn on the wi-fi|wifi-on
louder|vol-up
turn the volume down|vol-down
mute|mute
mic off|mic-off
do not disturb|dnd-on
turn off do not disturb|dnd-off
make the text bigger|text-bigger
make it purple|accent-purple
mouse settings|page-mouse
graphics driver|page-graphics
take a screenshot|snip
screenshot the whole screen|snip-full
something's wrong|doctor
get a file back|file-back
empty the trash|trash
undo the last update|update-undo
keep awake|awake-on
restart|power
airplane mode|airplane-on
connect headphones|bt-connect
tidy windows|layout-tidy
stop tiling windows|layout-free
EOF
ck "a real question is not an action"          "[ -z \"\$(top 'what is the capital of france')\" ]"
ck "an unknown request says so (exit 3), does nothing" \
   "PRIME_DO_DRY=1 python3 '$DO' 'write my essay' | grep -q \"don't know\"; [ \${PIPESTATUS[0]} = 3 ]"
ck "a known one runs its command (dry run)"     "PRIME_DO_DRY=1 python3 '$DO' 'wifi off' | grep -q '^DO nmcli radio wifi off'"
ck "restart / shut down only open the power menu" \
   "PRIME_DO_DRY=1 python3 '$DO' 'shut down' | grep -q 'prime-power-menu'"
missing=""
while IFS=$'\t' read -r iid _t; do
    PRIME_DO_DRY=1 python3 "$DO" --id "$iid" | head -1 | grep -q '^DO ' || missing="$missing $iid"
done < <(python3 "$DO" --list)
ck "every action has a command${missing:+ (not:$missing)}" "[ -z '$missing' ]"
bad=""
for b in $(python3 - "$DO" <<'PY'
import importlib.machinery, importlib.util, os, sys
l = importlib.machinery.SourceFileLoader("d", sys.argv[1]); s = importlib.util.spec_from_loader("d", l)
m = importlib.util.module_from_spec(s); l.exec_module(m)
for i in m.INTENTS:
    c = i[4][0] if i[4][0] != "sh" else i[4][2].split()[0]
    print(c)
PY
); do
    case "$b" in /*) [ -x "$b" ] || bad="$bad $(basename "$b")" ;; esac
done
ck "every Prime tool an action runs exists${bad:+ (missing:$bad)}" "[ -z '$bad' ]"
ck "the programs actions use are in the package list" \
   "for p in networkmanager bluez-utils wireplumber brightnessctl gnome-software; do grep -qx \$p '$REPO/os/arch/packages.txt' || exit 1; done"

# ── Spotlight shows them first, the Ask box tries them first ───────────────
ck "Spotlight: \"wifi off\" is the Top Hit, under Do it" \
   "grep -q 'lambda r: r\[0\] == \"do\" and r\[3\] == \"sure\"' '$REPO/layer/bin/prime-spotlight' && grep -q '\"do\": \"Do it\"' '$REPO/layer/bin/prime-spotlight'"
ck "Spotlight runs the action by its id"       "grep -q '\"prime-do\"), \"--id\", payload' '$REPO/layer/bin/prime-spotlight'"
ck "the Ask box does known requests without the model" "grep -q 'just_do(q)' '$REPO/layer/addons/ai/bin/prime-ask'"

# ── screenshots: saved and copied first; the next step is offered, not asked ─
F="$T/bin"; H="$T/home"; mkdir -p "$F" "$H/.config/prime" "$H/.config/hypr" "$H/Pictures"; : > "$H/.config/hypr/hyprland.conf"
cat > "$F/grim" <<'EOF'
#!/bin/sh
for a; do last="$a"; done; printf 'PNG' > "$last"
EOF
printf '#!/bin/sh\necho "0,0 10x10"\n' > "$F/slurp"
printf '#!/bin/sh\ncat > "%s/clip"\n' "$T" > "$F/wl-copy"
cat > "$F/notify-send" <<EOF
#!/bin/sh
[ "\$1" = --help ] && { echo "  -A, --action=[NAME=]Text..."; exit 0; }
echo "\$*" >> "$T/notes"
case "\$*" in *--action*) cat "$T/pick" 2>/dev/null ;; esac
EOF
printf '#!/bin/sh\necho "$*" > "%s/opened"\n' "$T" > "$F/xdg-open"
chmod +x "$F"/*
snip() { rm -f "$T/notes" "$T/clip" "$T/opened"; HOME="$H" XDG_RUNTIME_DIR="$T" PATH="$F:$PATH" timeout 20 bash "$REPO/layer/bin/prime-snip" area; }
shots() { find "$H/Pictures/Screenshots" -name 'snip_*.png' 2>/dev/null | wc -l; }

: > "$T/pick"; snip
ck "default: saved and copied before anything is offered" "[ \$(shots) -ge 1 ] && [ -s '$T/clip' ]"
ck "default: the notification offers Edit, Show and Delete" \
   "grep -q -- '--action=edit=Edit' '$T/notes' && grep -q -- '--action=show=Show in folder' '$T/notes' && grep -q -- '--action=delete=Delete' '$T/notes'"
ck "no AI pack: no Ask Prime button"               "! grep -q 'Ask Prime' '$T/notes'"
ck "ignoring it keeps the screenshot"              "[ \$(shots) -ge 1 ]"
n=$(shots); echo delete > "$T/pick"; snip
ck "Delete removes that screenshot only"           "[ \$(shots) = $n ]"
echo show > "$T/pick"; snip
ck "Show in folder opens Pictures › Screenshots"   "grep -q 'Pictures/Screenshots' '$T/opened'"
echo '{"settings": {"after_screenshot": "save"}}' > "$H/.config/prime/settings.json"; : > "$T/pick"; snip
ck "\"just save and copy\": no buttons at all"     "[ -s '$T/clip' ] && ! grep -q -- '--action' '$T/notes'"
echo ai > "$H/.config/prime/addons"
mkdir -p "$T/layer"; cp -r "$REPO/layer/bin" "$REPO/layer/addons" "$T/layer/"
printf '#!/bin/sh\necho "$*" > "%s/asked"\n' "$T" > "$T/layer/addons/ai/bin/prime-ask"; chmod +x "$T/layer/addons/ai/bin/prime-ask"
asnip() { rm -f "$T/notes" "$T/asked"; HOME="$H" XDG_RUNTIME_DIR="$T" PATH="$F:$PATH" timeout 20 bash "$T/layer/bin/prime-snip" area "$@"; }
echo '{"settings": {}}' > "$H/.config/prime/settings.json"; : > "$T/pick"; asnip
ck "with the AI pack the notification offers Ask Prime" "grep -q -- '--action=ask=Ask Prime' '$T/notes'"
echo ask > "$T/pick"; asnip
ck "pressing Ask Prime hands the picture to Prime"  "grep -q -- '--image .*snip_' '$T/asked'"
: > "$T/pick"; asnip --ask
ck "Super+Alt+A (--ask) asks at once, no buttons"   "grep -q -- '--image' '$T/asked' && ! grep -q -- '--action' '$T/notes'"
echo '{"settings": {"after_screenshot": "ask"}}' > "$H/.config/prime/settings.json"; asnip
ck "\"always ask Prime\" asks without buttons"     "grep -q -- '--image' '$T/asked'"
ck "after_screenshot is a toolbox setting (undoable)" \
   "HOME='$H' '$REPO/layer/bin/prime-settings' run change_setting '{\"setting\":\"after_screenshot\",\"value\":\"buttons\"}' | grep -q '\"ok\": true'"
ck "a nonsense value is refused" \
   "HOME='$H' '$REPO/layer/bin/prime-settings' run change_setting '{\"setting\":\"after_screenshot\",\"value\":\"x\"}' | grep -q '\"ok\": false'"

echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
