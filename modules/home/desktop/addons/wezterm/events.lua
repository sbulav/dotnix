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
