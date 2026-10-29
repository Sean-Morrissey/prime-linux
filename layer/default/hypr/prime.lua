-- Prime Linux — reads Hyprland's classic .conf files on Hyprland 0.57 and later.
--
-- Hyprland 0.57 dropped hyprland.conf: it only reads ~/.config/hypr/hyprland.lua.
-- Everything Prime has — its own defaults, the add-ons, the files Settings writes
-- (monitors.conf, keyboard.conf, the theme), and your own hyprland.conf — is still
-- .conf. Rather than rewrite all of it, this file reads those .conf files and makes
-- the same settings through Hyprland's Lua functions. Nothing that writes a .conf
-- file has to change, and the same files keep working on older Hyprland.
--
-- ~/.config/hypr/hyprland.lua loads this file, then calls
--   prime.load_conf("~/.config/hypr/hyprland.conf")
-- A line that can't be understood is skipped and reported (a notification, and the
-- list in $XDG_RUNTIME_DIR/prime-hypr-errors), never stopping the lines after it.
-- Scripts reach the dispatcher table through `prime-hypr`, which calls
-- prime.dispatch() / prime.set() with `hyprctl eval`.
-- Don't edit this file in ~/.local/share/prime-linux: `prime-update` replaces it.

local M = {}
prime = M

M.errors = {}
M.home = os.getenv("HOME") or ""
M.bin = M.home .. "/.local/share/prime-linux/layer/bin"

-- ── small helpers ───────────────────────────────────────────────────────────

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function expand_home(p)
  p = trim(p)
  if p:sub(1, 2) == "~/" then return M.home .. p:sub(2) end
  if p == "~" then return M.home end
  return (p:gsub("%$HOME", M.home))
end

