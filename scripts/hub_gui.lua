-- scripts/hub_gui.lua
local EventManager = require("scripts.events")

local HUB_NAMES = {
  ["capsule-hub-horizontal"] = true,
  ["capsule-hub-vertical"] = true
}

local COMPARATOR_OPTIONS = {"=", "≥", "≤", ">", "<", "≠"}
local COMPARATOR_VALUES = {
  [1] = "=",
  [2] = ">=",
  [3] = "<=",
  [4] = ">",
  [5] = "<",
  [6] = "!="
}
local COMPARATOR_INDEX_MAP = {
  ["="] = 1,
  [">="] = 2,
  ["<="] = 3,
  [">"] = 4,
  ["<"] = 5,
  ["!="] = 6
}

-- Fetch or initialize saved settings stored per hub
local function get_hub_data(entity)
  local unit_number = entity.unit_number
  storage.hubs = storage.hubs or {}
  
  if not storage.hubs[unit_number] then
    storage.hubs[unit_number] = {
      entity = entity,
      send = true,
      receive = true,
      filter = nil,               -- SignalID table for cargo
      comparator = "=",           -- Cargo quality comparator
      capsule_quality = "normal", -- Quality prototype name
      capsule_comparator = "="    -- Capsule quality comparator
    }
  else
    -- Refresh entity reference
    storage.hubs[unit_number].entity = entity
  end
  return storage.hubs[unit_number]
end

-- Apply full quality & comparator filters directly to inventory slots
local function apply_inventory_filters(entity, data)
  if not (entity and entity.valid) then return end
  local inv = entity.get_inventory(defines.inventory.chest)
  if not inv then return end

  -- Slot 1: Capsule Slot driven dynamically by UI settings
  inv.set_filter(1, {
    name = "item-capsule",
    quality = data.capsule_quality or "normal",
    comparator = data.capsule_comparator or "="
  })

  -- Slots 2-6: Cargo Slots with quality condition overlay
  local cargo_filter = nil
  if data.filter then
    local item_name = nil
    local item_quality = nil

    if type(data.filter) == "string" then
      item_name = data.filter
    elseif type(data.filter) == "table" and data.filter.name then
      if not data.filter.type or data.filter.type == "item" then
        item_name = data.filter.name
        item_quality = data.filter.quality
      end
    end

    if item_name then
      cargo_filter = {
        name = item_name,
        quality = item_quality or "normal",
        comparator = data.comparator or "="
      }
    end
  end

  for slot = 2, 6 do
    inv.set_filter(slot, cargo_filter)
  end
end

-- Close and remove any existing hub GUI for a player
local function close_gui(player)
  local gui = player.gui.relative.capsule_hub_gui
  if gui then
    gui.destroy()
  end
end

