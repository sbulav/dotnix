-- Behaviors shared by Nix-generated bindings. Keep physical modifiers out of
-- injected shortcuts, and pair hold releases with their own successful press.
local input = {}

function input.bindHold(keys, startCommand, stopCommand)
	local held = false
	hl.bind(keys, function()
		held = true
		hl.exec_cmd(startCommand)
	end, { description = "Start dictation (push-to-talk)" })
	hl.bind(keys, function()
		if held then
			held = false
			hl.exec_cmd(stopCommand)
		end
	end, {
		description = "Stop dictation (push-to-talk)",
		release = true,
		transparent = true,
		ignore_mods = true,
		non_consuming = true,
	})
end

function input.bindClipboard(keys, action, terminalClasses)
	local terminals = {}
	for _, class in ipairs(terminalClasses) do
		terminals[class:lower()] = true
	end
	local key = action == "copy" and "C" or "V"
	hl.bind(keys, function()
		local window = hl.get_active_window()
		local terminal = window and terminals[(window.class or ""):lower()]
		local mods = terminal and "CTRL SHIFT" or "CTRL"
		-- Explicit modifiers target the focused surface without merging the
		-- physically held Super key. Always release the synthetic key once.
		hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
		hl.timer(function()
			hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
		end, { timeout = 50, type = "oneshot" })
	end, { description = "Universal " .. action })
end

return input
