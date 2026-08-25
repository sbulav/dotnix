--!nonstrict

local active = noctalia.state.get("recording") == true
barWidget.setColor("error")

local function render()
  barWidget.setVisible(active)
  if active then
    barWidget.setText("● REC")
    barWidget.setTooltip({
      { key = "Screen recording", value = "active" },
      { key = "Click", value = "stop and save" },
    })
  else
    barWidget.setText("")
    barWidget.setTooltip({})
  end
end

render()

noctalia.state.watch("recording", function(value)
  active = value == true
  render()
end)
