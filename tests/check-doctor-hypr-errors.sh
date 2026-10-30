#!/usr/bin/env bash
# tests/check-doctor-hypr-errors.sh — a window setting the compositor quietly
# dropped is the quietest way for the desktop to stop doing something, so
# Check and fix (prime-doctor) has to ask about it.
#
# Hyprland 0.57+ reads Lua, so Prime's .conf files go through prime.lua; a line
# it can't translate is skipped and the rest carries on. prime.lua records those
# in $XDG_RUNTIME_DIR/prime-hypr-errors and shows one notification at login —
# which nobody is there to read. These check the doctor says so afterwards.
#
# Fake hyprctl, systemctl, busctl and friends on PATH; a throwaway HOME. No
# display, no root, nothing touches the running desktop.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; L="$REPO/layer"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if eval "$2" >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -4; fail=$((fail+1)); fi; }
mkdir -p "$T/bin" "$T/home" "$T/run" "$T/fix"; chmod 700 "$T/run"

# a session that is healthy in every way except the one under test
cat > "$T/bin/hyprctl" <<'F'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "version -j") printf '{"tag":"v%s"}\n' "$HYPR_V" ;;
  "version "*)  printf 'Hyprland %s\n' "$HYPR_V" ;;
  "plugin list") echo "Plugin hyprbars by Vaxry:" ;;
  "configerrors"*) ;;
  *) ;;
esac
F
printf '#!/usr/bin/env bash\ncase " $* " in *" is-active "*) exit 0 ;; *" --failed "*) ;; *" show "*) echo d ;; esac\nexit 0\n' > "$T/bin/systemctl"
printf '#!/usr/bin/env bash\necho "org.kde.StatusNotifierWatcher 1 waybar"\n' > "$T/bin/busctl"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pgrep"
printf '#!/usr/bin/env bash\necho Inter\necho "JetBrainsMono Nerd Font"\n' > "$T/bin/fc-list"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pacman"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/notify-send"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/findmnt"
chmod +x "$T/bin"/*

export HOME="$T/home" XDG_RUNTIME_DIR="$T/run" PATH="$T/bin:$PATH"
# the throwaway HOME carries the XDG dirs with it: without this the tools under
# test read and write the real ~/.config, ~/.local/state and ~/.cache
export XDG_STATE_HOME="$HOME/.local/state" XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache" XDG_DATA_HOME="$HOME/.local/share"
export HYPRLAND_INSTANCE_SIGNATURE=test PRIME_DOCTOR_FORCE=1 PRIME_NO_PANEL=1 PRIME_NO_GSETTINGS=1 PRIME_NO_LIVE=1
unset WAYLAND_DISPLAY DISPLAY PRIME_PANEL
ERR="$XDG_RUNTIME_DIR/prime-hypr-errors"
# prime-hypr caches "does this Hyprland read Lua?" per session — clear it between runs
doc() { rm -f "$XDG_RUNTIME_DIR"/prime-hypr-lua.*; HYPR_V="$1" bash "$L/bin/prime-doctor" 2>&1; }

echo "== Hyprland 0.57: Prime's settings go through the Lua translation"
printf 'workspaceopt: no such thing in 0.57\nblurls = unreadable\n' > "$ERR"
ck "a setting that was dropped needs you"        "doc 0.57.0 | grep -q \"2 of your window settings couldn't be read\""
ck "it says which one, in the person's words"    "doc 0.57.0 | grep -q 'workspaceopt'"
ck "it is a problem, not a passing remark"       "doc 0.57.0 | grep -q 'Needs you'"

: > "$ERR"
ck "nothing dropped: says so, doesn't stay silent" "doc 0.57.0 | grep -q 'Window settings: all of them loaded'"
ck "…and nothing needs you"                        "! doc 0.57.0 | grep -q \"couldn't be read\""

rm -f "$ERR"
ck "no record at all: the loader never ran"      "doc 0.57.0 | grep -q \"Prime's window settings aren't being loaded\""
ck "…and Update everything is offered"           "doc 0.57.0 | grep -qi 'Update everything'"

echo "== Hyprland 0.56: no Lua, no translation, nothing to say"
rm -f "$ERR"
ck "the check stays out of the way"              "! doc 0.56.2 | grep -qE \"window settings (all of them loaded|aren't being loaded)|couldn't be read\""
printf 'stale from an older session\n' > "$ERR"
ck "a leftover file from a 0.57 session is not blamed on 0.56" \
   "! doc 0.56.2 | grep -q \"couldn't be read\""

echo
[ "$fail" -eq 0 ] && echo "ALL PASSED" || echo "$fail FAILED"
exit $((fail > 0))
