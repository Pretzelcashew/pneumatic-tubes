-- scripts/capsulizer.lua
local capsule_evaluator = require("scripts.capsule_evaluator")
local capsule_routing = require("scripts.capsule_routing")

local capsulizer = {}

local function get_quality_name(q)
    if not q then return "normal" end
    if type(q) == "string" then return q end
    if type(q) == "table" or type(q) == "userdata" then
        return q.name or "normal"
    end
    return "normal"
end

--- Retrieves or creates the dedicated liminal surface for off-map item storage
local function get_liminal_surface()
    local surface = game.get_surface("liminal") or game.surfaces["liminal"]
    if not surface then
        surface = game.create_surface("liminal", {
            width = 1,
            height = 1,
            starting_area = "none"
        })
    end
    return surface
end

--- Spawns the hidden liminal holder entity on the liminal surface to hold physical items in transit
local function create_liminal_holder(position)
    local surface = get_liminal_surface()
    return surface.create_entity{
        name = "invisible-capsule-holder",
        position = position or {0, 0},
        force = "neutral"
    }
end

function capsulizer.dispatch_from_hub(hub, net_id, eval)
    local hub_inv = hub.get_inventory(defines.inventory.chest)
    if not (hub_inv and hub_inv.valid) then return false end

    -- 1. Spawn the liminal item holder entity
    local liminal_holder = create_liminal_holder({0, 0})
    if not (liminal_holder and liminal_holder.valid) then return false end

    local holder_inv = liminal_holder.get_inventory(defines.inventory.chest)
    if not (holder_inv and holder_inv.valid) then
        liminal_holder.destroy()
        return false
    end

    -- 2. Move Slot 1 (The capsule shell LuaItemStack reference)
    local capsule_stack = hub_inv[1]
    if capsule_stack and capsule_stack.valid_for_read then
        local inserted = holder_inv.insert(capsule_stack)
        if inserted > 0 then
            capsule_stack.count = capsule_stack.count - inserted
        end
    end

    -- 3. Move Payload Cargo (Strictly matching item name AND quality)
    local items_needed = eval.required_items or eval.payload_count
    local target_quality_name = eval.payload_quality_name or get_quality_name(eval.payload_quality)

    for i = 2, #hub_inv do
        if items_needed <= 0 then break end

        local stack = hub_inv[i]
        if stack and stack.valid_for_read and stack.name == eval.payload_name then
            if get_quality_name(stack.quality) == target_quality_name then
                local inserted = holder_inv.insert(stack)
                if inserted > 0 then
                    stack.count = stack.count - inserted
                    items_needed = items_needed - inserted
                end
            end
        end
    end

    -- 4. Store capsule reference
    local capsule_id = storage.next_capsule_id or 1
    local created_capsule = {
        id = capsule_id,
        holder = liminal_holder,
        source_hub_unit = hub.unit_number,
        net_id = net_id
    }
    storage.next_capsule_id = capsule_id + 1

    local net_struct = storage.pneumatic_networks and storage.pneumatic_networks[net_id]
    if net_struct then
        net_struct.capsules = net_struct.capsules or {}
        net_struct.capsules[capsule_id] = created_capsule
    end

    return true
end

function capsulizer.process_all_hubs()
    if not storage.hubs then return end

    for unit_number, hub_data in pairs(storage.hubs) do
        local hub = hub_data.entity
        if hub and hub.valid and hub_data.send then
            local net_ids = storage.entity_to_network and storage.entity_to_network[unit_number]
            if net_ids then
                local candidate_networks = {}

                for net_id, _ in pairs(net_ids) do
                    local eval = capsule_evaluator.evaluate_hub_readiness(hub, net_id)
                    if eval and eval.ready then
                        table.insert(candidate_networks, {
                            net_id = net_id,
                            eval = eval
                        })
                    end
                end

                if #candidate_networks > 0 then
                    local chosen = capsule_routing.select_next_network(hub, candidate_networks)
                    if chosen then
                        capsulizer.dispatch_from_hub(hub, chosen.net_id, chosen.eval)
                    end
                end
            end
        end
    end
end

-- Scan hubs for items to capsulize every 15 ticks
script.on_nth_tick(15, function()
    capsulizer.process_all_hubs()
end)

return capsulizer