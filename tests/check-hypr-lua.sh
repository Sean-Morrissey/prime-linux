#!/usr/bin/env bash
# tests/check-hypr-lua.sh — Hyprland 0.57+ (Lua config) gets the same desktop as
# older Hyprland. layer/default/hypr/prime.lua reads Prime's .conf files under plain
# `lua` with a stand-in `hl` that records every call; prime-hypr is run against a
# stand-in hyprctl that claims 0.56 and then 0.57. Nothing touches the session.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

# Hyprland 0.57 embeds Lua 5.5; prime.lua also runs on 5.4 (CI's Ubuntu)
LUA="$(command -v lua || command -v lua5.5 || command -v lua5.4)" ||
  { echo "  SKIP  lua is not installed (Hyprland 0.57 pulls it in)"; exit 0; }

# ── a home like an installed one: Prime's seed hyprland.conf, its layer, a theme ──
H="$T/home"; mkdir -p "$H/.local/share" "$H/.config/hypr" "$H/.config/prime/theme" "$T/run"
ln -s "$REPO" "$H/.local/share/prime-linux"
cp "$REPO/layer/seed/hypr/hyprland.conf" "$REPO/layer/seed/hypr/hyprland.lua" "$H/.config/hypr/"
printf 'monitor = HDMI-A-1, 1920x1080@144, 0x0, 1\n' > "$H/.config/hypr/monitors.conf"
printf 'env = LIBVA_DRIVER_NAME,radeonsi\n' > "$H/.config/hypr/hardware.conf"
printf 'source = %s/layer/addons/gaming/hypr.conf\n' "$REPO" > "$H/.config/hypr/addons.conf"
printf 'input {\n    kb_layout = us,de\n}\n' > "$H/.config/hypr/keyboard.conf"
printf '$accent = rgb(d4d4d8)\n$accent_border = rgba(d4d4d866)\n$prime_titlebar_text = 11\n' > "$H/.config/prime/theme/hyprland.conf"

