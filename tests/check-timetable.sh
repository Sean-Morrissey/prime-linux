#!/usr/bin/env bash
# tests/check-timetable.sh — the timetable and reminders (times read from words, a note
# before each class, reminders on time, "remind me…" in Prime Search), the camera check,
# and the disk-encryption advice in Welcome. Throwaway HOME, a pretend clock
# (PRIME_NOW), notifications printed instead of shown, a made-up /sys and /proc.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; L="$REPO/layer"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if ( eval "$2" ) >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -8; fail=$((fail+1)); fi; }
export HOME="$T/home" PRIME_TIMETABLE_DRY=1 PRIME_DO_DRY=1
mkdir -p "$HOME"
TT="$L/bin/prime-timetable"
# Monday 5 October 2026, 08:00
export PRIME_NOW=2026-10-05T08:00

echo "== reading times from words"
when() { python3 "$TT" --remind x "$1" | sed -n 's/^I.ll remind you \(.*\): x$/\1/p'; }
ck "in 20 minutes"        "[ \"\$(when 'in 20 minutes')\" = 'today at 08:20' ]"
ck "at 5pm"               "[ \"\$(when 'at 5pm')\" = 'today at 17:00' ]"
ck "tomorrow at 9"        "[ \"\$(when 'tomorrow at 9')\" = 'tomorrow at 09:00' ]"
ck "friday 3:30pm"        "[ \"\$(when 'friday 3:30pm')\" = 'on Friday 9 October at 15:30' ]"
ck "a time already past today means tomorrow (at 7)" "[ \"\$(when 'at 7')\" = 'tomorrow at 07:00' ]"
ck "\"monday\" on a Monday means next week" "[ \"\$(when 'monday')\" = 'on Monday 12 October at 09:00' ]"
ck "words that aren't a time are refused (soonish, in a month, 25:00)" \
   "! python3 '$TT' --remind x soonish && ! python3 '$TT' --remind x 'in a month' && ! python3 '$TT' --remind x 25:00"
rm -f "$HOME/.config/prime/timetable.json"

echo "== classes and reminders"
mkdir -p "$HOME/.config/prime"
cat > "$HOME/.config/prime/timetable.json" <<'EOF'
{"classes": [{"name": "Maths", "day": 0, "start": "09:00", "end": "10:00", "room": "B12"},
             {"name": "History", "day": 0, "start": "11:00", "end": "12:00", "room": ""},
             {"name": "Art", "day": 2, "start": "09:00", "end": "10:00", "room": "Studio"}],
 "reminders": [{"text": "Hand in the essay", "at": "2026-10-05T08:50", "done": false}],
 "remind_before": 10}
EOF
ck "the next class today, in words"           "[ \"\$(python3 '$TT' --next)\" = 'Maths at 09:00 in B12' ]"
ck "only today's classes (not Wednesday's)"   "[ \"\$(python3 '$TT' --today | tr '\n' '|')\" = 'Maths at 09:00 in B12|History at 11:00|' ]"
ck "10 minutes before Maths: a note with the room" "PRIME_NOW=2026-10-05T08:50 python3 '$TT' --tick | grep -qx 'NOTIFY Maths in 10 minutes | At 09:00, B12'"
ck "…and the reminder due at 08:50 at the same minute" "PRIME_NOW=2026-10-05T08:50 python3 '$TT' --tick | grep -q 'Hand in the essay' || grep -q '\"done\": true' '$HOME/.config/prime/timetable.json'"
ck "a reminder is sent once, not every minute after" "! PRIME_NOW=2026-10-05T08:51 python3 '$TT' --tick | grep -q 'essay'"
ck "nothing at a minute with nothing due"     "[ -z \"\$(PRIME_NOW=2026-10-05T08:30 python3 '$TT' --tick)\" ]"
ck "a missed reminder (computer asleep) comes at the next check" \
   "python3 '$TT' --remind 'Feed the cat' 'at 8:30' >/dev/null && PRIME_NOW=2026-10-05T08:44 python3 '$TT' --tick | grep -q 'Feed the cat'"
ck "notes before classes can be switched off"  "python3 -c \"import json;p='$HOME/.config/prime/timetable.json';d=json.load(open(p));d['remind_before']=0;json.dump(d,open(p,'w'))\" && [ -z \"\$(PRIME_NOW=2026-10-05T10:50 python3 '$TT' --tick)\" ]"
ck "the timetable is private to you"           "[ \"\$(stat -c %a '$HOME/.config/prime/timetable.json')\" = 600 ]"
ck "the check runs every minute with the session" "grep -q 'OnCalendar=\*-\*-\* \*:\*:00' '$L/systemd/prime-timetable.timer' && grep -q prime-timetable.timer '$L/systemd/prime-session.target'"
ck "Timetable is in the app list"              "grep -q '^Name=Timetable' '$L/applications/prime-timetable.desktop'"

