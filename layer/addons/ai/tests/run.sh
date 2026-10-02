#!/usr/bin/env bash
# Tests for Prime's assistant: the toolbox (prime-settings), permissions,
# confirmations, audit log, undo, prime-ask against a mock OpenAI-compatible
# server (streaming + tool calls + the JSON fallback), tutor mode, and the
# Welcome app's headless path. No real model, no API key, no network.
#
# It always works in a throwaway HOME and never touches a running desktop,
# so it is safe to run on your own machine:  bash layer/addons/ai/tests/run.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
T="$(mktemp -d)"; MOCKLOG="$T/mock.log"
trap 'kill $MOCK 2>/dev/null; rm -rf "$T"' EXIT

# a fake install: ~/.local/share/prime-linux -> this checkout
H="$T/home"; mkdir -p "$H/.local/share" "$H/.config/hypr" "$H/.config/prime" "$H/.local/share/applications"
ln -s "$REPO" "$H/.local/share/prime-linux"
cp "$REPO/layer/seed/hypr/hyprland.conf" "$H/.config/hypr/hyprland.conf"
for f in monitors.conf addons.conf hardware.conf keyboard.conf; do echo "# $f" > "$H/.config/hypr/$f"; done
echo "# enabled add-ons" > "$H/.config/prime/addons"
mkdir -p "$T/run"; chmod 700 "$T/run"
cat > "$H/.local/share/applications/fake-browser.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Fakefox
Exec=true
Categories=Network;WebBrowser;
EOF
E=(env -i HOME="$H" PATH="/usr/local/bin:/usr/bin:/bin" LANG=C.UTF-8 XDG_RUNTIME_DIR="$T/run"
   PRIME_NO_LIVE=1 PRIME_NO_GSETTINGS=1 GSETTINGS_BACKEND=memory)