# stand-in hl: every call is printed as one line; dispatchers are tables naming themselves
cat > "$T/mock.lua" <<'EOF'
local function show(v)
  if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. show(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function rec(name)
  return function(...)
    local s, n = {}, select("#", ...)
    for i = 1, n do s[i] = show((select(i, ...))) end
    print(name .. "(" .. table.concat(s, ",") .. ")")
    return { modmask = 64, key = "x" }
  end
end
local function ns(prefix)
  return setmetatable({}, { __index = function(_, k)
    return function(...) return { dsp = prefix .. k, args = { ... } } end end })
end
local dsp = ns("")
for _, sub in ipairs({ "window", "workspace", "group", "cursor" }) do rawset(dsp, sub, ns(sub .. ".")) end
hl = setmetatable({
  dsp = dsp,
  plugin = { load = rec("plugin.load") },
  notification = { create = rec("notification.create") },
  get_loaded_plugins = function() return {} end,
  define_submap = function(name, fn) print("define_submap(" .. name .. ")"); fn(); print("end_submap") end,
  on = function(ev, fn) print("on(" .. ev .. ")"); fn(); print("end_on") end,
}, { __index = function(_, k) return rec(k) end })
dofile(os.getenv("HOME") .. "/.config/hypr/hyprland.lua")
print("errors=" .. #prime.errors)
for _, e in ipairs(prime.errors) do print("error: " .. e) end
EOF
HOME="$H" XDG_RUNTIME_DIR="$T/run" "$LUA" "$T/mock.lua" > "$T/out" 2>&1
O="$T/out"

echo "== Prime's .conf files read through prime.lua"
ck "every line is understood (no errors)"           "grep -qx 'errors=0' $O"
ck "sections become dotted options"                 "grep -qF 'config({general.gaps_in=6})' $O"
ck "nested sections close properly"                 "grep -qF 'config({decoration.blur.size=8})' $O && grep -qF 'config({dwindle.preserve_split=true})' $O"
ck "\$variables are filled in (theme accent)"       "grep -qF 'colors={1=\"rgba(ffffff44)\",2=\"rgba(d4d4d866)\"}' $O"
ck "a gradient becomes colours + angle"             "grep -qF 'angle=45' $O"
ck "hyphenated keys are renamed (tap-to-click)"     "grep -qF 'input.touchpad.tap_to_click=true' $O"
ck "bindd → bind with description"                  "grep -qF 'bind(\"SUPER + Q\",{args={},dsp=\"window.close\"},{description=\"Close window\"})' $O"
ck "bind flags (e, l) → repeating, locked"          "grep -F 'XF86AudioRaiseVolume' $O | grep -q 'locked=true,repeating=true'"
ck "mouse binds drag and resize"                    "grep -F 'mouse:272' $O | grep -q 'window.drag' && grep -F 'mouse:273' $O | grep -q 'window.resize'"
ck "fullscreen 1 is maximise"                       "grep -F '\"SUPER + F\"' $O | grep -q 'mode=\"maximized\"'"
ck "silent move keeps you where you are"            "grep -F '\"SUPER + minus\"' $O | grep -q 'follow=false'"
ck "Alt+Tab goes through prime-hypr"                "grep -F '\"ALT + Tab\"' $O | grep -q 'prime-hypr dispatch cyclenext'"
ck "the lock submap keeps its one shortcut"         "awk '/^define_submap\\(prime-locked\\)/{f=1;next} /^end_submap/{f=0} f' $O | grep -q 'prime-lock --now'"
ck "window rules: match + effects"                  "grep -F 'window_rule(' $O | grep -F 'prime-float' | grep -q 'float=true'"
ck "old-style layer rules (blur waybar)"            "grep -qF 'layer_rule({blur=true,match={namespace=\"waybar\"}})' $O"
ck "animations and curves"                          "grep -qF 'curve(\"spring\"' $O && grep -F 'animation(' $O | grep -q 'style=\"popin 85%\"'"
ck "the add-on's config is read too (gaming)"       "grep -qF 'config({render.direct_scanout=2})' $O && grep -qF 'env(\"MANGOHUD\",\"1\")' $O"
ck "monitors from monitors.conf"                    "grep -qF 'output=\"HDMI-A-1\"' $O"
ck "keyboard.conf wins over the default layout"     "[ \"\$(grep -F 'input.kb_layout' $O | tail -1)\" = 'config({input.kb_layout=\"us,de\"})' ]"
ck "exec-once runs at start, bar session included"  "awk '/^on\\(hyprland.start\\)/{f=1;next} /^end_on/{f=0} f' $O | grep -q 'prime-session.target'"
ck "title-bar options wait for the plugin"          "! grep -q 'plugin.hyprbars' $O"

echo; echo "== a line it can't use is skipped, not fatal"
printf 'source = ~/.local/share/prime-linux/layer/default/hypr/prime.conf\nnonsense line\nbindd = SUPER, Z, x, nosuchdispatcher, 1\ngeneral {\n    gaps_out = 3\n}\n' > "$H/.config/hypr/hyprland.conf"
HOME="$H" XDG_RUNTIME_DIR="$T/run" "$LUA" "$T/mock.lua" > "$O" 2>&1
ck "both bad lines are reported, with file:line"    "grep -qx 'errors=2' $O && grep -q 'hyprland.conf:2' $O && grep -q 'hyprland.conf:3' $O"
ck "the lines after them still apply"               "grep -qF 'config({general.gaps_out=3})' $O"
ck "and they are listed for prime-doctor"           "[ \"\$(wc -l < $T/run/prime-hypr-errors)\" = 2 ]"
ck "you get told (a notification)"                  "grep -q 'notification.create' $O"

echo; echo "== prime-hypr: the old words on old Hyprland, Lua on 0.57"
F="$T/fake"; mkdir -p "$F"
cat > "$F/hyprctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
case "\$1" in version) cat "$T/version" ;; eval) echo ok ;; esac
EOF
chmod +x "$F/hyprctl"
ph() { rm -f "$T/calls"; HYPRLAND_INSTANCE_SIGNATURE="sig$RANDOM" XDG_RUNTIME_DIR="$T/run" PATH="$F:$PATH" bash "$REPO/layer/bin/prime-hypr" "$@"; }
echo '{"tag": "v0.56.2"}' > "$T/version"
ph dispatch workspace e+1
ck "0.56: dispatch passes straight through"         "grep -qx 'dispatch workspace e+1' $T/calls"
ph keyword animations:enabled false
ck "0.56: keyword passes straight through"          "grep -qx 'keyword animations:enabled false' $T/calls"
echo '{"tag": "v0.57.0"}' > "$T/version"
ph dispatch movetoworkspacesilent special:minimized
ck "0.57: dispatch goes to prime.dispatch"          "grep -qF 'prime.dispatch([==[movetoworkspacesilent]==], [==[special:minimized]==])' $T/calls"
ph dispatch exec -- 'notify-send "a b"'
ck "0.57: exec keeps the whole command, quotes too" "grep -qF 'prime.dispatch([==[exec]==], [==[notify-send \"a b\"]==])' $T/calls"
ph keyword general:col.active_border "rgba(ffffff44) rgba(aabbcc66) 45deg"
ck "0.57: keyword goes to prime.set"                "grep -qF 'prime.set([==[general:col.active_border]==], [==[rgba(ffffff44) rgba(aabbcc66) 45deg]==])' $T/calls"
ck "the version is asked once per session"          "S=sigfixed; rm -f $T/calls; for i in 1 2; do HYPRLAND_INSTANCE_SIGNATURE=\$S XDG_RUNTIME_DIR=$T/run PATH=$F:\$PATH bash $REPO/layer/bin/prime-hypr dispatch workspace 1; done; [ \"\$(grep -c '^version' $T/calls)\" = 1 ]"

echo; echo "== an existing install gets hyprland.lua (migration)"
mig() { HOME="$H" PRIME_LAYER="$REPO/layer" bash -eu "$REPO/layer/migrations/1793297266.sh" 2>/dev/null; }
rm -f "$H/.config/hypr/hyprland.lua"*; mig
ck "none → Prime's"                                 "grep -q prime-linux $H/.config/hypr/hyprland.lua"
printf 'hl.config({ autogenerated = true })\n' > "$H/.config/hypr/hyprland.lua"; mig
ck "Hyprland's autogenerated one → moved aside"     "grep -q prime-linux $H/.config/hypr/hyprland.lua && grep -q autogenerated $H/.config/hypr/hyprland.lua.autogenerated"
printf 'hl.bind(\"SUPER + T\", hl.dsp.exec_cmd(\"x\"))\n' > "$H/.config/hypr/hyprland.lua"; mig
ck "one you wrote → left alone"                     "grep -q SUPER $H/.config/hypr/hyprland.lua && ! grep -q prime-linux $H/.config/hypr/hyprland.lua"

echo; [ $fail -eq 0 ] && echo "ALL PASSED" || { echo "$fail FAILED"; exit 1; }
