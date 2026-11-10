--!nonstrict
-- Bar widget: shows the analog meter face that service.luau renders into
-- the plugin data dir. setImage with watch=true reloads the SVG on every
-- atomic rename, so this script only owns the tooltip.

-- The face is a 44x22 canvas (2:1, see service.luau): height follows width so
-- the image box never letterboxes. The default 44 gives 22 px — the full
-- thickness of the 22 px bar; a wider meter_width grows the face past the bar
-- edges, so scale it together with the bar.
local width = tonumber(noctalia.getConfig("meter_width")) or 44
local height = math.floor(width / 2 + 0.5)

-- Set once at load (the runtime consumes load-chunk patches too); update()
-- is only a slow tooltip fallback — state.watch does the real-time work.
noctalia.setUpdateInterval(5000)

local vu = noctalia.state.get("vu") or { status = "nosrc", level = 0 }

local function gainRow(rows)
  if vu.gain ~= nil then
    table.insert(rows, { key = "Gain", value = string.format("%d%%", vu.gain) })
  end
  return rows
end

local function refreshTooltip()
  if vu.status == "muted" then
    barWidget.setTooltip(gainRow({ { key = "Microphone", value = "muted" } }))
  elseif vu.status == "nosrc" then
    barWidget.setTooltip({ { key = "Microphone", value = "not found" } })
  else
    -- Peak of the last emitted 125 ms window, not the needle: the needle is
    -- ballistic-smoothed, the peak is what decides clipping. gawk floors it
    -- at -60, so the floor means "at or below", not a measured value.
    local peak
    if vu.db == nil then
      peak = "—"
    elseif vu.db <= -60 then
      peak = "< -60 dBFS"
    else
      peak = string.format("%.1f dBFS", vu.db)
    end
    barWidget.setTooltip(gainRow({
      { key = "Microphone", value = "live" },
      { key = "Peak", value = peak },
    }))
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
