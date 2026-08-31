--!nonstrict

local usage = require("./usage_lib.luau")
local state = noctalia.state.get("usage") or { providers = {} }
local refreshing = noctalia.state.get("refreshing") == true

local function render()
  local now = noctalia.nowMs()
  local summary = usage.summary(state, now)
  if summary.worst == nil then
    barWidget.setGlyph("sparkles")
    barWidget.setText("AI ?")
    barWidget.setColor("on_surface_variant")
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setTooltip({
      { key = "AI capacity", value = refreshing and "refreshing" or "no usable limits" },
      { key = "Left click", value = "details" },
      { key = "Right click", value = "refresh" },
    })
    return
  end

  local provider = summary.worst.provider
  local limit = summary.worst.limit
  local color = usage.color(limit.percent)
  local marker = ""
  if summary.degraded then
    marker = " !"
  elseif summary.stale then
    marker = " ~"
  end
  barWidget.setGlyph(usage.providerGlyph(provider.id))
  barWidget.setText("AI " .. tostring(usage.round(limit.percent)) .. "%" .. marker)
  barWidget.setColor(color)
  barWidget.setGlyphColor(color)

  local rows = {
    { key = provider.name or provider.id, value = (limit.label or "Limit") .. " · " .. tostring(usage.round(limit.percent)) .. "%" },
  }
  for _, current in ipairs((state and state.providers) or {}) do
    for _, item in ipairs(usage.activeLimits(current, now)) do
      rows[#rows + 1] = {
        key = (current.name or current.id) .. " · " .. (item.label or "Limit"),
        value = tostring(usage.round(item.percent)) .. "% · " .. usage.resetText(item.resetsAtMs, now),
      }
    end
  end
  if summary.degraded then
    rows[#rows + 1] = { key = "Status", value = "degraded · cached values shown" }
  elseif summary.stale then
    rows[#rows + 1] = { key = "Status", value = "stale · refresh pending" }
  end
  barWidget.setTooltip(rows)
end

noctalia.setUpdateInterval(30000)
noctalia.state.watch("usage", function(value)
  state = value or { providers = {} }
  render()
end)
noctalia.state.watch("refreshing", function(value)
  refreshing = value == true
  render()
end)
render()
