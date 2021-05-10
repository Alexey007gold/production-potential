local mod_gui = require("mod-gui")
for _, player in pairs(game.players) do
  local button_flow = player.gui.top.mod_gui_button_flow
  local pp_button = button_flow["pp-toggle-gui"]
  if pp_button and pp_button.valid then
    pp_button.destroy()
  end
end
