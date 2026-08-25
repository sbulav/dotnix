--!nonstrict
-- record-screen exposes its live state as a file under XDG_RUNTIME_DIR.
-- Poll cheaply and publish only transitions; this also repairs stale state
-- after a recorder crash because record-screen status validates the PID.

noctalia.state.set("recording", false)

local cmd = [[
last=
while :; do
  if @RECORD_SCREEN@ status >/dev/null 2>&1; then state=active; else state=inactive; fi
  if [ "$state" != "$last" ]; then
    printf '%s\n' "$state"
    last=$state
  fi
  sleep 0.5
done
]]

noctalia.runStream(cmd, function(line)
  noctalia.state.set("recording", noctalia.string.trim(line) == "active")
end)
