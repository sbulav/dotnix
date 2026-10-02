-- Adapted from Omarchy's MIT-licensed Quake console. Keep this compatible
-- with Hyprland 0.55: no workspace.special_active event or immediate-refresh API.
return function(settings)
	local workspace = "special:quake"
	local beside, below

	local function cover(side, bottom)
		if beside == side and below == bottom then
			return
		end
		beside, below = side, bottom
		hl.workspace_rule({
			workspace = workspace,
			gaps_in = 0,
			gaps_out = { top = 0, right = side, bottom = bottom, left = side },
			no_border = true,
			on_created_empty = "[workspace " .. workspace .. " silent] " .. settings.command,
		})
	end

	local function refit(monitor)
		local ws = hl.get_workspace(workspace)
		-- Following the pointer onto another output must not resize a visible
		-- console. A toggle explicitly supplies the output it will open on.
		monitor = monitor or (ws and ws.visible and ws.monitor) or hl.get_active_monitor()
		if not monitor or not monitor.scale or monitor.scale <= 0 then
			return
		end

		local width, height = monitor.width, monitor.height
		if (monitor.transform or 0) % 2 == 1 then
			width, height = height, width
		end
		width, height = width / monitor.scale, height / monitor.scale
		-- 0.55 has no Lua reserved-area property. Its layout still keeps the
		-- console below the bar; sizing uses the full logical output there.
		local reserved = monitor.reserved
		if reserved then
			width = width - reserved.left - reserved.right
			height = height - reserved.top - reserved.bottom
		end
		width, height = math.max(0, width), math.max(0, height)

		local tiled = 0
		-- Querying a selector for a workspace not created yet returns no
		-- workspace in 0.55; only query its windows once the handle exists.
		if ws then
			for _, window in ipairs(hl.get_workspace_windows(workspace)) do
				if not window.floating then
					tiled = tiled + 1
				end
			end
		end
		local tall = math.floor(height * 0.5)
		local wide = tiled <= 1 and math.min(width, tall * 2) or width
		cover(math.floor((width - wide) / 2), math.floor(height - tall))
	end

	cover(0, 0)
	refit()
	hl.config({ decoration = { dim_special = 0.6 } })
	hl.window_rule({ match = { class = "^org[.]dotnix[.]quake$" }, workspace = workspace .. " silent" })
	hl.curve("quakeIn", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
	hl.curve("quakeOut", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
	hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 3, bezier = "quakeIn", style = "slide top" })
	hl.animation({
		leaf = "specialWorkspaceOut",
		enabled = true,
		speed = 2,
		bezier = "quakeOut",
		style = "slide bottom",
	})

	hl.bind(settings.toggle_bind, function()
		refit(hl.get_active_monitor())
		return hl.dispatch(hl.dsp.workspace.toggle_special("quake"))
	end, { description = "Toggle Quake console (Herdr)" })
	hl.bind(settings.move_bind, hl.dsp.window.move({ workspace = workspace, follow = false }), {
		description = "Move window to Quake console",
	})

	hl.on("monitor.layout_changed", function()
		refit()
	end)
	hl.on("monitor.focused", function()
		refit()
	end)
	hl.on("workspace.move_to_monitor", function(ws, monitor)
		if ws and ws.name == workspace then
			refit(monitor)
		end
	end)
	local function recount()
		local ws = hl.get_workspace(workspace)
		if ws and ws.visible then
			refit()
		end
	end
	for _, event in ipairs({ "window.open", "window.destroy", "window.move_to_workspace", "window.update_rules" }) do
		hl.on(event, recount)
	end
end
