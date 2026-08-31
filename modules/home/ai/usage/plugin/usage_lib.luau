--!nonstrict

local M = {}

M.STALE_MS = 20 * 60 * 1000
M.UNKNOWN_MS = 2 * 60 * 60 * 1000

function M.round(value)
  return math.floor((tonumber(value) or 0) * 100 + 0.5)
end

function M.color(percent)
  local value = tonumber(percent) or 0
  if value >= 0.90 then
    return "#ff5c57"
  elseif value >= 0.70 then
    return "#f6c344"
  end
  return "#2ecc71"
end

function M.providerGlyph(providerId)
  return providerId == "codex" and "brand-openai" or "sparkles"
end

function M.ageMs(provider, nowMs)
  local stamp = tonumber(provider and provider.lastSuccessAtMs) or 0
  return stamp > 0 and math.max(0, nowMs - stamp) or M.UNKNOWN_MS + 1
end

function M.activeLimits(provider, nowMs)
  local result = {}
  if provider == nil or M.ageMs(provider, nowMs) > M.UNKNOWN_MS then
    return result
  end
  for _, limit in ipairs(provider.limits or {}) do
    local reset = tonumber(limit.resetsAtMs) or 0
    if reset == 0 or reset > nowMs then
      result[#result + 1] = limit
    end
  end
  return result
end

function M.summary(state, nowMs)
  local result = {
    worst = nil,
    degraded = false,
    stale = false,
    usableProviders = 0,
  }
  for _, provider in ipairs((state and state.providers) or {}) do
    if provider.probeOk ~= true then
      result.degraded = true
    end
    local limits = M.activeLimits(provider, nowMs)
    if #limits > 0 then
      result.usableProviders += 1
      if M.ageMs(provider, nowMs) > M.STALE_MS then
        result.stale = true
      end
      for _, limit in ipairs(limits) do
        if result.worst == nil or (tonumber(limit.percent) or 0) > (tonumber(result.worst.limit.percent) or 0) then
          result.worst = { provider = provider, limit = limit }
        end
      end
    end
  end
  return result
end

function M.ageText(ageMs)
  if ageMs < 60 * 1000 then
    return "just now"
  elseif ageMs < 60 * 60 * 1000 then
    return tostring(math.floor(ageMs / (60 * 1000))) .. "m ago"
  end
  return tostring(math.floor(ageMs / (60 * 60 * 1000))) .. "h ago"
end

function M.resetText(resetAtMs, nowMs)
  local remaining = (tonumber(resetAtMs) or 0) - nowMs
  if remaining <= 0 then
    return "awaiting refresh"
  end
  local totalMinutes = math.floor(remaining / 60000)
  local days = math.floor(totalMinutes / 1440)
  local hours = math.floor((totalMinutes % 1440) / 60)
  local minutes = totalMinutes % 60
  if days > 0 then
    return string.format("resets in %dd %dh", days, hours)
  elseif hours > 0 then
    return string.format("resets in %dh %dm", hours, minutes)
  end
  return string.format("resets in %dm", math.max(1, minutes))
end

function M.providerById(state, providerId)
  for _, provider in ipairs((state and state.providers) or {}) do
    if provider.id == providerId then
      return provider
    end
  end
  return { id = providerId, name = providerId == "claude" and "Claude Code" or "Codex", limits = {} }
end

return M
