--!nonstrict
-- The Noctalia service is the sole scheduler. It loads the last atomic cache,
-- refreshes once at shell startup, then every 15 minutes or on explicit IPC.

local stateFile = "@STATE_FILE@"
local running = false
local queued = false

local function publish(payload)
  if payload ~= nil and payload.providers ~= nil then
    noctalia.state.set("usage", payload)
  end
end

local function loadCache()
  local raw = noctalia.readFile(stateFile)
  if raw == nil or raw == "" then
    return
  end
  local payload = noctalia.json.decode(raw)
  publish(payload)
end

local function refresh(force)
  if running then
    queued = queued or force
    return
  end
  running = true
  noctalia.state.set("refreshing", true)
  noctalia.state.set("refreshError", "")

  local args = { "@AI_USAGE_UPDATE@" }
  if force then
    args[#args + 1] = "--force"
  end
  local launched = noctalia.runAsync(args, function(result)
    running = false
    noctalia.state.set("refreshing", false)
    if result.exitCode == 0 and not result.timedOut then
      local payload = noctalia.json.decode(result.stdout or "")
      if payload ~= nil then
        publish(payload)
      else
        noctalia.state.set("refreshError", "collector returned invalid data")
      end
    else
      noctalia.state.set("refreshError", result.timedOut and "collector timed out" or "collector failed")
      loadCache()
    end
    if queued then
      queued = false
      refresh(true)
    end
  end, 30000)

  if not launched then
    running = false
    noctalia.state.set("refreshing", false)
    noctalia.state.set("refreshError", "collector could not start")
  end
end

function update()
  refresh(false)
end

function onIpc(event, _payload)
  if event == "refresh" then
    refresh(true)
  end
end

noctalia.setUpdateInterval(15 * 60 * 1000)
loadCache()
refresh(false)
