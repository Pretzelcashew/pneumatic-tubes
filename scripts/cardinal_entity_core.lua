-- scripts/cardinal_entity_core.lua
local EventManager = require("scripts.events")
local cardinal_core = {}

-- MULTI-ENTITY CONFIGURATION: Pneumatic and cardinal entities tracked by the core
local TARGET_ENTITIES = {
    "pneumatic-pump","capsule-hub-horizontal","capsule-hub-vertical","pneumatic-tube"

}

-- Helper function to check if a table contains a specific value
local function table_contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

local listeners = {
    created = {},
    changed = {},
    removed = {}
}

function cardinal_core.on_created(fn) table.insert(listeners.created, fn) end
function cardinal_core.on_changed(fn) table.insert(listeners.changed, fn) end
function cardinal_core.on_removed(fn) table.insert(listeners.removed, fn) end

function cardinal_core.get_flow_positions(dir, pos, mirrored)
    local input_pos, output_pos = {x = pos.x, y = pos.y}, {x = pos.x, y = pos.y}

    if dir == defines.direction.north then
        input_pos  = {x = pos.x, y = pos.y + 1}
        output_pos = {x = pos.x, y = pos.y - 1}
    elseif dir == defines.direction.east then
        input_pos  = {x = pos.x - 1, y = pos.y}
        output_pos = {x = pos.x + 1, y = pos.y}
    elseif dir == defines.direction.south then
        input_pos  = {x = pos.x, y = pos.y - 1}
        output_pos = {x = pos.x, y = pos.y + 1}
    elseif dir == defines.direction.west then
        input_pos  = {x = pos.x + 1, y = pos.y}
        output_pos = {x = pos.x - 1, y = pos.y}
    end

    if mirrored then
        if dir == defines.direction.north or dir == defines.direction.south then
            input_pos.x, output_pos.x = 2 * pos.x - input_pos.x, 2 * pos.x - output_pos.x
        else
            input_pos.y, output_pos.y = 2 * pos.y - input_pos.y, 2 * pos.y - output_pos.y
        end
    end

    return input_pos, output_pos
end

local function notify_listeners(list, data)
    for _, fn in ipairs(list) do
        fn(data)
    end
end

local function on_entity_created(event)
    local entity = event.created_entity or event.entity
    if entity and entity.valid then
        local dir = entity.direction
        local mirrored = entity.mirroring or false

        storage.tracked_cardinal_entities = storage.tracked_cardinal_entities or {}
        storage.tracked_cardinal_entities[entity.unit_number] = {
            entity = entity,
            direction = dir,
            mirrored = mirrored
        }

        notify_listeners(listeners.created, {
            entity = entity,
            direction = dir,
            mirrored = mirrored
        })
    end
end

local function check_entity_update(event)
    local entity = event.created_entity or event.entity
    if entity and entity.valid and table_contains(TARGET_ENTITIES, entity.name) then
        storage.tracked_cardinal_entities = storage.tracked_cardinal_entities or {}
        local tracked = storage.tracked_cardinal_entities[entity.unit_number]
        if tracked then
            local new_dir = entity.direction
            local new_mirrored = entity.mirroring or false

            if tracked.direction ~= new_dir or tracked.mirrored ~= new_mirrored then
                tracked.direction = new_dir
                tracked.mirrored = new_mirrored

                notify_listeners(listeners.changed, {
                    entity = entity,
                    direction = new_dir,
                    mirrored = new_mirrored
                })
            end
        end
    end
end

local function on_entity_cloned(event)
    local destination = event.destination
    if destination and destination.valid then
        on_entity_created({entity = destination})
    end
end

local function on_entity_removed(event)
    local entity = event.entity
    storage.tracked_cardinal_entities = storage.tracked_cardinal_entities or {}
    if entity and entity.valid and storage.tracked_cardinal_entities[entity.unit_number] then
        storage.tracked_cardinal_entities[entity.unit_number] = nil

        notify_listeners(listeners.removed, {
            entity = entity
        })
    end
end

-- Dynamically build the native filter array for all target entities
local entity_filters = {}
for _, name in ipairs(TARGET_ENTITIES) do
    table.insert(entity_filters, {filter = "name", name = name})
end

EventManager.register(defines.events.on_built_entity, on_entity_created, entity_filters)
EventManager.register(defines.events.on_robot_built_entity, on_entity_created, entity_filters)
EventManager.register(defines.events.script_raised_built, on_entity_created, entity_filters)
EventManager.register(defines.events.on_entity_cloned, on_entity_cloned, entity_filters)
EventManager.register(defines.events.script_raised_revive, on_entity_created, entity_filters)

EventManager.register(defines.events.on_player_mined_entity, on_entity_removed, entity_filters)
EventManager.register(defines.events.on_entity_died, on_entity_removed, entity_filters)
EventManager.register(defines.events.on_robot_mined_entity, on_entity_removed, entity_filters)
EventManager.register(defines.events.script_raised_destroy, on_entity_removed, entity_filters)

EventManager.register(defines.events.on_player_rotated_entity, check_entity_update)
EventManager.register(defines.events.on_player_flipped_entity, check_entity_update)

EventManager.register(defines.events.script_raised_set_tiles, function(event)
    storage.tracked_cardinal_entities = storage.tracked_cardinal_entities or {}
    for _, data in pairs(storage.tracked_cardinal_entities) do
        local tracked_entity = data.entity
        if tracked_entity and tracked_entity.valid then
            if tracked_entity.direction ~= data.direction or (tracked_entity.mirroring or false) ~= data.mirrored then
                check_entity_update({entity = tracked_entity})
            end
        end
    end
end)

return cardinal_core