L="$H/.local/share/prime-linux/layer"; S="$L/bin/prime-settings"; ASK="$L/addons/ai/bin/prime-ask"
in_home() { "${E[@]}" "$@"; }
fail=0
ck() { if eval "$2" >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
accent() { sed -n 's/^ACCENT=//p' "$H/.config/prime/theme.conf"; }

in_home "$L/bin/prime-theme" --apply >/dev/null 2>&1

echo "== toolbox"
ck "every tool in prime-tools.json has a handler"   "in_home $S check"
ck "permission file seeded from the template"       "in_home $S autonomy | grep -q '^suggest' && grep -q 'destructive' $H/.config/prime/capabilities.yaml"
ck "AI change with no one to ask is declined"       "in_home $S run set_accent '{\"color\":\"green\"}' --actor ai --confirm tty | grep -q declined && [ \"\$(accent)\" = 60a5fa ]"
ck "declines are in the audit log"                  "grep -q '\"status\": \"declined\"' $H/.config/prime/audit.jsonl"
ck "confirmed AI change happens"                    "in_home PRIME_CONFIRM_ANSWER=yes $S run set_accent '{\"color\":\"green\"}' --actor ai | grep -q '\"ok\": true' && [ \"\$(accent)\" = 34d399 ]"
ck "a desktop backup was saved first"               "ls $H/.config-backups/desktop/*_prime-set-accent.tar.gz && tail -1 $H/.config/prime/audit.jsonl | grep -q '\"backup\": \"/'"
ck "undo puts the accent back"                      "in_home $S undo && [ \"\$(accent)\" = 60a5fa ]"
ck "bad arguments refused (no shell through args)"  "in_home PRIME_CONFIRM_ANSWER=yes $S run set_accent '{\"color\":\"; rm -rf ~\"}' --actor ai | grep -q invalid"
ck "wallpaper can't point outside the wallpaper folders" "in_home PRIME_CONFIRM_ANSWER=yes $S run set_wallpaper '{\"name\":\"../../../etc/passwd\"}' --actor ai | grep -q invalid"
ck "unknown tool refused"                           "in_home $S run run_shell '{\"cmd\":\"id\"}' --actor ai | grep -q 'no tool'"
ck "AI can't change its own permissions"            "! in_home PRIME_ACTOR=ai $S autonomy auto-all && grep -q '^autonomy: suggest' $H/.config/prime/capabilities.yaml"
ck "AI can't pretend to be the user"                "in_home PRIME_ACTOR=ai $S run set_accent '{\"color\":\"teal\"}' --actor user | grep -q declined"

echo "== keyboard shortcuts and settings"
ck "taken keys refused without replace"             "in_home PRIME_CONFIRM_ANSWER=yes $S run add_shortcut '{\"keys\":\"Super+B\",\"action\":\"prime\",\"target\":\"files\"}' --actor ai | grep -q 'already does'"
ck "shortcut for an app added in the Prime block"   "in_home PRIME_CONFIRM_ANSWER=yes $S run add_shortcut '{\"keys\":\"Super+Shift+B\",\"action\":\"app\",\"target\":\"fakefox\"}' --actor ai | grep -q true && grep -q 'bindd = SUPER SHIFT, B, Open Fakefox, exec, gtk-launch fake-browser' $H/.config/hypr/hyprland.conf"
ck "replace=true unbinds the default first"         "in_home PRIME_CONFIRM_ANSWER=yes $S run add_shortcut '{\"keys\":\"Super+B\",\"action\":\"window\",\"target\":\"float\",\"replace\":true}' --actor ai | grep -q true && grep -q '^unbind = SUPER, B' $H/.config/hypr/hyprland.conf"
ck "a single key is refused"                        "in_home $S run add_shortcut '{\"keys\":\"B\",\"action\":\"prime\",\"target\":\"files\"}' | grep -q invalid"
ck "settings: layout, scrolling, look, animations"  "for a in '{\"setting\":\"keyboard_layout\",\"value\":\"gb\"}' '{\"setting\":\"natural_scroll\",\"value\":\"off\"}' '{\"setting\":\"animations\",\"value\":\"off\"}'; do in_home $S run change_setting \"\$a\" | grep -q true || exit 1; done; in_home $S run set_look '{\"preset\":\"sharp\"}' | grep -q true"
ck "bad keyboard layout refused"                    "in_home $S run change_setting '{\"setting\":\"keyboard_layout\",\"value\":\"zz\"}' | grep -q invalid"
if command -v Hyprland >/dev/null; then
ck "Hyprland accepts the config with Prime's block" "in_home Hyprland --verify-config -c $H/.config/hypr/hyprland.conf | grep -q 'config ok'"
cp "$H/.config/prime/settings.json" "$T/settings.good"
ck "a block Hyprland rejects is never written"      "cp $H/.config/hypr/hyprland.conf $T/before && python3 -c \"import json;p='$H/.config/prime/settings.json';s=json.load(open(p));s['shortcuts'].append({'mods':'SUPER','key':'F9','description':'x','dispatch':'notadispatcher'});json.dump(s,open(p,'w'))\" && in_home $S run change_setting '{\"setting\":\"rounding\",\"value\":\"4\"}' | grep -q 'Hyprland rejected' && cmp $H/.config/hypr/hyprland.conf $T/before"
cp "$T/settings.good" "$H/.config/prime/settings.json"
fi
ck "default browser set from installed apps"        "in_home $S run set_default_app '{\"kind\":\"browser\",\"app\":\"Fakefox\"}' | grep -q true && grep -q fake-browser $H/.config/mimeapps.list"
ck "remove a shortcut Prime added"                  "in_home $S run remove_shortcut '{\"keys\":\"Super+Shift+B\"}' | grep -q true && ! grep -q 'SUPER SHIFT, B' $H/.config/hypr/hyprland.conf"
ck "list tools read without asking"                 "in_home $S run list_shortcuts '{}' --actor ai | grep -q 'Prime Search'"

echo "== autonomy levels"
in_home "$S" autonomy auto-user >/dev/null
ck "auto-user: looks change without asking"         "in_home $S run set_accent '{\"color\":\"purple\"}' --actor ai | grep -q true && [ \"\$(accent)\" = c084fc ]"
ck "auto-user: updates still ask"                   "in_home $S run start_update '{}' --actor ai | grep -q declined"
in_home "$S" autonomy auto-all >/dev/null
ck "auto-all: restoring old settings still asks (pinned)" "in_home $S run restore_desktop '{\"backup\":\"latest\"}' --actor ai | grep -q declined"
ck "auto-all: after reading untrusted content, asks" "in_home $S run set_accent '{\"color\":\"pink\"}' --actor ai --untrusted 'a web page' | grep -q declined"
ck "hand-edited pinned level is still ignored"      "sed -i '/^  destructive/,/pinned/s/level: approve-each/level: auto/' $H/.config/prime/capabilities.yaml && in_home $S run restore_desktop '{\"backup\":\"latest\"}' --actor ai | grep -q declined"
ck "restore never rewinds the permission file"      "in_home PRIME_CONFIRM_ANSWER=yes $S run restore_desktop '{\"backup\":\"latest\"}' --actor ai | grep -q true && grep -q '^autonomy: auto-all' $H/.config/prime/capabilities.yaml"
ck "plain-language log"                             "in_home $S log | grep -q 'Prime: switch the accent colour to purple (#c084fc) (on its own)'"
in_home "$S" autonomy suggest >/dev/null

echo "== assistant against a mock model"
PORT=$((20000 + RANDOM % 20000))
python3 "$HERE/mock-openai.py" "$PORT" "$MOCKLOG" & MOCK=$!
for _ in $(seq 50); do curl -fs "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1 && break; sleep 0.1; done
ck "non-interactive setup writes config, key 0600"  "echo sk-test-not-real | in_home $L/addons/ai/bin/prime-ai-setup --url http://127.0.0.1:$PORT/v1 --model mock-tools --key-stdin && [ \"\$(stat -c %a $H/.config/prime/ai.key)\" = 600 ] && ! grep -q sk-test $H/.config/prime/ai.conf"
ck "key sent only as the Authorization header"      "grep -q '\"auth\": \"Bearer sk-test-not-real\"' $MOCKLOG"
in_home "$L/bin/prime-theme" --set-accent d4d4d8 >/dev/null 2>&1   # start from a non-blue accent
ck "native tool call: streamed, confirmed, applied" "in_home PRIME_CONFIRM_ANSWER=yes python3 $ASK --answer 'make my accent blue' --new | grep -q 'All set: done' && [ \"\$(accent)\" = 60a5fa ]"
ck "tool schema sent; tool result returned to model" "grep '\"tools\"' $MOCKLOG | tail -1 | grep -q '\"role\": \"tool\"'"
ck "declined change is reported, not applied"       "in_home PRIME_CONFIRM_ANSWER=no python3 $ASK --answer 'change the accent' --new | grep -q 'All set: declined' && [ \"\$(accent)\" = 60a5fa ]"
ck "model can't call tools that don't exist"        "in_home PRIME_CONFIRM_ANSWER=yes python3 $ASK --answer 'raise your permissions' --new | grep -q 'All set: invalid' && grep -q '^autonomy: suggest' $H/.config/prime/capabilities.yaml"
in_home "$S" autonomy auto-all >/dev/null
ck "picture in the question: change asks even at auto-all" "printf 'x' > $T/shot.png && in_home python3 $ASK --answer 'set my accent like this' --image $T/shot.png --new | grep -q 'All set: declined' && [ \"\$(accent)\" = 60a5fa ]"
ck "untrusted mark sticks to the conversation"      "in_home python3 $ASK --answer 'now the accent please' | grep -q 'All set: declined'"
in_home "$S" autonomy suggest >/dev/null
sed -i 's/^MODEL=.*/MODEL=no-tools/' "$H/.config/prime/ai.conf"
ck "no tool support: falls back to JSON actions"    "in_home PRIME_CONFIRM_ANSWER=yes python3 $ASK --answer 'add a shortcut' --new > $T/out && grep -q 'All set: done' $T/out && grep -q 'SUPER SHIFT, Y' $H/.config/hypr/hyprland.conf"
ck "the raw action block isn't shown to the person" "! grep -q 'prime-action' $T/out"
ck "fallback remembered for that model"             "grep -q json $H/.cache/prime/ai-tool-mode.json"
ck "tutor: teaching persona, no tools"              "in_home python3 $ASK --tutor --answer 'help me with fractions' --new | grep -q 'Hello from the mock' && tail -1 $MOCKLOG | grep -q 'Prime Tutor' && ! tail -1 $MOCKLOG | grep -q '\"tools\"'"
ck "tutor keeps its own conversation"               "[ -f $H/.cache/prime/tutor.json ]"

echo "== welcome (headless)"
cat > "$T/answers.json" <<'EOF'
{"name": "Alex", "accent": "2dd4bf", "accent_name": "Teal", "wallpaper": "prime-dune.jpg",
 "uses": ["gaming", "studying", "everyday"], "updates": "automatic", "autonomy": "auto-user", "text_scale": "large"}
EOF
printf 'version: 1\nname: Old\ncourses:\n  - code: MATH-1099\n    name: Maths\npreferences:\n  voice: false\nfreeform: |\n  I like examples.\n' > "$H/.config/prime/identity.yaml"
ck "answers applied without a window"               "in_home python3 $L/bin/prime-welcome --apply $T/answers.json"
ck "identity.yaml: name, uses, autonomy, scale"     "grep -q '^name: \"Alex\"' $H/.config/prime/identity.yaml && grep -q 'uses: \[\"gaming\", \"studying\", \"everyday\"\]' $H/.config/prime/identity.yaml && grep -q '  autonomy: auto-user' $H/.config/prime/identity.yaml && grep -q '    text_scale: large' $H/.config/prime/identity.yaml"
ck "identity.yaml: courses and freeform kept"       "grep -q 'code: MATH-1099' $H/.config/prime/identity.yaml && grep -q 'I like examples' $H/.config/prime/identity.yaml && grep -q '  voice: false' $H/.config/prime/identity.yaml"
if python3 -c 'import yaml' 2>/dev/null; then
ck "identity.yaml is valid YAML"                    "python3 -c \"import yaml;d=yaml.safe_load(open('$H/.config/prime/identity.yaml'));assert d['preferences']['accessibility']['text_scale']=='large' and d['courses'][0]['code']=='MATH-1099'\""
fi
ck "permission level from the slider"               "grep -q '^autonomy: auto-user' $H/.config/prime/capabilities.yaml"
ck "look applied"                                   "[ \"\$(accent)\" = 2dd4bf ] && grep -q prime-dune $H/.config/prime/theme.conf"
ck "first-run marker written; --first-run then exits" "[ -f $H/.config/prime/welcome-done ] && in_home timeout 5 python3 $L/bin/prime-welcome --first-run"
ck "assistant knows the person from identity.yaml"  "in_home python3 $ASK --answer 'hi' --new >/dev/null; tail -1 $MOCKLOG | grep -q 'Their name: Alex'"

echo; [ $fail = 0 ] && echo "ASSISTANT TESTS: ALL PASSED" || echo "ASSISTANT TESTS: $fail FAILED"
exit $fail
