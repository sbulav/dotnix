local events, bindings, rules, commands = {}, {}, {}, {}
local monitors = { { name = "eDP-1" } }
hl = {
  on = function(event, action) events[event] = action end,
  bind = function(key, action, options)
    assert(options.locked, "lid handling must work on the lock screen")
    bindings[key] = action
  end,
  get_monitors = function() return monitors end,
  monitor = function(rule) rules[#rules + 1] = rule end,
  exec_cmd = function(command) commands[#commands + 1] = command end,
}
local probes = 0
io.popen = function()
  probes = probes + 1
  return { read = function() return "Open" end, close = function() end }
end
dofile(arg[1])({ internal = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1.5,
  read_lid = "read-lid", suspend = "suspend" })
assert(#rules == 1 and rules[1].scale == 1.5 and not rules[1].disabled)
monitors[#monitors + 1] = { name = "DP-1" }
events["monitor.layout_changed"]()
bindings["switch:on:Lid Switch"]()
assert(rules[#rules].disabled and rules[#rules].output == "eDP-1")
assert(#commands == 0, "docked lid close must not suspend")
local count = #rules
for _ = 1, 30 do events["monitor.layout_changed"]() end
assert(#rules == count and probes == 1, "stable state must not rewrite rules or spawn probes")
monitors = {}
events["monitor.layout_changed"]()
assert(#commands == 1 and commands[1] == "suspend", "undocking a closed laptop suspends")
events["monitor.layout_changed"]()
assert(#commands == 1, "repeated output events must not resubmit suspend")
bindings["switch:off:Lid Switch"]()
assert(not rules[#rules].disabled and rules[#rules].scale == 1.5)
assert(probes == 1, "lid and monitor events use compositor state without periodic shell commands")
print("Clamshell event and idle-budget checks passed")
