-- TODO: fix when is resolved https://github.com/wezterm/wezterm/issues/7156
wezterm.on("window-config-reloaded", function(window)
	if wezterm.gui.screens().active.name == "eDP-1" then
		window:set_config_overrides({
			dpi = 384,
		})
	end
	if wezterm.gui.screens().active.name == "DP-2" then
		window:set_config_overrides({
			dpi = 384,
		})
	end
end)
-- Update window title
-- {{{
wezterm.on("format-window-title", function(tab, _, tabs)
	local index = ""
	if #tabs > 1 then
		index = "[" .. tab.tab_index + 1 .. "/" .. #tabs .. "]"
	end

	return index .. tab.window_title
end)
-- }}}
wezterm.on("update-right-status", function(window)
	window:set_right_status(status.render(theme, {
		status.kubernetes(theme, custom_status.kubernetes),
		status.clock(theme, custom_status.clock),
	}))
end)
-- }}}