echo "== \"remind me …\" in Prime Search (no AI)"
DO="$L/bin/prime-do"
ck "remind me to call mum at 5pm → the Top Hit, with the time" \
   "python3 '$DO' --match 'remind me to call mum at 5pm' | head -1 | grep -qP '^remind:call mum\|at 5pm\tRemind me: call mum — today at 17:00\t1.0$'"
ck "remind me at 9 to bring my PE kit"  "python3 '$DO' --match 'remind me at 9 to bring my PE kit' | grep -q 'Remind me: bring my PE kit — today at 09:00'"
ck "please remind me in 20 minutes to take the pizza out" "python3 '$DO' --match 'please remind me in 20 minutes to take the pizza out' | grep -q 'take the pizza out — today at 08:20'"
ck "a time it can't read isn't a reminder (left to the assistant or the web)" "[ -z \"\$(python3 '$DO' --match 'remind me soonish to x')\" ]"
ck "running it adds the reminder through prime-timetable" "python3 '$DO' --id 'remind:call mum|at 5pm' | grep -q 'prime-timetable --remind call mum at 5pm'"
ck "ordinary requests still work"       "python3 '$DO' --match 'wifi off' | head -1 | grep -q '^wifi-off'"

echo "== the camera check"
S="$T/sys"; mkdir -p "$S/sys/class/video4linux"/{video0,video1,video2} "$S/proc/4242/fd" "$S/proc/4343/fd"
printf 'Integrated Camera\n' > "$S/sys/class/video4linux/video0/name"; echo 0 > "$S/sys/class/video4linux/video0/index"
printf 'Integrated Camera\n' > "$S/sys/class/video4linux/video1/name"; echo 1 > "$S/sys/class/video4linux/video1/index"
printf 'USB Webcam C920\n' > "$S/sys/class/video4linux/video2/name"; echo 0 > "$S/sys/class/video4linux/video2/index"
ln -s /dev/video0 "$S/proc/4242/fd/7"; echo zoom > "$S/proc/4242/comm"
ln -s /dev/null "$S/proc/4343/fd/1"; echo firefox > "$S/proc/4343/comm"
ck "each camera once (its extra metadata node left out), and which app is using one" "PRIME_SYS_ROOT='$S' python3 -c \"
import importlib.machinery as M, importlib.util as U
l = M.SourceFileLoader('s', '$L/bin/prime-system-settings'); m = U.module_from_spec(U.spec_from_loader('s', l)); l.exec_module(m)
assert m.cameras() == [('/dev/video0', 'Integrated Camera'), ('/dev/video2', 'USB Webcam C920')], m.cameras()
assert m.camera_users() == ['zoom'], m.camera_users()\""
ck "no camera: nothing listed, nothing using one" "PRIME_SYS_ROOT='$T/nothing' python3 -c \"
import importlib.machinery as M, importlib.util as U
l = M.SourceFileLoader('s', '$L/bin/prime-system-settings'); m = U.module_from_spec(U.spec_from_loader('s', l)); l.exec_module(m)
assert m.cameras() == [] and m.camera_users() == []\""
ck "Settings has a Camera & Microphone page, found by 'webcam'" "python3 '$L/bin/prime-system-settings' --list-pages | grep -qP '^camera\tCamera & Microphone\t.*webcam'"

echo "== disk encryption advice in Welcome"
wel() { python3 -c "
import importlib.machinery as M, importlib.util as U
l = M.SourceFileLoader('w', '$L/bin/prime-welcome'); m = U.module_from_spec(U.spec_from_loader('w', l)); l.exec_module(m)
$1"; }
ck "an encrypted disk: no advice step"            "PRIME_FAKE_ENCRYPTED=yes PRIME_FAKE_LAPTOP=yes wel 'assert m.encryption_advice() == []'"
ck "an unencrypted laptop: why it matters on a laptop, and how" \
   "PRIME_FAKE_ENCRYPTED=no PRIME_FAKE_LAPTOP=yes wel \"t = [a for a, _ in m.encryption_advice()]; assert t == ['What encryption does', 'Why it matters on a laptop', 'Now is the cheapest time', 'How'], t\""
ck "an unencrypted desktop: it's fine to keep it"  "PRIME_FAKE_ENCRYPTED=no PRIME_FAKE_LAPTOP=no wel \"assert any('fine to keep' in w for _, w in m.encryption_advice())\""
ck "the install guide says to tick Encrypt system" "grep -q 'tick \*\*Encrypt system\*\*' '$REPO/docs/USER-GUIDE.md'"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
