#!/usr/bin/env bash
# tests/check-checkup.sh — the daily checkup (prime-doctor --daily, prime-checkup.timer):
# a full disk, failed services and desktop version jumps are reported in words, and a
# problem you've already been told about isn't repeated every day. Fake pacman,
# systemctl, df and notify-send on PATH; a throwaway HOME. No display, no root.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; L="$REPO/layer"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if eval "$2" >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -5; fail=$((fail+1)); fi; }
mkdir -p "$T/bin" "$T/home" "$T/fix"
cat > "$T/bin/pacman" <<'F'
#!/usr/bin/env bash
[ "$1" = -Q ] && [ -n "${2:-}" ] && { v="$(sed -n "s/^$2 //p" "$FIX/versions")"; [ -n "$v" ] && echo "$2 $v" && exit 0; }
exit 1
F
cat > "$T/bin/systemctl" <<'F'
#!/usr/bin/env bash
case " $* " in
  *" --failed "*) if [ "$1" = --user ]; then cat "$FIX/failed-user" 2>/dev/null; else cat "$FIX/failed-system" 2>/dev/null; fi ;;
  *" show "*)     for a; do last="$a"; done; echo "Description of $last" ;;
  *) exit 1 ;;
esac
F
cat > "$T/bin/df" <<'F'
#!/usr/bin/env bash
[ -f "$FIX/df" ] && { cat "$FIX/df"; exit 0; }
exec /usr/bin/df "$@"
F
printf '#!/usr/bin/env bash\necho "$*" >> "$FIX/notified"\n' > "$T/bin/notify-send"
chmod +x "$T/bin/"*
export FIX="$T/fix" HOME="$T/home" PATH="$T/bin:$PATH" PRIME_NO_GSETTINGS=1 PRIME_NO_LIVE=1
unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR
doc() { bash "$L/bin/prime-doctor" "$@" 2>&1; }
notes() { cat "$FIX/notified" 2>/dev/null | wc -l; }

printf 'hyprland 0.51.1-1\nwaybar 0.13.0-2\n' > "$FIX/versions"
ck "the first check records versions, says nothing about them" "! doc | grep -q 'Updated since the last check'"
printf 'hyprland 0.52.0-1\nwaybar 0.13.0-3\n' > "$FIX/versions"
ck "a version jump is told once, in words"      "doc | grep -q 'Updated since the last check: hyprland 0.51 → 0.52'"
ck "…and not again once it's been told"         "! doc | grep -q 'Updated since the last check'"
ck "a package rebuild (same version) is not a jump" "grep -qx 'waybar 0.13' $T/home/.local/state/prime/versions"

printf 'prime-bar@top.service loaded failed failed Prime bar\n' > "$FIX/failed-user"
printf 'cups.service loaded failed failed CUPS\n' > "$FIX/failed-system"
ck "a failed desktop part needs you"            "doc | grep -q 'A part of the desktop stopped: Description of prime-bar@top.service'"
ck "a failed system service is a tip, named"    "doc | grep -q 'A background service stopped: Description of cups.service (cups.service)'"
rm -f "$FIX/failed-user" "$FIX/failed-system"

printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/x 100000000 99000000 1000000 99%% /\n' > "$FIX/df"
ck "an almost full disk needs you, in GB"       "doc | grep -q 'almost full (0 GB free)'"
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/x 100000000 92000000 8000000 92%% /\n' > "$FIX/df"
ck "a filling disk is a tip"                    "doc | grep -q 'getting full (7 GB free)'"
rm -f "$FIX/df"

: > "$FIX/notified"; printf 'cups.service loaded failed failed CUPS\nprime-x.service loaded failed failed X\n' > "$FIX/failed-user"
doc --daily >/dev/null; first=$(notes)
ck "the daily check tells you about a problem"  "[ $first -ge 1 ]"
doc --daily >/dev/null
ck "…and stays quiet the next day if nothing changed" "[ \$(notes) = $first ]"
printf 'prime-y.service loaded failed failed Y\n' >> "$FIX/failed-user"
doc --daily >/dev/null
ck "…but speaks up when something new goes wrong" "[ \$(notes) -gt $first ]"
ck "the timer is part of the desktop session"   "grep -q prime-checkup.timer $L/systemd/prime-session.target && grep -q 'prime-doctor --daily' $L/systemd/prime-checkup.service"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
