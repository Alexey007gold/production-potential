do
  local mod_gui = require("mod-gui")
  local function create_button(player)
    mod_gui.get_button_flow(player).add({
      name = "pp-toggle-gui",
      type = "button",
      caption = "PP",
      style = mod_gui.button_style
    })
  end

  script.on_init(function()
    for _, player in pairs(game.players) do
      create_button(player)
    end
  end)

  script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    create_button(player)
  end)
end

local util = require("util")

local function show_gui(player)
  local frame = player.gui.screen.add({
    type = "frame",
    name = "pp-main-frame",
    caption = "Production potential",
    direction = "vertical"
  })
  frame.force_auto_center()
  frame.style.maximal_height = 860

  local inner_frame = frame.add({
    type = "frame",
    style = "inside_deep_frame"
  })

  local scroll_pane = inner_frame.add({
    type = "scroll-pane"
  })

  local sorted_potential = get_production_sorted_by_potential(player.force)
  for _, item in ipairs(sorted_potential) do
    local flow = scroll_pane.add({
      type = "flow",
      direction = "horizontal"
    })
    flow.style.vertical_align = "center"
    flow.add({
      type = "sprite",
      sprite = (item.type == "item" and "item/" or "fluid/") .. item.name,
      tooltip = (item.type == "item" and game.item_prototypes or game.fluid_prototypes)[item.name].localised_name
    })
    flow.add({
      type = "progressbar",
      style = "statistics_progressbar",
      value = item.potential
    })
    local label = flow.add({
      type = "label",
      style = "electric_usage_label",
      caption = util.format_number(item.actual_per_minute, true) .. "/m"
    })
    label.style.horizontal_align = "right"
  end
  player.opened = frame
end

function get_production_sorted_by_potential(force)
  local potential_production = get_potential_production(force)
  local sorted_potential = {}
  for _, item in pairs(potential_production) do
    local actual = get_actual_production(force, item.name, item.type)
    local actual_per_minute = actual / 10
    table.insert(sorted_potential, {
      name = item.name,
      type = item.type,
      actual_per_minute = actual_per_minute,
      potential = actual_per_minute / (item.potential_per_second * 60)
    })
  end
  table.sort(sorted_potential, function(item1, item2)
    return item1.potential > item2.potential
  end)
  return sorted_potential
end

function get_potential_production(force)
  local potential_production = {}
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered({type = {"furnace", "assembling-machine", "rocket-silo"}, force = force})
    for _, machine in pairs(entities) do
      local recipe = machine.get_recipe()
      if recipe then
        local recipe_time = recipe.energy
        local actual_time = recipe_time / machine.crafting_speed
        local productivity_multiplier = 1 + machine.productivity_bonus
        for _, output in pairs(recipe.products) do
          local product_amount = util.product_amount(output)
          local amount_per_second = (product_amount - (output.catalyst_amount or 0)) * productivity_multiplier / actual_time
          if amount_per_second > 0 then
            if not potential_production[output.name] then
              potential_production[output.name] = {
                name = output.name,
                type = output.type,
                potential_per_second = 0
              }
            end
            potential_production[output.name].potential_per_second = amount_per_second + potential_production[output.name].potential_per_second
          end
        end
      end
    end
  end
  return potential_production
end

function get_actual_production(force, name, type)
  local statistics
  if type == "item" then
    statistics = force.item_production_statistics
  elseif type == "fluid" then
    statistics = force.fluid_production_statistics
  else
    return 0
  end
  return statistics.get_flow_count({
    name = name,
    input = true, -- input == true is production
    precision_index = defines.flow_precision_index.ten_minutes,
     count = true
  })
end

script.on_event(defines.events.on_gui_click, function(event)
  if event.element.name == "pp-toggle-gui" then
    local player = game.get_player(event.player_index)
    local center = player.gui.screen
    if center["pp-main-frame"] then
      center["pp-main-frame"].destroy()
    else
      show_gui(player)
    end
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  if event.element and event.element.name == "pp-main-frame" then
    event.element.destroy()
  end
end)
