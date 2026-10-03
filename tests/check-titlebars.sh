#!/usr/bin/env bash
# tests/check-titlebars.sh — window title bars come back by themselves after a Hyprland
# update: at login, a build that no longer loads is rebuilt without anyone asking.
# Stand-ins for hyprpm, hyprctl and notify-send; nothing is built or downloaded.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
F="$T/bin"; mkdir -p "$F" "$T/home"
cat > "$F/hyprpm" <<EOF
#!/bin/sh
S="$T"
echo "\$*" >> "\$S/calls"
case "\$1" in
  list)   [ -e "\$S/enabled" ] && printf 'Repository hyprland-plugins:\n  Plugin hyprbars\n    enabled: true\n'; [ -e "\$S/added" ] && [ ! -e "\$S/enabled" ] && printf 'Repository hyprland-plugins:\n  Plugin hyprbars\n    enabled: false\n'; exit 0 ;;
  update) sleep "\${SLOW:-0}"; touch "\$S/built"; rm -f "\$S/stale" ;;
  add)    touch "\$S/added" ;;
  enable) touch "\$S/enabled" ;;
  reload) [ -e "\$S/enabled" ] && [ ! -e "\$S/stale" ] && touch "\$S/loaded"; exit 0 ;;
esac
EOF
printf '#!/bin/sh\n[ "$1 $2" = "plugin list" ] && [ -e "%s/loaded" ] && echo "Plugin hyprbars by Vaxry"\nexit 0\n' "$T" > "$F/hyprctl"
printf '#!/bin/sh\necho "$*" >> "%s/notes"\n' "$T" > "$F/notify-send"
chmod +x "$F"/*
tb() { rm -f "$T/calls" "$T/notes" "$T/loaded"; HOME="$T/home" HYPRLAND_INSTANCE_SIGNATURE=test PATH="$F:$PATH" timeout 30 bash "$REPO/layer/bin/prime-titlebars"; }

touch "$T/enabled"; tb
ck "built and loading: login just loads them (nothing rebuilt)" "! grep -q '^update' '$T/calls' && [ -e '$T/loaded' ] && [ ! -s '$T/notes' ]"
touch "$T/stale"; tb
ck "after a Hyprland update the old build doesn't load: rebuilt at login" "grep -q '^update' '$T/calls' && [ -e '$T/loaded' ]"
ck "… and it says why, in words"                                  "grep -q 'Hyprland was updated' '$T/notes' && grep -q 'Window title bars are ready' '$T/notes'"
rm -f "$T/enabled" "$T/added" "$T/stale"; tb
ck "first login: added, enabled, loaded"                          "grep -q '^add' '$T/calls' && grep -q '^enable hyprbars' '$T/calls' && [ -e '$T/loaded' ]"
rm -f "$T/enabled" "$T/added" "$T/stale" "$T/calls" "$T/loaded"
run2() { HOME="$T/home" HYPRLAND_INSTANCE_SIGNATURE=test SLOW=2 PATH="$F:$PATH" timeout 30 bash "$REPO/layer/bin/prime-titlebars" --rebuild; }
run2 & run2 & wait
ck "two builds started together (login + health check) build once"   "[ \$(grep -c '^update' '$T/calls') = 1 ]"
mkdir -p "$T/home/.config/prime"; echo '{"settings":{"titlebars":"off"}}' > "$T/home/.config/prime/settings.json"
rm -f "$T/calls"; tb
ck "switched off in Settings: nothing is built or loaded"            "[ ! -s '$T/calls' ]"
rm -f "$T/home/.config/prime/settings.json"

SW="$T/home/.config/prime/theme/plugins.conf"
rm -f "$T/stale" "$SW"; touch "$T/enabled" "$T/added"; tb
ck "loaded: Hyprland reads the title bars' look"            "grep -q '^source = .*/layer/default/hypr/plugins.conf' '$SW'"
# while a rebuild runs (after a Hyprland update) the look is switched off — no screen of errors
printf '#!/bin/sh\n[ "$1 $2" = "plugin list" ] && [ -e "%s/loaded" ] && echo "Plugin hyprbars by Vaxry"\n[ "$1" = reload ] && cat "%s" >> "%s/during" 2>/dev/null\nexit 0\n' "$T" "$SW" "$T" > "$F/hyprctl"; chmod +x "$F/hyprctl"
touch "$T/stale"; rm -f "$T/during"; tb
ck "a rebuild switches the look off first, then on (no errors while it builds)" "head -1 '$T/during' | grep -q \"aren't loaded\" && tail -1 '$T/during' | grep -q '^source = '"
ck "…and back on once the bars load"                        "grep -q '^source = ' '$SW'"
mkdir -p "$T/home/.config/prime"; echo '{"settings":{"titlebars":"off"}}' > "$T/home/.config/prime/settings.json"; tb
ck "title bars switched off in Settings: their look is off too" "grep -q \"aren't loaded\" '$SW'"
rm -f "$T/home/.config/prime/settings.json"
ck "Hyprland reads the look only through the switch file"  "grep -q '^source = ~/.config/prime/theme/plugins.conf' '$REPO/layer/default/hypr/prime.conf' && ! grep -q '^source = .*layer/default/hypr/plugins.conf' '$REPO/layer/default/hypr/prime.conf'"

echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail
