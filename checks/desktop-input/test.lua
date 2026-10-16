-- Drive the bindings as a compositor would, including a changed modifier mask
-- and another key released while dictating. No live session is involved.
local bindings, commands = {}, {}
hl = {
  bind = function(keys, action, options)
    bindings[#bindings + 1] = { keys = keys, action = action, options = options }
  end,
  exec_cmd = function(command)
    commands[#commands + 1] = command
  end,
}

local input = dofile(arg[1])
input.bindHold("ALT + slash", "start", "stop")
local press, release = bindings[1], bindings[2]
assert(press.keys == "ALT + slash" and release.keys == press.keys)
assert(release.options.release and release.options.transparent and release.options.ignore_mods)
assert(release.options.non_consuming, "unmatched key presses must still reach applications")
release.action()
assert(#commands == 0, "a release without its own press must do nothing")
press.action()
release.action()
release.action()
assert(#commands == 2 and commands[1] == "start" and commands[2] == "stop")
input.bindHold("F9", "second-start", "second-stop")
bindings[4].action()
assert(#commands == 2, "each hold tracks its own press")
-- The same physical chord uses the clipboard in terminals and ordinary GUI
-- apps, including the no-window case when a layer-shell panel has focus.
local window, sent, timers = nil, {}, {}
hl.get_active_window = function() return window end
hl.dsp = { send_key_state = function(options) return options end }
hl.dispatch = function(options) sent[#sent + 1] = options end
hl.timer = function(action) timers[#timers + 1] = action end
local terminalClasses = { "wezterm", "org.wezfurlong.wezterm", "kitty", "Alacritty", "foot", "com.mitchellh.ghostty" }
input.bindClipboard("SUPER + C", "copy", terminalClasses)
input.bindClipboard("SUPER + V", "paste", terminalClasses)
local copy, paste = bindings[5].action, bindings[6].action
for _, class in ipairs({ "wezterm", "org.wezfurlong.wezterm", "kitty", "Alacritty", "foot", "com.mitchellh.ghostty" }) do
  window = { class = class }
  copy()
  assert(sent[#sent].mods == "CTRL SHIFT" and sent[#sent].key == "C")
  paste()
  assert(sent[#sent].mods == "CTRL SHIFT" and sent[#sent].key == "V")
end
for _, focused in ipairs({ { class = "firefox" }, { class = "org.telegram.desktop" }, false }) do
  window = focused or nil
  paste()
  assert(sent[#sent].mods == "CTRL" and sent[#sent].key == "V")
end
local down = sent[#sent]
assert(down.state == "down" and down.window == nil, "target the focused surface, including panels")
timers[#timers]()
local up = sent[#sent]
assert(up.state == "up" and up.mods == down.mods and up.key == down.key)
print("Desktop input behavior checks passed")
