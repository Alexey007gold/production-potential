local util = require("util")

local function round(num, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

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
  local produced = 0;
  local all = 0;

  local sorted_potential = get_production_sorted_by_potential(player.force)
  for _, item in ipairs(sorted_potential) do
    if item.potential > 0 then
        produced = produced + 1
    end
    all = all + 1
  end

  build_titlebar(frame, produced, all)
  frame.style.minimal_width = 272

  local inner_frame = frame.add({
    type = "frame",
    style = "inside_deep_frame"
  })

  local scroll_pane = inner_frame.add({
    type = "scroll-pane"
  })
  scroll_pane.style.padding = { 4, 4, 4, 4 }
  scroll_pane.style.vertically_stretchable = true

  local items = {}
  for _, item in ipairs(sorted_potential) do
    local flow = scroll_pane.add({
      type = "flow",
      direction = "horizontal"
    })
    flow.style.vertical_align = "center"
    flow.add({
      type = "sprite",
      sprite = (item.type == "fluid" and "fluid/" or "item/") .. item.name,
      tooltip = (item.type == "fluid" and prototypes.fluid or prototypes.item)[item.name].localised_name
    })
    --local label = flow.add({
    --  type = "label",
    --  style = "electric_usage_label",
    --  caption = util.format_number(round(item.actual_per_minute, 1), true) .. "/m"
    --})
    --label.style.horizontal_align = "left"
    local bar = flow.add({
      type = "progressbar",
      --style = "progressbar_style",
      value = item.actual_per_minute / item.potential,
      tooltip = util.format_number(round(item.actual_per_minute, 1), true) .. "/m"
    })
    bar.style.horizontally_stretchable = true
    bar.style.minimal_width = 50
    local label = flow.add({
      type = "label",
      style = "electric_usage_label",
      caption = util.format_number(round(item.potential, 1), true) .. "/m"
    })
    label.style.horizontal_align = "right"
    table.insert(items, { name = item.name, gui = flow })
  end
  storage[player.index] = storage[player.index] or {}
  storage[player.index].items = items
end

function build_titlebar(frame, produced, all)
  local flow = frame.add({
    name = "titlebar",
    type = "flow",
    direction = "horizontal",
  })
  flow.add({
    type = "label",
    style = "frame_title",
    caption = "Potential (" .. tostring(produced) .. "/" .. tostring(all) .. ")",
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
    sprite = "utility/search",
    hovered_sprite = "utility/search",
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
      potential = (item.potential_per_second * 60)
    })
  end
  table.sort(sorted_potential, function(item1, item2)
    return item1.potential > item2.potential
  end)

  local producible = get_all_producible()
  for name, prototype in pairs(prototypes.item) do
    if not potential_production[name] and producible[name] and not prototype.hidden then
      table.insert(sorted_potential, {
        name = prototype.name,
        type = prototype.type,
        actual_per_minute = 0,
        potential = 0
      })
    end
  end

  return sorted_potential
end

function get_all_producible()
  local producible = {}
  for recipe_name, recipe in pairs(game.get_player(1).force.recipes) do
    for _, r in pairs(recipe.products) do
      producible[r.name] = true
    end
  end
  return producible
end

function get_potential_production(force)
  local potential_production = {}
  local function add_products(products, productivity_bonus, seconds)
    for _, output in pairs(products) do
      local product_amount = util.product_amount(output)
      local amount_per_second = (product_amount - (output.catalyst_amount or 0)) * (1 + productivity_bonus) / seconds
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
  for _, surface in pairs(game.surfaces) do
    --boiler, generator, offshore-pump?
    local entities = surface.find_entities_filtered({type = {"furnace", "assembling-machine", "rocket-silo"}, force = force})
    for _, machine in pairs(entities) do
      local recipe = machine.get_recipe()
      if recipe and not recipe.hidden_from_flow_stats then
        local recipe_time = recipe.energy
        local actual_time = recipe_time / machine.crafting_speed
        local productivity_bonus = machine.productivity_bonus
        add_products(recipe.products, productivity_bonus, actual_time)
      end
    end
    local mining_entities = surface.find_entities_filtered({type = {"mining-drill"}, force = force})
    for _, miner in pairs(mining_entities) do
      if miner.mining_target then
        local mineable_properties = miner.mining_target.prototype.mineable_properties
        local recipe_time = mineable_properties.mining_time
        local crafting_speed = miner.prototype.mining_speed * (1 + miner.speed_bonus)
        local actual_time = recipe_time / crafting_speed
        local productivity_bonus = miner.productivity_bonus
        add_products(mineable_properties.products, productivity_bonus, actual_time)
      end
    end
  end
  return potential_production
end

function get_actual_production(force, name, type)
  local actual = 0
  for _, surface in pairs(game.surfaces) do
      local statistics
      if type == "item" then
          statistics = force.get_item_production_statistics(surface)
      elseif type == "fluid" then
          statistics = force.get_fluid_production_statistics(surface)
      else
          return 0
      end
      actual = actual + statistics.get_flow_count({
          name = name,
          category = 'input', -- input == true is production
          precision_index = defines.flow_precision_index.ten_minutes,
          count = true
      })
  end
  return actual
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
        --style = "titlebar_search_textfield",
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
  for _, item in ipairs(storage[player_index].items) do
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