-- Construct the Hub GUI panel docked to the right of the container
local function open_gui(player, entity)
  close_gui(player)

  local data = get_hub_data(entity)
  local tags = { unit_number = entity.unit_number }

  apply_inventory_filters(entity, data)

  local frame = player.gui.relative.add{
    type = "frame",
    name = "capsule_hub_gui",
    direction = "vertical",
    anchor = {
      gui = defines.relative_gui_type.container_gui,
      position = defines.relative_gui_position.right
    },
    tags = tags
  }

  -- Title Bar with Refresh/Sync Button
  local title_flow = frame.add{ type = "flow", direction = "horizontal" }
  title_flow.style.vertical_align = "center"
  title_flow.add{ type = "label", caption = "Hub Configuration", style = "frame_title" }

  local drag_space = title_flow.add{ type = "empty-widget" }
  drag_space.style.horizontally_stretchable = true

  title_flow.add{
    type = "sprite-button",
    name = "capsule_hub_refresh_btn",
    sprite = "utility/refresh",
    style = "frame_action_button",
    tooltip = "Sync filter settings to container slots",
    tags = tags
  }

  local content = frame.add{ 
    type = "frame", 
    style = "inside_shallow_frame_with_padding", 
    direction = "vertical" 
  }

  content.add{
    type = "checkbox",
    name = "capsule_hub_chk_send",
    caption = "Allow Sending",
    state = data.send,
    tags = tags
  }

  content.add{
    type = "checkbox",
    name = "capsule_hub_chk_receive",
    caption = "Allow Receiving",
    state = data.receive,
    tags = tags
  }

  -- Cargo Filter Row
  local cargo_flow = content.add{ type = "flow", direction = "horizontal" }
  cargo_flow.style.vertical_align = "center"
  cargo_flow.style.top_margin = 8

  cargo_flow.add{ type = "label", caption = "Cargo Filter: " }
  cargo_flow.add{
    type = "drop-down",
    name = "capsule_hub_cargo_comp_dd",
    items = COMPARATOR_OPTIONS,
    selected_index = COMPARATOR_INDEX_MAP[data.comparator] or 1,
    tags = tags
  }
  cargo_flow.add{
    type = "choose-elem-button",
    name = "capsule_hub_filter_elem",
    elem_type = "signal",
    signal = data.filter,
    tags = tags
  }

  -- Capsule Quality Row
  local capsule_flow = content.add{ type = "flow", direction = "horizontal" }
  capsule_flow.style.vertical_align = "center"
  capsule_flow.style.top_margin = 4

  capsule_flow.add{ type = "label", caption = "Capsule Quality: " }
  capsule_flow.add{
    type = "drop-down",
    name = "capsule_hub_capsule_comp_dd",
    items = COMPARATOR_OPTIONS,
    selected_index = COMPARATOR_INDEX_MAP[data.capsule_comparator] or 1,
    tags = tags
  }
  capsule_flow.add{
    type = "choose-elem-button",
    name = "capsule_hub_capsule_quality_elem",
    elem_type = "quality",
    quality = data.capsule_quality or "normal",
    tags = tags
  }
end

-- GUI Events
EventManager.register(defines.events.on_gui_opened, function(event)
  if event.gui_type == defines.gui_type.entity and event.entity and HUB_NAMES[event.entity.name] then
    local player = game.get_player(event.player_index)
    if player then open_gui(player, event.entity) end
  end
end)

EventManager.register(defines.events.on_gui_closed, function(event)
  if event.gui_type == defines.gui_type.entity and event.entity and HUB_NAMES[event.entity.name] then
    local player = game.get_player(event.player_index)
    if player then close_gui(player) end
  end
end)

EventManager.register(defines.events.on_gui_click, function(event)
  local name = event.element.name
  if name == "capsule_hub_refresh_btn" then
    local tags = event.element.tags
    if tags and tags.unit_number and storage.hubs[tags.unit_number] then
      local data = storage.hubs[tags.unit_number]
      apply_inventory_filters(data.entity, data)

      local player = game.get_player(event.player_index)
      if player then
        player.create_local_flying_text{
          text = "Filters synced!",
          position = player.position
        }
        player.play_sound{ path = "utility/confirm" }
      end
    end
  end
end)

EventManager.register(defines.events.on_gui_checked_state_changed, function(event)
  local name = event.element.name
  if name == "capsule_hub_chk_send" or name == "capsule_hub_chk_receive" then
    local tags = event.element.tags
    if tags and tags.unit_number and storage.hubs[tags.unit_number] then
      local data = storage.hubs[tags.unit_number]
      if name == "capsule_hub_chk_send" then data.send = event.element.state
      elseif name == "capsule_hub_chk_receive" then data.receive = event.element.state end
    end
  end
end)

EventManager.register(defines.events.on_gui_selection_state_changed, function(event)
  local name = event.element.name
  local tags = event.element.tags
  if tags and tags.unit_number and storage.hubs[tags.unit_number] then
    local data = storage.hubs[tags.unit_number]
    local val = COMPARATOR_VALUES[event.element.selected_index] or "="
    
    if name == "capsule_hub_cargo_comp_dd" then data.comparator = val
    elseif name == "capsule_hub_capsule_comp_dd" then data.capsule_comparator = val end

    apply_inventory_filters(data.entity, data)
  end
end)

