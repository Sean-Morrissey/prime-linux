#!/usr/bin/env bash
# The fast suite: runs on any Linux with python3, bash and jq — no container, no
# install, nothing touches this machine (every write goes to a throwaway HOME).
# The GUI self-tests use the real display, or a virtual one (xvfb-run) when there
# is none; without either they are skipped and say so.
#
#   tests/check-static.sh          (tests/install-in-container.sh is the full install test)
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; L="$REPO/layer"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if eval "$2" >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -8; fail=$((fail+1)); fi; }
# a python that has GTK (the system one; a venv or a newer python may not)
PY=python3
for p in python3 /usr/bin/python3 /usr/bin/python3.14 /usr/bin/python3.13 /usr/bin/python3.12; do
    command -v "$p" >/dev/null && "$p" -c 'import gi; gi.require_version("Gtk", "3.0")' 2>/dev/null && { PY="$p"; break; }
done
GUI=""
if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then GUI=" "
elif command -v xvfb-run >/dev/null; then GUI="xvfb-run -a"; fi

echo "== layer, menus, bar, wording, payload"
python3 "$REPO/tests/check-static.py" || fail=$((fail+1))

echo; echo "== behaviour (throwaway HOME)"
export HOME="$T/home" PRIME_NO_GSETTINGS=1 PRIME_NO_LIVE=1; mkdir -p "$HOME/.config/hypr"
unset HYPRLAND_INSTANCE_SIGNATURE
ck "theme writes every generated file"        "bash $L/bin/prime-theme --apply && for f in colors.css colors.rasi fonts.rasi hyprland.conf hyprlock.conf kitty.conf swaync.css; do [ -s \$HOME/.config/prime/theme/\$f ] || { echo missing \$f; exit 1; }; done"
ck "text size: default ladder"                "grep -q 'prime-font-body: *\"Inter 13\"' \$HOME/.config/prime/theme/fonts.rasi && grep -q 'prime_font_clock = 72' \$HOME/.config/prime/theme/hyprlock.conf"
ck "text size: Larger scales every surface"   "bash $L/bin/prime-theme --set-text larger && grep -q 'prime-font-body: *\"Inter 16.9\"' \$HOME/.config/prime/theme/fonts.rasi && grep -q 'prime_font_clock = 94' \$HOME/.config/prime/theme/hyprlock.conf && grep -q 'prime_titlebar_text = 14' \$HOME/.config/prime/theme/hyprland.conf && grep -q '^TEXT=larger' \$HOME/.config/prime/theme.conf"
ck "text size: a wrong value changes nothing" "! bash $L/bin/prime-theme --set-text huge && grep -q '^TEXT=larger' \$HOME/.config/prime/theme.conf"
ck "text size survives an accent change"      "bash $L/bin/prime-theme --set-accent 60a5fa && grep -q '^TEXT=larger' \$HOME/.config/prime/theme.conf && grep -q 60a5fa \$HOME/.config/prime/theme/colors.css"
ck "health check speaks the window's language" "PRIME_PANEL=1 bash $L/bin/prime-doctor > \$HOME/doc && ! grep -vqE '^@(ok|fix|bad|note|step|action|summary) ' \$HOME/doc && grep -q '^@summary ' \$HOME/doc"
ck "health check offers a button, not a command" "PRIME_PANEL=1 bash $L/bin/prime-doctor | grep '^@bad' | grep -vqiE 'run |prime-|systemctl|journalctl' || ! PRIME_PANEL=1 bash $L/bin/prime-doctor | grep -q '^@bad'"
ck "About lists facts as rows"                "PRIME_PANEL=1 bash $L/bin/prime-about | grep -q '^@row Version	Prime ' && PRIME_PANEL=1 bash $L/bin/prime-about --computer | grep -q '^@row Memory	'"
ck "add-on list says on/off and where to change it" "bash $L/bin/prime-addon | grep -q 'Settings → Apps → Packs and add-ons'"
ck "every bar item is in the keyboard list"   "[ \$(python3 $L/bin/prime-bar --keys --list | wc -l) -ge 15 ] && python3 $L/bin/prime-bar --keys --list | grep -q '^bar.logo	Start'"
ck "old terminal rows open Prime windows"     "grep -q prime-activity $L/bin/prime-float && grep -q prime-wifi $L/bin/prime-float && ! grep -q kitty $L/bin/prime-float"
ck "lock-screen status line is quiet without Caps Lock" "out=\$(bash $L/bin/prime-lock-status); [ -z \"\$out\" ] || [ \"\$out\" = 'Caps Lock is on' ]"

echo; echo "== the lock (prime-lock, with stand-ins for Hyprland, hyprlock and the screen saver)"
LK="$(mktemp -d)"
printf '#!/bin/sh\necho "hyprctl $*" >> %s/log\n' "$LK" > "$LK/hyprctl"
printf '#!/bin/sh\necho "hyprlock" >> %s/log\nsleep 2\n' "$LK" > "$LK/hyprlock"
printf '#!/bin/sh\necho "saver $*" >> %s/log\nexit 1\n' "$LK" > "$LK/saver"
chmod +x "$LK"/*
PATH="$LK:$PATH" PRIME_SAVER="$LK/saver" bash $L/bin/prime-lock >/dev/null 2>&1
ck "shortcuts off, saver, then the password screen, then shortcuts back — even if the saver fails" \
   "[ \"\$(grep -v pidof $LK/log | paste -sd'|')\" = 'hyprctl dispatch submap prime-locked|saver --lock|hyprlock|hyprctl dispatch submap reset' ]"
: > "$LK/log"; PATH="$LK:$PATH" PRIME_SAVER="$LK/saver" bash $L/bin/prime-lock --now >/dev/null 2>&1
ck "going to sleep: straight to the password screen"  "[ \"\$(cat $LK/log)\" = hyprlock ]"
ck "the submap prime-lock uses exists (has a bind)"   "awk '/^submap = prime-locked/{f=1;next} /^submap = reset/{f=0} f && /^bind/' $L/default/hypr/bindings.conf | grep -q ."
rm -rf "$LK"

echo; echo "== windows (GTK)"
if [ -n "$GUI" ]; then
    ck "Prime window: protocol, rows, words, accessible names" "$GUI $PY $L/bin/prime-panel --selftest"
    ck "Spotlight: sources, router, window, accessible names" "PATH=\"\$(dirname \$(command -v $PY)):\$PATH\" $GUI $PY $L/bin/prime-spotlight --selftest"
    ck "Screen saver: frames, drift, wake rules"               "$PY $L/bin/prime-screensaver --selftest"
    ck "Activity lists apps with words for how busy"          "$PY $L/bin/prime-activity --list | grep -qE '(idle|light|busy|very busy)'"
else
    echo "  SKIP  no display and no xvfb-run — the GTK windows weren't built"
fi

echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
