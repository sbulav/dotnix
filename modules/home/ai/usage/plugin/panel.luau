--!nonstrict

local usage = require("./usage_lib.luau")
local state = noctalia.state.get("usage") or { providers = {} }
local refreshing = noctalia.state.get("refreshing") == true
local refreshError = tostring(noctalia.state.get("refreshError") or "")

local MONO = "JetBrainsMono Nerd Font"

local function requestRefresh()
  noctalia.runAsync({ "@NOCTALIA@", "msg", "plugin", "sab/ai_usage:collector", "all", "refresh" })
end

local function providerStatus(provider, now)
  local age = usage.ageMs(provider, now)
  if age > usage.UNKNOWN_MS then
    return "Unknown · no recent usable data", "error"
  elseif provider.probeOk ~= true then
    return "Cached · live check failed · " .. usage.ageText(age), "tertiary"
  elseif age > usage.STALE_MS then
    return "Stale · updated " .. usage.ageText(age), "tertiary"
  end
  return "Live · updated " .. usage.ageText(age), "on_surface_variant"
end

local function limitRows(provider, now)
  local children = {}
  local limits = usage.activeLimits(provider, now)
  for index, limit in ipairs(limits) do
    local color = usage.color(limit.percent)
    children[#children + 1] = ui.column({ key = provider.id .. "-limit-" .. tostring(index), gap = 5 }, {
      ui.row({ align = "center", gap = 8 }, {
        ui.label({ text = limit.label or "Limit", fontSize = 13, fontWeight = "medium", flexGrow = 1, maxLines = 1 }),
        ui.label({
          text = tostring(usage.round(limit.percent)) .. "%",
          fontSize = 13,
          fontWeight = "bold",
          fontFamily = MONO,
          color = color,
        }),
      }),
      ui.progress({ progress = tonumber(limit.percent) or 0, height = 7, fill = color, track = "surface_variant", radius = 4 }),
      ui.label({
        text = usage.resetText(limit.resetsAtMs, now),
        fontSize = 11,
        fontFamily = MONO,
        color = "on_surface_variant",
      }),
    })
  end
  if #children == 0 then
    children[#children + 1] = ui.label({
      text = (tonumber(provider.lastSuccessAtMs) or 0) > 0 and "No active limit windows" or "Waiting for the first successful check",
      fontSize = 12,
      color = "on_surface_variant",
    })
  end
  return children
end

local function providerCard(provider, now)
  local status, statusColor = providerStatus(provider, now)
  local imagePath = "assets/claude.svg"
  if provider.id == "codex" then
    imagePath = noctalia.isDarkMode() and "assets/codex.svg" or "assets/codex-light.svg"
  end
  local content = {
    ui.row({ align = "center", gap = 10 }, {
      ui.image({ path = imagePath, width = 25, height = 25, fit = "contain" }),
      ui.column({ gap = 1, flexGrow = 1 }, {
        ui.label({ text = provider.name or provider.id, fontSize = 16, fontWeight = "bold" }),
        ui.label({
          text = (provider.tierLabel and provider.tierLabel ~= "") and provider.tierLabel or "Plan unavailable",
          fontSize = 11,
          color = "on_surface_variant",
        }),
      }),
      ui.label({ text = status, fontSize = 10, color = statusColor, maxWidth = 180, textAlign = "right", maxLines = 2 }),
    }),
  }
  for _, child in ipairs(limitRows(provider, now)) do
    content[#content + 1] = child
  end
  if provider.probeOk ~= true and provider.statusText and provider.statusText ~= "" then
    content[#content + 1] = ui.column({ fill = "error_container/0.35", radius = 8, padding = 9, gap = 3 }, {
      ui.label({ text = provider.statusText, fontSize = 11, fontWeight = "bold", color = "on_error_container" }),
      ui.label({ text = provider.helpText or "", fontSize = 10, color = "on_error_container", maxLines = 2 }),
    })
  end
  return ui.column({
    key = provider.id,
    fill = "surface_variant/0.35",
    border = "outline_variant/0.65",
    borderWidth = 1,
    radius = 14,
    padding = 13,
    gap = 12,
  }, content)
end

local function render()
  local now = noctalia.nowMs()
  local summary = usage.summary(state, now)
  local headline = "No usable limit data"
  local headlineMeta = "Claude Code and Codex"
  local headlineColor = "on_surface_variant"
  local headlineProgress = 0
  if summary.worst ~= nil then
    local provider = summary.worst.provider
    local limit = summary.worst.limit
    headline = (provider.name or provider.id) .. " · " .. (limit.label or "Limit")
    headlineMeta = tostring(usage.round(limit.percent)) .. "% used · " .. usage.resetText(limit.resetsAtMs, now)
    headlineColor = usage.color(limit.percent)
    headlineProgress = tonumber(limit.percent) or 0
  end

  local providers = {
    providerCard(usage.providerById(state, "claude"), now),
    providerCard(usage.providerById(state, "codex"), now),
  }
  local refreshCaption = refreshing and "Refreshing" or "Refresh"
  local footer = refreshError ~= "" and refreshError or "Automatic refresh every 15 minutes"

  panel.render(ui.column({ padding = 16, gap = 13, flexGrow = 1 }, {
    ui.row({ align = "center", gap = 10 }, {
      ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({ text = "AI capacity", fontSize = 19, fontWeight = "bold" }),
        ui.label({ text = "The tightest live subscription constraint", fontSize = 11, color = "on_surface_variant" }),
      }),
      ui.button({
        key = "refresh",
        text = refreshCaption,
        glyph = "refresh",
        variant = "ghost",
        controlSize = "sm",
        enabled = not refreshing,
        tooltip = "Refresh Claude and Codex limits",
        onClick = requestRefresh,
      }),
    }),
    ui.column({ gap = 5 }, {
      ui.row({ align = "center", gap = 8 }, {
        ui.label({ text = headline, fontSize = 12, fontWeight = "medium", flexGrow = 1, maxLines = 1 }),
        ui.label({ text = headlineMeta, fontSize = 11, fontFamily = MONO, color = headlineColor }),
      }),
      ui.progress({ progress = headlineProgress, height = 4, fill = headlineColor, track = "surface_variant", radius = 2 }),
    }),
    ui.scroll({ flexGrow = 1, gap = 12 }, providers),
    ui.label({
      text = footer,
      fontSize = 10,
      color = refreshError ~= "" and "error" or "on_surface_variant",
      textAlign = "center",
    }),
  }))
end

panel.setWantsSecondTicks(true)
function update()
  render()
end
noctalia.state.watch("usage", function(value)
  state = value or { providers = {} }
  render()
end)
noctalia.state.watch("refreshing", function(value)
  refreshing = value == true
  render()
end)
noctalia.state.watch("refreshError", function(value)
  refreshError = tostring(value or "")
  render()
end)
render()
