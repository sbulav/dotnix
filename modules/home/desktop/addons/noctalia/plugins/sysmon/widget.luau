--!nonstrict
-- Bar widget: one stat per instance, tooltip limited to that stat's own
-- rows (the whole reason this exists — the builtin sysmon tooltip dumps
-- every available stat). Data comes from noctalia.systemStats(), the same
-- sampler the builtin uses, so no shell readers are needed.

local stat = tostring(noctalia.getConfig("stat") or "cpu")

local GLYPH = {
  cpu = "cpu-usage",
  temp = "cpu-temperature",
  ram = "memory",
}
local NAME = {
  cpu = "CPU usage",
  temp = "CPU temperature",
  ram = "RAM used",
}

-- The stat setting is a select in plugin.toml, so the settings schema
-- constrains it — this catches a hand-edited config, loudly instead of
-- silently rendering cpu under the wrong label.
local valid = GLYPH[stat] ~= nil
barWidget.setGlyph(valid and GLYPH[stat] or "alert-triangle")

noctalia.setUpdateInterval(2000)

local function round(x)
  return math.floor(x + 0.5)
end

local function gib(mb)
  return string.format("%.1f GiB", mb / 1024)
end

function update()
  if not valid then
    barWidget.setText("?")
    barWidget.setTooltip({ { key = "sysmon", value = "unknown stat '" .. stat .. "'" } })
    return
  end
  local stats = noctalia.systemStats()
  if stats == nil then
    -- render the outage instead of freezing the last sample on screen
    barWidget.setText("--")
    barWidget.setTooltip({ { key = NAME[stat], value = "sampler unavailable" } })
    return
  end

  if stat == "temp" then
    local t = stats.cpu and stats.cpu.tempC
    if t == nil then
      barWidget.setText("--")
      barWidget.setTooltip({ { key = "CPU temperature", value = "unavailable" } })
    else
      barWidget.setText(string.format("%d°", round(t)))
      barWidget.setTooltip({ { key = "CPU temperature", value = string.format("%.1f°C", t) } })
    end
  elseif stat == "ram" then
    local ram = stats.ram or {}
    local pct = ram.usagePercent or 0
    barWidget.setText(string.format("%d%%", round(pct)))
    barWidget.setTooltip({
      { key = "RAM used", value = string.format("%d%%", round(pct)) },
      { key = "Used / total", value = gib(ram.usedMb or 0) .. " / " .. gib(ram.totalMb or 0) },
    })
  else -- cpu
    local cpu = stats.cpu or {}
    local pct = cpu.usagePercent or 0
    barWidget.setText(string.format("%d%%", round(pct)))
    local rows = { { key = "CPU usage", value = string.format("%d%%", round(pct)) } }
    if cpu.freqMhz ~= nil then
      local freq = string.format("%.2f GHz", cpu.freqMhz / 1000)
      if cpu.maxFreqMhz ~= nil and cpu.maxFreqMhz > 0 then
        freq = freq .. string.format(" / %.2f GHz", cpu.maxFreqMhz / 1000)
      end
      rows[#rows + 1] = { key = "CPU frequency", value = freq }
    end
    barWidget.setTooltip(rows)
  end
end