-- Split on commas into at most `n` fields; the last field keeps any commas
-- (commands and regexes may contain them).
local function split_n(s, n)
  local out, rest = {}, s
  while #out < n - 1 do
    local i = rest:find(",", 1, true)
    if not i then break end
    out[#out + 1] = trim(rest:sub(1, i - 1))
    rest = rest:sub(i + 1)
  end
  out[#out + 1] = trim(rest)
  return out
end

local function split_all(s)
  local out = {}
  for part in (s .. ","):gmatch("(.-),") do out[#out + 1] = trim(part) end
  return out
end

local function words(s)
  local out = {}
  for w in s:gmatch("%S+") do out[#out + 1] = w end
  return out
end

local BOOL = { ["true"] = true, yes = true, on = true, ["false"] = false, no = false, off = false }

local function to_bool(v)
  if type(v) == "boolean" then return v end
  local b = BOOL[tostring(v):lower()]
  if b ~= nil then return b end
  if v == "1" or v == 1 then return true end
  if v == "0" or v == 0 then return false end
  return nil
end

local function note(where, msg)
  msg = tostring(msg):gsub("^.-:%d+: ", "")   -- drop Lua's own "file:line:" prefix
  M.errors[#M.errors + 1] = where .. ": " .. msg
end

local function try(where, f, ...)
  local ok, err = pcall(f, ...)
  if not ok then note(where, err) end
  return ok
end

-- ── dispatchers: classic name + argument string → hl.dsp.* ─────────────────

local DIR = { l = "left", r = "right", u = "up", d = "down", t = "up", b = "down",
              left = "left", right = "right", up = "up", down = "down" }

-- "3,address:0x…" → "3", "address:0x…"
local function arg_and_window(a)
  local x, w = a:match("^(.-),%s*(.+)$")
  if x then return trim(x), trim(w) end
  return trim(a), nil
end

local function with_window(t, w)
  if w == "active" then w = "activewindow" end      -- the old short form
  if w and w ~= "" then t.window = w end
  return t
end

local function toggle_action(a)
  a = trim(a or "")
  if a == "" or a == "toggle" then return "toggle" end
  local b = to_bool(a)
  if b == true then return "enable" elseif b == false then return "disable" end
  return a
end

-- Leading "[float; workspace 2 silent]" on exec → exec_cmd rules.
local function exec_rules(cmd)
  local rules, rest = cmd:match("^%s*%[(.-)%]%s*(.*)$")
  if not rules then return cmd, nil end
  local t = {}
  for raw in (rules .. ";"):gmatch("(.-);") do
    local r = trim(raw)
    if r ~= "" then
      local k, v = r:match("^(%S+)%s*(.*)$")
      t[k] = (v == "" or BOOL[v] ~= nil) and (BOOL[v] ~= false) or v
    end
  end
  return rest, t
end

-- Shell commands written for the old hyprctl ("hyprctl dispatch killactive") go
-- through prime-hypr, which speaks both the old and the new syntax.
function M.fix_cmd(cmd)
  return (cmd:gsub("hyprctl%s+dispatch%s+", M.bin .. "/prime-hypr dispatch "))
end

local D = {}
D.exec = function(a) local c, r = exec_rules(a) return hl.dsp.exec_cmd(M.fix_cmd(c), r) end
D.execr = function(a) return hl.dsp.exec_raw(M.fix_cmd(a)) end
D.killactive = function() return hl.dsp.window.close() end
D.closewindow = function(a) return hl.dsp.window.close({ window = a }) end
D.forcekillactive = function() return hl.dsp.window.kill() end
D.killwindow = function(a) return hl.dsp.window.kill({ window = a }) end
D.signal = function(a) local s, w = arg_and_window(a) return hl.dsp.window.signal(with_window({ signal = tonumber(s) or s }, w)) end
D.fullscreen = function(a)
  local mode = ({ ["0"] = "fullscreen", ["1"] = "maximized", [""] = "fullscreen" })[trim(a)]
  return hl.dsp.window.fullscreen({ mode = mode or "fullscreen", action = "toggle" })
end
D.fullscreenstate = function(a)
  local w = words(a)
  return hl.dsp.window.fullscreen_state({ internal = tonumber(w[1]) or -1, client = tonumber(w[2]) or -1 })
end
D.togglefloating = function(a) return hl.dsp.window.float(with_window({ action = "toggle" }, trim(a))) end
D.setfloating = function(a) return hl.dsp.window.float(with_window({ action = "enable" }, trim(a))) end
D.settiled = function(a) return hl.dsp.window.float(with_window({ action = "disable" }, trim(a))) end
D.pin = function(a) return hl.dsp.window.pin(with_window({ action = "toggle" }, trim(a))) end
D.pseudo = function(a) return hl.dsp.window.pseudo(with_window({ action = "toggle" }, trim(a))) end
D.centerwindow = function() return hl.dsp.window.center() end
D.cyclenext = function(a)
  local t = {}
  for _, w in ipairs(words(a)) do
    if w == "prev" then t.next = false elseif w == "tiled" then t.tiled = true
    elseif w == "floating" then t.floating = true end
  end
  return hl.dsp.window.cycle_next(t)
end
D.bringactivetotop = function() return hl.dsp.window.alter_zorder({ mode = "top" }) end
D.alterzorder = function(a) local m, w = arg_and_window(a) return hl.dsp.window.alter_zorder(with_window({ mode = m }, w)) end
D.movefocus = function(a) return hl.dsp.focus({ direction = DIR[trim(a)] or trim(a) }) end
D.movewindow = function(a)
  a = trim(a)
  if a == "" then return hl.dsp.window.drag() end           -- mouse bind
  local mon = a:match("^mon:(.+)$")
  if mon then return hl.dsp.window.move({ monitor = mon }) end
  return hl.dsp.window.move({ direction = DIR[a] or a })
end
D.resizewindow = function() return hl.dsp.window.resize() end  -- mouse bind
D.swapwindow = function(a) return hl.dsp.window.swap({ direction = DIR[trim(a)] or trim(a) }) end
D.resizeactive = function(a)
  local w = words(a)
  return hl.dsp.window.resize({ x = tonumber(w[1]) or w[1], y = tonumber(w[2]) or w[2], relative = true })
end
D.moveactive = function(a)
  local w = words(a)
  return hl.dsp.window.move({ x = tonumber(w[1]) or w[1], y = tonumber(w[2]) or w[2], relative = true })
end
-- "exact 800 600,activewindow" sets the size/position; "40 0" changes it by that much
local function pixel_spec(a)
  local xy, win = arg_and_window(a)
  local w = words(xy)
  local exact = w[1] == "exact"
  if exact then table.remove(w, 1) end
  return with_window({ x = tonumber(w[1]) or w[1], y = tonumber(w[2]) or w[2], relative = not exact }, win)
end
D.resizewindowpixel = function(a) return hl.dsp.window.resize(pixel_spec(a)) end
D.movewindowpixel = function(a) return hl.dsp.window.move(pixel_spec(a)) end
D.focusmonitor = function(a) return hl.dsp.focus({ monitor = trim(a) }) end
D.focuswindow = function(a) return hl.dsp.focus({ window = trim(a) }) end
D.focusurgentorlast = function() return hl.dsp.focus({ urgent_or_last = true }) end
D.focuscurrentorlast = function() return hl.dsp.focus({ last = true }) end
D.workspace = function(a) return hl.dsp.focus({ workspace = trim(a) }) end
D.movetoworkspace = function(a)
  local ws, w = arg_and_window(a)
  return hl.dsp.window.move(with_window({ workspace = ws, follow = true }, w))
end
D.movetoworkspacesilent = function(a)
  local ws, w = arg_and_window(a)
  return hl.dsp.window.move(with_window({ workspace = ws, follow = false }, w))
end
D.togglespecialworkspace = function(a) return hl.dsp.workspace.toggle_special(trim(a)) end
D.movecurrentworkspacetomonitor = function(a) return hl.dsp.workspace.move({ monitor = trim(a) }) end
D.moveworkspacetomonitor = function(a)
  local w = words(a)
  return hl.dsp.workspace.move({ workspace = w[1], monitor = w[2] })
end
D.swapactiveworkspaces = function(a)
  local w = words(a)
  return hl.dsp.workspace.swap_monitors({ monitor1 = w[1], monitor2 = w[2] })
end
D.renameworkspace = function(a)
  local id, name = trim(a):match("^(%S+)%s*(.*)$")
  return hl.dsp.workspace.rename({ workspace = id, name = name ~= "" and name or nil })
end
D.layoutmsg = function(a) return hl.dsp.layout(trim(a)) end
D.submap = function(a) return hl.dsp.submap(trim(a)) end
D.exit = function() return hl.dsp.exit() end
D.dpms = function(a)
  local w = words(a)
  local act = ({ on = "enable", off = "disable", toggle = "toggle" })[w[1] or "toggle"] or "toggle"
  return hl.dsp.dpms({ action = act, monitor = w[2] })
end
D.forcerendererreload = function() return hl.dsp.force_renderer_reload() end
D.togglegroup = function() return hl.dsp.group.toggle() end
D.changegroupactive = function(a)
  a = trim(a)
  if a == "b" or a == "prev" then return hl.dsp.group.prev() end
  if tonumber(a) then return hl.dsp.group.active({ index = tonumber(a) }) end
  return hl.dsp.group.next()
end
D.lockgroups = function(a) return hl.dsp.group.lock({ all = true, action = toggle_action(a) }) end
D.lockactivegroup = function(a) return hl.dsp.group.lock({ action = toggle_action(a) }) end
D.denywindowfromgroup = function(a) return hl.dsp.window.deny_from_group({ action = toggle_action(a) }) end
D.toggleswallow = function() return hl.dsp.window.toggle_swallow() end
D.pass = function(a) return hl.dsp.pass(with_window({}, trim(a))) end
D.sendshortcut = function(a)
  local f = split_n(a, 3)
  return hl.dsp.send_shortcut(with_window({ mods = f[1], key = f[2] }, f[3]))
end
D.global = function(a) return hl.dsp.global(trim(a)) end
D.event = function(a) return hl.dsp.event(trim(a)) end
D.tagwindow = function(a) local t, w = trim(a):match("^(%S+)%s*(.*)$") return hl.dsp.window.tag(with_window({ tag = t }, w)) end
D.setprop = function(a)
  local w, p, v = trim(a):match("^(%S+)%s+(%S+)%s+(.*)$")
  return hl.dsp.window.set_prop({ window = w, prop = p, value = v })
end
D.movecursor = function(a) local w = words(a) return hl.dsp.cursor.move({ x = tonumber(w[1]), y = tonumber(w[2]) }) end
D.movecursortocorner = function(a) return hl.dsp.cursor.move_to_corner({ corner = tonumber(trim(a)) }) end
D.forceidle = function(a) return hl.dsp.force_idle(tonumber(trim(a)) or 0) end

M.dispatchers = D

-- The dispatcher object for a classic dispatcher name and its arguments.
function M.dsp(name, args)
  local f = D[trim(name or ""):lower()]
  if not f then error("unknown dispatcher '" .. tostring(name) .. "'") end
  return f(args or "")
end

-- Run one classic dispatch now: what `prime-hypr dispatch NAME ARGS` calls.
function M.dispatch(name, args)
  return hl.dispatch(M.dsp(name, args))
end

-- What each shortcut does, by "modmask:key", so prime-keys can run one from its
-- list (0.57's `hyprctl binds` no longer says what a bind does in words).
M.bind_registry = {}

function M.run_bind(modmask, key)
  local d = M.bind_registry[tostring(modmask) .. ":" .. tostring(key)]
  if not d then error("no shortcut " .. tostring(modmask) .. ":" .. tostring(key)) end
  return hl.dispatch(d)
end

-- ── values ─────────────────────────────────────────────────────────────────

local COLOUR = "^(rgba?%b())$"

-- "rgba(ffffff44) rgba(d4d4d866) 45deg" → { colors = {…}, angle = 45 }
local function gradient(v)
  local w, colors, angle = {}, {}, nil
  -- colours may contain spaces inside their brackets: rgba(0, 0, 0, 0.5)
  local s = v:gsub("%b()", function(p) return (p:gsub("%s+", "")) end)
  w = words(s)
  if #w < 2 then return nil end
  for _, t in ipairs(w) do
    local deg = t:match("^(%-?[%d%.]+)deg$")
    if deg then angle = tonumber(deg)
    elseif t:match(COLOUR) or t:match("^0x%x+$") then colors[#colors + 1] = t
    else return nil end
  end
  if #colors == 0 then return nil end
  return { colors = colors, angle = angle }
end

-- Integer options refuse "1" (a string), so numbers go across as numbers.
local function config_value(path, v)
  local b = BOOL[v:lower()]
  if b ~= nil then return b end
  local n = tonumber(v)
  if n and not v:match("^0x") then return n end
  local g = gradient(v)
  if g then return g end
  if path:match("on_double_click$") then return M.fix_cmd(v) end
  return v
end

-- ── the reader ─────────────────────────────────────────────────────────────

local KEY_ALIAS = { ["tap-to-click"] = "tap_to_click", ["tap-and-drag"] = "tap_and_drag",
                    ["drag-lock"] = "drag_lock" }

local function key_name(k)
  k = trim(k)
  return KEY_ALIAS[k] or (k:gsub("%-", "_"))
end

local BIND_FLAGS = { l = "locked", r = "release", c = "click", g = "drag", o = "long_press",
  e = "repeating", n = "non_consuming", m = "mouse", t = "transparent", i = "ignore_mods",
  p = "dont_inhibit", u = "submap_universal", a = "auto_consuming" }

local function bind_keys(mods, key)
  local parts = {}
  for m in mods:gmatch("[^%s_+]+") do parts[#parts + 1] = m:upper() end
  parts[#parts + 1] = trim(key)
  return table.concat(parts, " + ")
end

-- Old window-rule match names (windowrulev2) → the current ones
local MATCH_ALIAS = { initialClass = "initial_class", initialTitle = "initial_title",
  floating = "float", pinned = "pin", fullscreenstate = "fullscreen_state_internal",
  xdgTag = "xdg_tag", onworkspace = "workspace" }

local NUMERIC_EFFECTS = { border_size = true, rounding = true, rounding_power = true,
  no_close_for = true, scroll_mouse = true, scroll_touchpad = true, scrolling_width = true,
  above_lock = true, order = true, ignore_alpha = true }

local function effect_value(name, v)
  v = trim(v or "")
  if v == "" then return true end
  if NUMERIC_EFFECTS[name] then return tonumber(v) or v end
  local b = to_bool(v)
  if b ~= nil and name ~= "workspace" and name ~= "monitor" and name ~= "opacity" then return b end
  return v
end

-- "float on, match:class ^(x)$, size 720 520" → spec for hl.window_rule / layer_rule
local function rule_spec(value, is_layer)
  local spec, match = {}, {}
  local parts = split_all(value)
  for _, p in ipairs(parts) do
    local mk, mv = p:match("^match:(%S+)%s+(.+)$")
    if not mk then mk, mv = p:match("^(%a[%w_]*):(.+)$") end     -- windowrulev2: class:^(x)$
    if mk then
      match[MATCH_ALIAS[mk] or mk] = effect_value("match", mv)
    elseif p ~= "" then
      local name, arg = p:match("^(%S+)%s*(.*)$")
      name = name:gsub("^no(%a)", "no_%1"):gsub("^no__", "no_")    -- noblur → no_blur
      spec[name] = effect_value(name, arg)
    end
  end
  -- the oldest layer-rule form: "blur waybar" (effect, then namespace)
  if is_layer and next(match) == nil and #parts == 1 then
    local name, ns = parts[1]:match("^(%S+)%s+(.+)$")
    if name then spec = { [name] = true }; match.namespace = ns end
  end
  spec.match = match
  return spec
end

local Reader = {}
Reader.__index = Reader

function M.new_reader()
  return setmetatable({ vars = {}, section = {}, block = nil, submap = nil,
                        submap_binds = nil, exec_once = {}, depth = 0 }, Reader)
end

function Reader:expand(v)
  if not v:find("$", 1, true) then return v end
  -- longest names first so $accent_border isn't read as $accent + "_border"
  local names = {}
  for n in pairs(self.vars) do names[#names + 1] = n end
  table.sort(names, function(a, b) return #a > #b end)
  for _, n in ipairs(names) do
    v = v:gsub("%$" .. n:gsub("%p", "%%%0"), (self.vars[n]:gsub("%%", "%%%%")))
  end
  return v
end

-- A plugin's options don't exist until the plugin is loaded. prime-titlebars loads
-- it after login and Hyprland then reads the config again, so until then they're
-- skipped rather than reported.
local function plugin_loaded(name)
  local ok, list = pcall(hl.get_loaded_plugins)
  if not ok or type(list) ~= "table" then return false end
  for _, p in ipairs(list) do
    if p.name and p.name:lower() == name:lower() then return true end
  end
  return false
end

function Reader:set_option(where, path, value)
  local plugin = path:match("^plugin%.([^.]+)%.")
  if plugin and not plugin_loaded(plugin) then return end
  try(where, hl.config, { [path] = config_value(path, value) })
end

function Reader:do_bind(where, kw, value)
  local flags = kw:match("^bind(%a*)$")
  if not flags then return note(where, "unknown keyword '" .. kw .. "'") end
  local opts = {}
  local has_desc = flags:find("d", 1, true) ~= nil
  for c in flags:gmatch(".") do
    if BIND_FLAGS[c] then opts[BIND_FLAGS[c]] = true end
  end
  local f = split_n(value, has_desc and 5 or 4)
  local mods, key = f[1] or "", f[2] or ""
  local i = 3
  if has_desc then opts.description = f[3]; i = 4 end
  local name, args = f[i] or "", f[i + 1] or ""
  local keys = bind_keys(mods, key)
  local in_submap = self.submap ~= nil
  local function register()
    local d = M.dsp(name, args)
    if opts.mouse and name == "movewindow" then d = hl.dsp.window.drag() end
    if opts.mouse and name == "resizewindow" then d = hl.dsp.window.resize() end
    local kb = hl.bind(keys, d, next(opts) and opts or nil)
    if kb and not in_submap and not opts.mouse then
      M.bind_registry[tostring(kb.modmask) .. ":" .. tostring(kb.key)] = d
    end
  end
  if self.submap then
    table.insert(self.submap_binds, { where = where, fn = register })
  else
    try(where, register)
  end
end

function Reader:close_submap()
  local name, binds = self.submap, self.submap_binds
  self.submap, self.submap_binds = nil, nil
  try("submap " .. name, hl.define_submap, name, function()
    for _, b in ipairs(binds) do try(b.where, b.fn) end
  end)
end

function Reader:keyword(where, kw, value)
  if kw:match("^bind") then return self:do_bind(where, kw, value) end

  if kw == "unbind" then
    local f = split_n(value, 2)
    return try(where, hl.unbind, bind_keys(f[1], f[2] or ""))
  elseif kw == "source" then
    return self:source(where, value)
  elseif kw == "env" then
    local f = split_n(value, 2)
    return try(where, hl.env, f[1], f[2] or "")
  elseif kw == "exec-once" or kw == "execr-once" then
    table.insert(self.exec_once, M.fix_cmd(value))
    return
  elseif kw == "exec" or kw == "execr" then
    return try(where, hl.exec_cmd, M.fix_cmd(value))
  elseif kw == "exec-shutdown" then
    local cmd = M.fix_cmd(value)
    return try(where, hl.on, "hyprland.shutdown", function() hl.exec_cmd(cmd) end)
  elseif kw == "windowrule" or kw == "windowrulev2" then
    return try(where, hl.window_rule, rule_spec(value, false))
  elseif kw == "layerrule" then
    return try(where, hl.layer_rule, rule_spec(value, true))
  elseif kw == "monitor" then
    return self:monitor(where, value)
  elseif kw == "workspace" then
    return self:workspace_rule(where, value)
  elseif kw == "bezier" then
    local f = split_all(value)
    return try(where, hl.curve, f[1], { type = "bezier",
      points = { { tonumber(f[2]), tonumber(f[3]) }, { tonumber(f[4]), tonumber(f[5]) } } })
  elseif kw == "animation" then
    local f = split_n(value, 5)
    local spec = { leaf = f[1], enabled = to_bool(f[2]) ~= false }
    if spec.enabled then
      spec.speed = tonumber(f[3]); spec.bezier = f[4]
      if f[5] and f[5] ~= "" then spec.style = f[5] end
    end
    return try(where, hl.animation, spec)
  elseif kw == "gesture" then
    local f = split_n(value, 4)
    local spec = { fingers = tonumber(f[1]), direction = f[2] }
    local rest = f[3] or ""
    local mods = rest:match("^mod:%s*(.+)$")
    if mods then spec.mods = mods; local g = split_n(f[4] or "", 2); rest = g[1]; f[4] = g[2] end
    if rest == "dispatcher" then
      local g = split_n(f[4] or "", 2)
      local d = M.dsp(g[1], g[2])
      spec.action = function() hl.dispatch(d) end
    else
      spec.action = rest
    end
    return try(where, hl.gesture, spec)
  elseif kw == "submap" then
    value = trim(value)
    if self.submap then self:close_submap() end
    if value ~= "reset" then self.submap, self.submap_binds = value, {} end
    return
  elseif kw == "plugin" then
    return try(where, hl.plugin.load, expand_home(value))
  elseif kw == "permission" then
    local f = split_all(value)
    return try(where, hl.permission, { binary = f[1], type = f[2], mode = f[3] })
  elseif kw == "hyprbars-button" then
    local f = split_n(value, 5)
    if not (hl.plugin and hl.plugin.hyprbars) then return end   -- not loaded yet
    return try(where, hl.plugin.hyprbars.add_button, {
      bg_color = f[1], size = tonumber(f[2]), icon = f[3],
      action = M.fix_cmd(f[4] or ""), fg_color = f[5] })
  end
  note(where, "unknown keyword '" .. kw .. "'")
end

function Reader:monitor(where, value)
  local f = split_all(value)
  local spec = { output = f[1] }
  if f[2] == "disable" or f[2] == "disabled" then
    spec.disabled = true
  elseif f[2] == "addreserved" then
    spec.reserved = { top = tonumber(f[3]), bottom = tonumber(f[4]), left = tonumber(f[5]), right = tonumber(f[6]) }
  else
    spec.mode, spec.position, spec.scale = f[2], f[3], f[4]
    local i = 5
    while f[i] do
      local k, v = f[i], f[i + 1]
      spec[k] = tonumber(v) or v
      i = i + 2
    end
  end
  try(where, hl.monitor, spec)
end

local WS_KEYS = { gapsin = "gaps_in", gapsout = "gaps_out", bordersize = "border_size",
  defaultName = "default_name", on_created_empty = "on_created_empty", floatgaps = "float_gaps" }

function Reader:workspace_rule(where, value)
  local f = split_all(value)
  local spec = { workspace = f[1] }
  for i = 2, #f do
    local k, v = f[i]:match("^([%w_]+):%s*(.*)$")
    if k then
      k = WS_KEYS[k] or k
      if k == "border" then spec.no_border = to_bool(v) == false
      elseif k == "shadow" then spec.no_shadow = to_bool(v) == false
      elseif k == "rounding" then spec.no_rounding = to_bool(v) == false
      else
        local b = to_bool(v)
        spec[k] = (b ~= nil and k ~= "monitor" and k ~= "default_name") and b or (tonumber(v) or v)
      end
    end
  end
  try(where, hl.workspace_rule, spec)
end

-- A whole-block rule:  windowrule { name = x  match:class = y  float = on }
function Reader:close_block()
  local b = self.block
  self.block = nil
  local spec, match = {}, {}
  for _, kv in ipairs(b.items) do
    local k, v = kv[1], kv[2]
    local mk = k:match("^match:(.+)$")
    if mk then match[MATCH_ALIAS[mk] or mk] = effect_value("match", v)
    elseif k == "name" then spec.name = v
    else spec[key_name(k)] = effect_value(key_name(k), v) end
  end
  if b.kind == "device" then return try(b.where, hl.device, spec) end
  spec.match = match
  try(b.where, b.kind == "layerrule" and hl.layer_rule or hl.window_rule, spec)
end

local BLOCKS = { windowrule = true, layerrule = true, device = true }

function Reader:line(where, raw)
  -- comments: "#" starts one, "##" is a literal "#"
  local line = raw:gsub("##", "\1"):gsub("#.*$", ""):gsub("\1", "#")
  line = trim(line)
  if line == "" then return end

  -- section open, possibly with something after the brace on the same line
  local name, after = line:match("^([%w_%-%.:]+)%s*{%s*(.-)$")
  if name then
    if BLOCKS[name] and #self.section == 0 then
      self.block = { kind = name, where = where, items = {} }
    else
      table.insert(self.section, false)   -- marks how far one "}" unwinds
      for part in name:gmatch("[^:%.]+") do table.insert(self.section, part) end
    end
    if after ~= "" then self:line(where, after) end
    return
  end

  if line:sub(1, 1) == "}" then
    if self.block then self:close_block()
    else
      while #self.section > 0 do
        local top = table.remove(self.section)
        if top == false then break end
      end
    end
    local rest = trim(line:sub(2))
    if rest ~= "" then self:line(where, rest) end
    return
  end

  local k, v = line:match("^([^=]-)%s*=%s*(.*)$")
  if not k then return note(where, "can't read this line") end
  k = trim(k)

  if k:sub(1, 1) == "$" then
    self.vars[k:sub(2)] = self:expand(trim(v))
    return
  end
  v = self:expand(v)

  if self.block then
    table.insert(self.block.items, { k, trim(v) })
    return
  end

  local sec = {}
  for _, s in ipairs(self.section) do if s then sec[#sec + 1] = s end end

  -- keywords are recognised anywhere (bezier/animation live inside animations {},
  -- hyprbars-button inside plugin { hyprbars {} })
  if k:match("^bind%a*$") or k == "unbind" or k == "source" or k == "env" or k:match("^exec")
     or k == "windowrule" or k == "windowrulev2" or k == "layerrule" or k == "monitor"
     or (k == "workspace" and #sec == 0) or k == "bezier" or k == "animation" or k == "gesture"
     or k == "submap" or (k == "plugin" and #sec == 0) or k == "permission" or k == "hyprbars-button" then
    return self:keyword(where, k, v)
  end

  -- an option: general { gaps_in = 6 }  or  general:gaps_in = 6
  local path = {}
  for _, s in ipairs(sec) do path[#path + 1] = key_name(s) end
  for part in k:gmatch("[^:]+") do path[#path + 1] = key_name(part) end
  self:set_option(where, table.concat(path, "."), trim(v))
end

function Reader:source(where, pattern)
  pattern = expand_home(pattern)
  local files = {}
  if pattern:find("[%*%?%[]") then
    local p = io.popen("ls -1d " .. pattern:gsub("[^%w%*%?%[%]/%._%-~]", "\\%0") .. " 2>/dev/null")
    if p then for f in p:lines() do files[#files + 1] = f end p:close() end
  else
    files[1] = pattern
  end
  for _, f in ipairs(files) do self:file(f, where) end
end

function Reader:file(path, from)
  self.depth = self.depth + 1
  if self.depth > 20 then self.depth = self.depth - 1 return note(from or path, "source nested too deep") end
  local fh = io.open(path, "r")
  if not fh then
    self.depth = self.depth - 1
    return note(from or path, "can't open " .. path)
  end
  local short = path:gsub("^" .. M.home:gsub("%p", "%%%0"), "~")
  local n = 0
  for raw in fh:lines() do
    n = n + 1
    local ok, err = pcall(self.line, self, short .. ":" .. n, raw)
    if not ok then note(short .. ":" .. n, err) end
  end
  fh:close()
  self.depth = self.depth - 1
end

-- One `hyprctl keyword KEY VALUE`, now: what `prime-hypr keyword` calls. Read as a
-- config line, so an option (general:gaps_in, or general.gaps_in) and a keyword
-- (workspace = 1, monitor:<output>) both work. A failure is raised, not just listed,
-- so the script that asked hears about it.
function M.set(key, value)
  local before = #M.errors
  M.new_reader():line("hyprctl keyword", key .. " = " .. tostring(value))
  if #M.errors > before then
    local err = M.errors[#M.errors]
    while #M.errors > before do table.remove(M.errors) end
    error(err, 0)
  end
end

-- Read one .conf file (and everything it sources) into Hyprland.
function M.load_conf(path)
  local r = M.new_reader()
  r:file(expand_home(path))
  if r.submap then r:close_submap() end
  if #r.exec_once > 0 then
    local cmds = r.exec_once
    try("exec-once", hl.on, "hyprland.start", function()
      for _, c in ipairs(cmds) do pcall(hl.exec_cmd, c) end
    end)
  end
  M.report()
  return r
end

-- Tell someone about lines that were skipped.
function M.report()
  local dir = os.getenv("XDG_RUNTIME_DIR")
  if dir then
    local f = io.open(dir .. "/prime-hypr-errors", "w")
    if f then
      for _, e in ipairs(M.errors) do f:write(e, "\n") end
      f:close()
    end
  end
  if #M.errors > 0 then
    local first = M.errors[1]
    local more = #M.errors > 1 and (" (and " .. (#M.errors - 1) .. " more — see $XDG_RUNTIME_DIR/prime-hypr-errors)") or ""
    pcall(function()
      hl.notification.create({ text = "Prime skipped a Hyprland setting it couldn't read: " .. first .. more,
                               timeout = 15000, color = "rgb(ffbd2e)" })
    end)
  end
end

return M
