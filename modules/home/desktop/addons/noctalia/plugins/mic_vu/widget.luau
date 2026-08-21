--!nonstrict
-- Bar widget: shows the analog meter face that service.luau renders into
-- the plugin data dir. setImage with watch=true reloads the SVG on every
-- atomic rename, so this script only owns the tooltip.

local width = tonumber(noctalia.getConfig("meter_width")) or 46
local height = math.floor(width * 0.6 + 0.5) -- face is 60x36

-- Set once at load (the runtime consumes load-chunk patches too); update()
-- is only a slow tooltip fallback — state.watch does the real-time work.
noctalia.setUpdateInterval(5000)

local vu = noctalia.state.get("vu") or { status = "nosrc", level = 0 }

local function refreshTooltip()
  if vu.status == "muted" then
    barWidget.setTooltip({ { key = "Microphone", value = "muted" } })
  elseif vu.status == "nosrc" then
    barWidget.setTooltip({ { key = "Microphone", value = "not found" } })
  else
    barWidget.setTooltip({
      { key = "Microphone", value = "live" },
      { key = "Level", value = string.format("%d%%", math.floor((vu.level or 0) * 100 + 0.5)) },
    })
  end
end

local dataDir = noctalia.pluginDataDir()
if dataDir ~= nil then
  barWidget.setImage(dataDir .. "/vu.svg", true, width, height)
else
  -- no writable state dir: degrade to a static glyph instead of a dead spot
  barWidget.setGlyph("microphone-off")
end
refreshTooltip()

noctalia.state.watch("vu", function(value)
  if value ~= nil then
    vu = value
  end
  refreshTooltip()
end)

function update()
  refreshTooltip()
end