EventManager.register(defines.events.on_gui_elem_changed, function(event)
  local name = event.element.name
  local tags = event.element.tags
  if tags and tags.unit_number and storage.hubs[tags.unit_number] then
    local data = storage.hubs[tags.unit_number]
    
    if name == "capsule_hub_filter_elem" then data.filter = event.element.elem_value
    elseif name == "capsule_hub_capsule_quality_elem" then data.capsule_quality = event.element.elem_value end

    apply_inventory_filters(data.entity, data)
  end
end)

-- Entity Settings Copy/Paste (Pipette Settings Feature)
EventManager.register(defines.events.on_entity_settings_pasted, function(event)
  local source = event.source
  local destination = event.destination

  if source and source.valid and HUB_NAMES[source.name] and
     destination and destination.valid and HUB_NAMES[destination.name] then

    local source_data = get_hub_data(source)
    local dest_data = get_hub_data(destination)

    dest_data.send = source_data.send
    dest_data.receive = source_data.receive
    dest_data.filter = source_data.filter
    dest_data.comparator = source_data.comparator
    dest_data.capsule_quality = source_data.capsule_quality
    dest_data.capsule_comparator = source_data.capsule_comparator

    apply_inventory_filters(destination, dest_data)

    local player = game.get_player(event.player_index)
    if player then
      local gui = player.gui.relative.capsule_hub_gui
      if gui and gui.valid and gui.tags and gui.tags.unit_number == destination.unit_number then
        open_gui(player, destination)
      end

      player.create_local_flying_text{
        text = "Hub settings copied!",
        position = destination.position
      }
      player.play_sound{ path = "utility/confirm" }
    end
  end
end)

-- Save Hub Settings to Blueprint Tags
EventManager.register(defines.events.on_player_setup_blueprint, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local bp = player.blueprint_to_setup
  if not (bp and bp.valid_for_read) then
    bp = player.cursor_stack
  end
  if not (bp and bp.valid_for_read and bp.is_blueprint) then return end

  local mapping = event.mapping.get()
  for bp_index, entity in pairs(mapping) do
    if entity and entity.valid and HUB_NAMES[entity.name] then
      local data = storage.hubs[entity.unit_number]
      if data then
        bp.set_blueprint_entity_tag(bp_index, "hub_settings", {
          send = data.send,
          receive = data.receive,
          filter = data.filter,
          comparator = data.comparator,
          capsule_quality = data.capsule_quality,
          capsule_comparator = data.capsule_comparator
        })
      end
    end
  end
end)

-- Entity Lifecycle Events
local function on_entity_created(event)
  local entity = event.entity or event.destination or event.created_entity
  if entity and entity.valid and HUB_NAMES[entity.name] then
    local data = get_hub_data(entity)
    
    -- Check if created from blueprint with custom tags
    local tags = event.tags
    if tags and tags.hub_settings then
      local s = tags.hub_settings
      data.send = s.send
      data.receive = s.receive
      data.filter = s.filter
      data.comparator = s.comparator
      data.capsule_quality = s.capsule_quality
      data.capsule_comparator = s.capsule_comparator
    end

    apply_inventory_filters(entity, data)
  end
end

EventManager.register(defines.events.on_built_entity, on_entity_created)
EventManager.register(defines.events.on_robot_built_entity, on_entity_created)
EventManager.register(defines.events.script_raised_built, on_entity_created)
EventManager.register(defines.events.script_raised_revive, on_entity_created)

local function on_entity_removed(event)
  local entity = event.entity
  if entity and entity.valid and HUB_NAMES[entity.name] and storage.hubs then
    storage.hubs[entity.unit_number] = nil
  end
end

EventManager.register(defines.events.on_entity_died, on_entity_removed)
EventManager.register(defines.events.on_player_mined_entity, on_entity_removed)
EventManager.register(defines.events.on_robot_mined_entity, on_entity_removed)
EventManager.register(defines.events.script_raised_destroy, on_entity_removed)