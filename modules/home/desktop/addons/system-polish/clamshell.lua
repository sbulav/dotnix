-- Hyprland already receives lid and output events. React in-process instead
-- of waking a shell, hyprctl and jq every second throughout the session.
return function(settings)
	local lid, previous
	local probe = io.popen(settings.read_lid, "r")
	if probe then
		lid = (probe:read("*l") or ""):lower()
		probe:close()
	end

	local function reconcile()
		if lid ~= "open" and lid ~= "closed" then
			return
		end
		local external = false
		for _, monitor in ipairs(hl.get_monitors()) do
			if monitor.name and monitor.name ~= settings.internal then
				external = true
			end
		end
		local action = lid == "open" and "restore" or (external and "disable" or "suspend")
		if action == previous then
			return
		end
		-- Set this before updating rules: a monitor layout event can follow our
		-- own change and must not trigger another config update or suspend.
		previous = action
		if action == "suspend" then
			hl.exec_cmd(settings.suspend)
		elseif action == "disable" then
			hl.monitor({ output = settings.internal, disabled = true })
		else
			hl.monitor({
				output = settings.internal,
				disabled = false,
				mode = settings.mode,
				position = settings.position,
				scale = settings.scale,
			})
		end
	end

	for _, state in ipairs({ "on", "off" }) do
		hl.bind("switch:" .. state .. ":" .. (settings.switch or "Lid Switch"), function()
			lid = state == "on" and "closed" or "open"
			reconcile()
		end, { locked = true })
	end
	hl.on("monitor.layout_changed", reconcile)
	hl.on("hyprland.start", reconcile)
	-- Also initialize on config reload, when hyprland.start will not fire.
	if #hl.get_monitors() > 0 then
		reconcile()
	end
end
