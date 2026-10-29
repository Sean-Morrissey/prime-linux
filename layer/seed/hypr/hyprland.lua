-- Hyprland 0.57 and later read this file instead of hyprland.conf.
--
-- Prime keeps your settings in hyprland.conf — Settings, the theme and add-ons
-- all write .conf files — so this only reads that, through Prime's reader in
-- ~/.local/share/prime-linux/layer/default/hypr/prime.lua. Keep making your
-- changes in hyprland.conf; they work on every Hyprland version.
-- A line the reader can't use is skipped and listed in
-- $XDG_RUNTIME_DIR/prime-hypr-errors (you get a notification too).

dofile(os.getenv("HOME") .. "/.local/share/prime-linux/layer/default/hypr/prime.lua")
prime.load_conf("~/.config/hypr/hyprland.conf")

-- ── Lua of your own goes below (optional; it runs after hyprland.conf) ──────
-- hl.bind("SUPER + T", hl.dsp.exec_cmd("konsole"))
