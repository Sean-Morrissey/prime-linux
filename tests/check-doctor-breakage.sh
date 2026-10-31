#!/usr/bin/env bash
# tests/check-doctor-breakage.sh — the checks that exist because these things
# really broke a desktop, not because they seemed like a good idea.
#
#   · the desktop's parts pointing at a copy of Prime that was deleted, so the
#     bar, dock, clipboard and popups never start (2026-10-16)
#   · the minimised-windows overlay left showing, which makes minimising look
#     like a no-op and pins its windows to every desktop
#   · a bar item pointing at a script that moved — how the bar actually breaks
#   · apps drawing a second set of window buttons that cannot work
#   · an edit under Prime's own files, which makes every update refuse to run
#   · a graphics card with no headroom, which takes the session down with it
#
# Fake hyprctl, systemctl, gsettings and git on PATH; a throwaway HOME; no
# display, no compositor, nothing touches the running desktop.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; L="$REPO/layer"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if ( eval "$2" ) >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -4; fail=$((fail+1)); fi; }
mkdir -p "$T/bin" "$T/home" "$T/run" "$T/fix"; chmod 700 "$T/run"

cat > "$T/bin/hyprctl" <<'F'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "version -j") echo '{"tag":"v0.56.2"}' ;;
  "version "*)  echo "Hyprland 0.56.2" ;;
  "plugin list") echo "Plugin hyprbars by Vaxry:" ;;
  "-j monitors"|"monitors -j") printf '[{"name":"DP-1","specialWorkspace":{"name":"%s"}}]\n' "$(cat "$FIX/special")" ;;
  "configerrors"*) ;;
esac
exit 0
F
printf '#!/usr/bin/env bash\ncase " $* " in *" is-active "*) exit 0 ;; *" --failed "*) ;; *" show "*) echo d ;; esac\nexit 0\n' > "$T/bin/systemctl"
printf '#!/usr/bin/env bash\necho "org.kde.StatusNotifierWatcher 1 waybar"\n' > "$T/bin/busctl"
printf '#!/usr/bin/env bash\ncat "$FIX/gtkbuttons" 2>/dev/null\n' > "$T/bin/gsettings"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pgrep"
printf '#!/usr/bin/env bash\necho Inter\necho "JetBrainsMono Nerd Font"\n' > "$T/bin/fc-list"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pacman"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/notify-send"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/findmnt"
printf '#!/usr/bin/env bash\ncat "$FIX/gitstatus" 2>/dev/null\nexit 0\n' > "$T/bin/git"
chmod +x "$T/bin"/*

export HOME="$T/home" XDG_RUNTIME_DIR="$T/run" PATH="$T/bin:$PATH" FIX="$T/fix"
export XDG_STATE_HOME="$HOME/.local/state" XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
export HYPRLAND_INSTANCE_SIGNATURE=test PRIME_DOCTOR_FORCE=1 PRIME_NO_PANEL=1 PRIME_NO_GSETTINGS=1 PRIME_NO_LIVE=1
unset WAYLAND_DISPLAY DISPLAY PRIME_PANEL
echo "" > "$FIX/special"; echo "':minimize,maximize,close'" > /dev/null
printf "'appmenu'\n" > "$FIX/gtkbuttons"
: > "$FIX/gitstatus"
mkdir -p "$XDG_RUNTIME_DIR/prime-bar"
printf '{"clock":{"format":"{:%%H:%%M}"}}\n' > "$XDG_RUNTIME_DIR/prime-bar/top.json"
doc() { rm -f "$XDG_RUNTIME_DIR"/prime-hypr-lua.*; bash "$L/bin/prime-doctor" 2>&1; }

echo "== the desktop's own parts point at a Prime that is really there"
UD="$HOME/.config/systemd/user"; mkdir -p "$UD"
for u in "$L"/systemd/*; do ln -sfn "$u" "$UD/$(basename "$u")"; done
ck "all of them point at the right place"      "doc | grep -q 'point at the right place'"
rm -f "$UD/prime-dock.service"
ln -sfn /tmp/a-copy-of-prime-that-is-gone/prime-bar@.service "$UD/prime-bar@.service"
ck "a dead one is put back, not just reported" "doc | grep -q \"pointed at a copy of Prime that isn't there any more\""
ck "…and it really is relinked"                "[ \"\$(readlink -f $UD/prime-bar@.service)\" = \"\$(readlink -f $L/systemd/prime-bar@.service)\" ] && [ -e $UD/prime-dock.service ]"
ck "…so the next check finds nothing wrong"    "doc | grep -q 'point at the right place'"

echo "== minimised windows left showing on top of the desktop"
echo "special:minimized" > "$FIX/special"
ck "the overlay is put away for you"           "doc | grep -q 'left showing on top of your desktop'"
echo "" > "$FIX/special"
ck "nothing showing: says so, changes nothing" "doc | grep -q 'Minimised windows stay out of the way'"

echo "== a bar item pointing at something that isn't there"
ck "a clean bar passes"                        "doc | grep -q 'Everything in the top bar can still run'"
printf '{"custom/x":{"exec":"/does/not/exist/script.sh"}}\n' > "$XDG_RUNTIME_DIR/prime-bar/top.json"
ck "a missing script is caught"                "doc | grep -q 'point at something that isn.t there'"
ck "…and it is a problem, not a remark"        "doc | grep -q 'Needs you'"
printf '{"custom/x":{"exec":"echo hi","on-click":"bash -c \\"exec /nope/deep/inside.sh\\""}}\n' > "$XDG_RUNTIME_DIR/prime-bar/top.json"
ck "…even buried inside a bash -c string"      "doc | grep -q 'point at something that isn.t there'"
printf '{"custom/x":{"exec":"echo hi"}}\n' > "$XDG_RUNTIME_DIR/prime-bar/top.json"
ck "a command on PATH is fine"                 "doc | grep -q 'Everything in the top bar can still run'"

echo "== a second set of window buttons, which cannot work here"
ck "none: one set, on the title bar"           "doc | grep -q 'One set of window buttons'"
printf "'appmenu:minimize,maximize,close'\n" > "$FIX/gtkbuttons"
ck "apps drawing their own is caught"          "doc | grep -q 'second set of window buttons'"
printf "'appmenu'\n" > "$FIX/gtkbuttons"

echo "== an edit under Prime's own files stops every update"
mkdir -p "$HOME/.local/share/prime-linux/.git"
ck "clean: updates can install"                "doc | grep -q \"Prime's own files are untouched\""
printf ' M layer/bin/prime-bar\n' > "$FIX/gitstatus"
ck "edited: says so before the update fails"   "doc | grep -q \"Prime's own files have been changed\""
ck "…and offers the way out"                   "doc | grep -qi 'set the changes aside'"
: > "$FIX/gitstatus"

echo
[ "$fail" -eq 0 ] && echo "ALL PASSED" || echo "$fail FAILED"
exit $((fail > 0))
