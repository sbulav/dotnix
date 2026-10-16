--!nonstrict
-- One sleeping subscription watches state files and the recorder's pidfd.
-- It emits transitions immediately, including crashes, without idle commands.

noctalia.state.set("recording", false)

noctalia.runStream("exec @RECORD_SCREEN@ watch", function(line)
  noctalia.state.set("recording", noctalia.string.trim(line) == "active")
end)
