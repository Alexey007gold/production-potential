local util = require("util")

local function show_gui(player)
  local frame = player.gui.relative.add({
    type = "frame",
    name = "pp-main-frame",
    direction = "vertical",
    anchor = {
      gui = defines.relative_gui_type.production_gui,
      position = defines.relative_gui_position.right
    }
  })
  build_titlebar(frame)
  frame.style.minimal_width = 352

  local inner_frame = frame.add({
    type = "frame",
    style = "inside_deep_frame"
  })

  local scroll_pane = inner_frame.add({
    type = "scroll-pane"
  })
  scroll_pane.style.padding = { 4, 4, 4, 4 }
  scroll_pane.style.vertically_stretchable = true

  local sorted_potential = get_production_sorted_by_potential(player.force)
  local items = {}
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
    local bar = flow.add({
      type = "progressbar",
      style = "statistics_progressbar",
      value = item.potential
    })
    bar.style.horizontally_stretchable = true
    local label = flow.add({
      type = "label",
      style = "electric_usage_label",
      caption = util.format_number(item.actual_per_minute, true) .. "/m"
    })
    label.style.horizontal_align = "right"
    table.insert(items, { name = item.name, gui = flow })
  end
  global[player.index] = global[player.index] or {}
  global[player.index].items = items
end

function build_titlebar(frame)
  local flow = frame.add({
    name = "titlebar",
    type = "flow",
    direction = "horizontal",
  })
  flow.add({
    type = "label",
    style = "frame_title",
    caption = "Potential",
    ignored_by_interaction = true
  })
  flow.style.horizontal_spacing = 8
  flow.style.bottom_padding = 4

  local filler = flow.add({
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true
  })
  filler.style.right_margin = 4
  filler.style.height = 24
  filler.style.horizontally_stretchable = true

  flow.add({
    type = "sprite-button",
    style = "frame_action_button",
    sprite = "utility/search_white",
    hovered_sprite = "utility/search_black",
    tags = { action = "pp-toggle-search" }
  })
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

script.on_event({defines.events.on_gui_click, defines.events.on_gui_text_changed}, function(event)
  local player = game.get_player(event.player_index)
  local frame = player.gui.relative["pp-main-frame"]
  if not frame or not frame.valid then return end

  local action = event.element.tags.action
  if action == "pp-toggle-search" then
    if frame["titlebar"]["search-textfield"] then
       frame["titlebar"]["search-textfield"].destroy()
       apply_filter(event.player_index, "")
    else
      local search_field = frame["titlebar"].add({
        name = "search-textfield",
        type = "textfield",
        style = "titlebar_search_textfield",
        tags = { action = "pp-set-search-term" },
        index = 3
      })
      search_field.focus()
    end
  elseif action == "pp-set-search-term" then
    local filter = event.element.text
    apply_filter(event.player_index, filter)
  end
end)

function apply_filter(player_index, filter)
  for _, item in ipairs(global[player_index].items) do
    item.gui.visible = string.find(item.name, filter:lower()) and true or false
  end
end

script.on_event(defines.events.on_gui_opened, function(event)
  if event.gui_type == defines.gui_type.production then
    local player = game.get_player(event.player_index)
    local frame = player.gui.relative["pp-main-frame"]
    if not frame or not frame.valid then
      show_gui(player)
    end
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  if event.gui_type == defines.gui_type.production then
    local player = game.get_player(event.player_index)
    local frame = player.gui.relative["pp-main-frame"]
    if frame and frame.valid then
      frame.destroy()
    end
  end
end)
