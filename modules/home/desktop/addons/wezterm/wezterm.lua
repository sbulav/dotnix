-- https://github.com/pjcj/base/blob/2f036f8bb616a5b3dabf8314ae9eb6d574a83e32/.wezterm.lua#L406
--
local wezterm = require "wezterm"
local config = {}

if wezterm.config_builder then
  config = wezterm.config_builder()
end

-- Fonts
-- {{{
config.adjust_window_size_when_changing_font_size = false

config.font = wezterm.font_with_fallback {
  "CaskaydiaCove Nerd Font Mono",
  { family = "Symbols Nerd Font Mono", scale = 0.9 },
  { family = "DejaVu Sans", weight = "Regular", scale = 0.75 },
}
if wezterm.target_triple == "aarch64-apple-darwin" then
  config.font_size = 18
  -- Linux Setup
else
  config.font_size = 14
end
-- }}}
-- Windows
-- {{{
config.window_close_confirmation = "AlwaysPrompt"
config.window_padding = {
  left = 0,
  right = 0,
  top = 1,
  bottom = 0,
}
config.window_background_opacity = 0.9
-- }}}
-- Cursor
-- {{{
config.cursor_blink_rate = 1000
config.default_cursor_style = "BlinkingBlock"
config.hide_mouse_cursor_when_typing = false
config.xcursor_theme = "Adwaita"
-- }}}
-- Tabs
-- {{{
config.use_fancy_tab_bar = false
config.tab_max_width = 32
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = true
config.inactive_pane_hsb = {
  saturation = 0.9,
  brightness = 0.2,
}
config.quick_select_patterns = {
  "[0-9a-f]{7,40}",
  "https?://[\\w.-]+\\.[a-z]{2,}[\\w/?.=&%-]*", -- URLs
  "/[\\w.-/]+", -- File paths
  "[\\w._%+-]+@[\\w.-]+\\.[a-z]{2,}", -- Emails
  "\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b", -- IP addresses
  "\\b0x[0-9a-fA-F]+\\b", -- Hex numbers
  "\\b[0-9a-fA-F]{7,40}\\b", -- Git hashes
  "\\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\b", -- UUIDs
}

-- }}}
