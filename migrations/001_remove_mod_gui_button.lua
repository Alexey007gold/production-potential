local mod_gui = require("mod-gui")
for _, player in pairs(game.players) do
  local button_flow = mod_gui.get_button_flow(player)
  if button_flow and button_flow.valid then
    local pp_button = button_flow["pp-toggle-gui"]
    if pp_button and pp_button.valid then
      pp_button.destroy()
    end
  end
end
