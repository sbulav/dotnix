-- Exercise mixed-DPI geometry, focus changes and workspace lifecycle without
-- starting a compositor or touching the user's active desktop.
local rules, handlers, bindings = {}, {}, {}
local active_monitor, console, windows
local dispatched
local known_events = {
	["monitor.layout_changed"] = true,
	["monitor.focused"] = true,
	["workspace.move_to_monitor"] = true,
	["window.open"] = true,
	["window.destroy"] = true,
	["window.move_to_workspace"] = true,
	["window.update_rules"] = true,
}
hl = {
	workspace_rule = function(rule)
		table.insert(rules, rule)
	end,
	get_workspace = function()
		return console
	end,
	get_active_monitor = function()
		return active_monitor
	end,
	get_workspace_windows = function()
		assert(console, "must not query all desktop windows before the console exists")
		return windows
	end,
	config = function() end,
	window_rule = function() end,
	curve = function() end,
	animation = function() end,
	bind = function(key, action)
		bindings[key] = action
	end,
	on = function(event, action)
		assert(known_events[event], "unsupported Hyprland 0.55 event: " .. event)
		handlers[event] = action
	end,
	dispatch = function(action)
		dispatched = action
	end,
	dsp = {
		workspace = {
			toggle_special = function(name)
				return { toggle = name }
			end,
		},
		window = {
			move = function(options)
				return options
			end,
		},
	},
}

dofile(arg[1])({ command = "launch-console", toggle_bind = "toggle", move_bind = "move" })
local function gaps()
	return rules[#rules].gaps_out
end
assert(rules[1].on_created_empty == "[workspace special:quake silent] launch-console")
assert(gaps().bottom == 0, "startup before outputs exist leaves a valid seed rule")
assert(bindings.move.workspace == "special:quake" and not bindings.move.follow)

local function monitor(width, height, scale, transform, reserved)
	return { width = width, height = height, scale = scale, transform = transform or 0, reserved = reserved }
end

-- These are mz's configured monitors. Equal logical geometry must produce
-- equal console geometry regardless of the number of physical pixels.
active_monitor = monitor(1920, 1080, 1)
bindings.toggle()
assert(dispatched.toggle == "quake")
assert(gaps().bottom == 540 and gaps().left == 420)
active_monitor = monitor(3840, 2160, 2)
bindings.toggle()
assert(gaps().bottom == 540 and gaps().left == 420)
active_monitor = monitor(3840, 2560, 2)
bindings.toggle()
assert(gaps().bottom == 640 and gaps().left == 320)
active_monitor = monitor(2880, 1620, 1.5)
bindings.toggle()
assert(gaps().bottom == 540 and gaps().left == 420)

-- A rotated monitor swaps the work-area axes, including flipped rotations.
for _, transform in ipairs({ 1, 3, 5, 7 }) do
	active_monitor = monitor(1920, 1080, 1, transform)
	bindings.toggle()
	assert(gaps().bottom == 960 and gaps().left == 0)
end

active_monitor = monitor(3840, 2160, 2, 0, { top = 40, bottom = 0, left = 0, right = 0 })
bindings.toggle()
assert(gaps().bottom == 520 and gaps().left == 440, "honor reserved space on newer Hyprland")

-- Once visible, moving the pointer to the other output must leave it alone.
console = { name = "special:quake", visible = true, monitor = active_monitor }
windows = { { floating = false } }
local count = #rules
active_monitor = monitor(1920, 1080, 1)
handlers["monitor.focused"]()
assert(#rules == count, "focus alone must not change a visible console's geometry")

windows[#windows + 1] = { floating = false }
handlers["window.move_to_workspace"]()
assert(gaps().left == 0, "two tiled windows use the full console width")
windows = { { floating = false }, { floating = true } }
handlers["window.update_rules"]()
assert(gaps().left == 440, "floating windows do not widen the console")
count = #rules
handlers["window.update_rules"]()
assert(#rules == count, "unchanged state must not rewrite rules recursively")

-- An explicit workspace move resizes for the destination output.
handlers["workspace.move_to_monitor"](console, active_monitor)
assert(gaps().bottom == 540 and gaps().left == 420)
console.monitor = active_monitor
console.visible = false
windows = { { floating = false }, { floating = false } }
count = #rules
handlers["window.open"]()
assert(#rules == count, "hidden consoles need no per-window updates")
bindings.toggle()
assert(gaps().left == 0, "reopening applies the hidden workspace's current window count")

-- Disconnected outputs expose expired handles and must not crash callbacks.
console.visible = true
console.monitor = {}
active_monitor = nil
count = #rules
handlers["monitor.layout_changed"]()
assert(#rules == count)
print("Quake console geometry and lifecycle checks passed")
