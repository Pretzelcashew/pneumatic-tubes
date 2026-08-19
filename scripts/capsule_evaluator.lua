-- scripts/capsule_evaluator.lua
local capsule_evaluator = {}

-- Configurable max capsules per network
capsule_evaluator.MAX_CAPSULES_PER_NETWORK = 1

local function get_quality_name(q)
    if not q then return "normal" end
    if type(q) == "string" then return q end
    if type(q) == "table" or type(q) == "userdata" then
        return q.name or "normal"
    end
    return "normal"
end

local function get_capsule_capacity(quality)
    local q_name = get_quality_name(quality)

    if q_name == "legendary" then return 5
    elseif q_name == "epic" then return 4
    elseif q_name == "rare" then return 3
    elseif q_name == "uncommon" then return 2
    else return 1
    end
end

local function get_hub_inventory(hub_entity)
    if not (hub_entity and hub_entity.valid) then return nil end

    local inv = hub_entity.get_inventory(defines.inventory.chest)
    if inv and not inv.is_empty() then return inv end

    if defines.inventory.hub then
        inv = hub_entity.get_inventory(defines.inventory.hub)
        if inv and not inv.is_empty() then return inv end
    end

    inv = hub_entity.get_inventory(1)
    if inv and not inv.is_empty() then return inv end

    return nil
end

function capsule_evaluator.evaluate_hub_readiness(hub_entity, net_id)
    if not (hub_entity and hub_entity.valid) then
        return { ready = false, reason = "invalid_hub" }
    end

    -- 1. Check if Hub is set for sending
    local unit_number = hub_entity.unit_number
    local hub_data = storage.hubs and storage.hubs[unit_number]
    if hub_data and hub_data.send == false then
        return { ready = false, reason = "hub_not_sending" }
    end

    -- 2. Check Network Capacity directly from storage.pneumatic_networks[net_id]
    local net_struct = storage.pneumatic_networks and storage.pneumatic_networks[net_id]
    if net_struct then
        local active_count = 0
        if net_struct.capsules then
            for _ in pairs(net_struct.capsules) do
                active_count = active_count + 1
            end
        end

        if active_count >= capsule_evaluator.MAX_CAPSULES_PER_NETWORK then
            return { ready = false, reason = "network_full", active_capsules = active_count }
        end
    end

    -- 3. Safely Fetch Hub Inventory
    local inv = get_hub_inventory(hub_entity)
    if not inv or #inv == 0 then
        return { ready = false, reason = "no_inventory" }
    end

    -- 4. Check Slot 1 for Transport Capsule Shell
    local slot1_stack = inv[1]
    if not (slot1_stack and slot1_stack.valid_for_read and slot1_stack.name == "item-capsule") then
        return { ready = false, reason = "no_capsule_in_slot1" }
    end

    local carrier_quality = slot1_stack.quality
    local required_full_stacks = get_capsule_capacity(carrier_quality)

    -- 5. Aggregate item counts strictly grouped by item name AND quality
    local payload_candidates = {}

    for i = 2, #inv do
        local stack = inv[i]
        if stack and stack.valid_for_read then
            local max_stack_size = stack.prototype.stack_size
            local q_name = get_quality_name(stack.quality)
            local key = stack.name .. "@" .. q_name

            payload_candidates[key] = payload_candidates[key] or {
                name = stack.name,
                quality = stack.quality,
                quality_name = q_name,
                max_stack_size = max_stack_size,
                total_count = 0,
                slots = {}
            }

            payload_candidates[key].total_count = payload_candidates[key].total_count + stack.count
            table.insert(payload_candidates[key].slots, { slot_index = i, count = stack.count })
        end
    end

    -- 6. Check if total accumulated items of a SINGLE quality group meet required stack count
    for _, candidate in pairs(payload_candidates) do
        local required_items = candidate.max_stack_size * required_full_stacks
        if candidate.total_count >= required_items then
            return {
                ready = true,
                hub_entity = hub_entity,
                capsule_slot = 1,
                capsule_quality = carrier_quality,
                capacity = required_full_stacks,
                required_items = required_items,
                payload_name = candidate.name,
                payload_quality = candidate.quality,
                payload_quality_name = candidate.quality_name,
                payload_count = candidate.total_count,
                payload_slots = candidate.slots
            }
        end
    end

    return { ready = false, reason = "insufficient_cargo" }
end

return capsule_evaluator