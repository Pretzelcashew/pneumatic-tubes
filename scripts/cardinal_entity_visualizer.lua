-- scripts/cardinal_entity_visualizer.lua
local CardinalCore = require("scripts.cardinal_entity_core")
local cardinal_vis = {}

local active_visuals = {}
local visualizer_enabled = true

local function clear_visuals(unit_number)
    local vis = active_visuals[unit_number]
    if vis then
        if vis.r_in and vis.r_in.valid then vis.r_in.destroy() end
        if vis.r_out and vis.r_out.valid then vis.r_out.destroy() end
        active_visuals[unit_number] = nil
    end
end

local function draw_visuals(entity, dir, mirrored)
    clear_visuals(entity.unit_number)
    
    if not visualizer_enabled then return end

    local input_pos, output_pos = CardinalCore.get_flow_positions(dir, entity.position, mirrored)

    local r_in = rendering.draw_circle{
        color = {r = 1, g = 0, b = 0, a = 1},
        radius = 0.4, filled = true, target = input_pos, surface = entity.surface, draw_on_ground = false
    }

    local r_out = rendering.draw_circle{
        color = {r = 0, g = 1, b = 0, a = 1},
        radius = 0.4, filled = true, target = output_pos, surface = entity.surface, draw_on_ground = false
    }

    active_visuals[entity.unit_number] = {r_in = r_in, r_out = r_out}
end

function cardinal_vis.toggle()
    visualizer_enabled = not visualizer_enabled

    if not visualizer_enabled then
        for unit_number, _ in pairs(active_visuals) do
            clear_visuals(unit_number)
        end
    else
        if storage.tracked_cardinal_entities then
            for _, data in pairs(storage.tracked_cardinal_entities) do
                if data.entity and data.entity.valid then
                    draw_visuals(data.entity, data.direction, data.mirrored)
                end
            end
        end
    end

    return visualizer_enabled
end

CardinalCore.on_created(function(event)
    draw_visuals(event.entity, event.direction, event.mirrored)
end)

CardinalCore.on_changed(function(event)
    draw_visuals(event.entity, event.direction, event.mirrored)
end)

CardinalCore.on_removed(function(event)
    clear_visuals(event.entity.unit_number)
end)

commands.add_command("toggle-cardinal-visuals", "Toggles the cardinal entity input/output circle visualizer on or off.", function(command)
    local is_active = cardinal_vis.toggle()
    if is_active then
        game.print("[Mod] Cardinal entity visualizer enabled.")
    else
        game.print("[Mod] Cardinal entity visualizer disabled.")
    end
end)

return cardinal_vis