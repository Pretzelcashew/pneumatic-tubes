-- scripts/capsule_routing.lua
local capsule_routing = {}

-- Round-robin state tracked per hub unit_number
local hub_routing_state = {}

function capsule_routing.select_next_network(hub_entity, candidate_networks)
    if not candidate_networks or #candidate_networks == 0 then
        return nil
    end

    local unit_number = hub_entity.unit_number
    hub_routing_state[unit_number] = hub_routing_state[unit_number] or { last_index = 0 }

    local state = hub_routing_state[unit_number]
    
    -- Cycle through candidate networks (round-robin selection)
    state.last_index = (state.last_index % #candidate_networks) + 1
    
    return candidate_networks[state.last_index]
end

-- Clean up routing state when a hub entity is destroyed
local event_manager = require("scripts.events")
event_manager.register(defines.events.on_object_destroyed, function(e)
    local unit_number = e.useful_id or e.unit_number
    if unit_number then
        hub_routing_state[unit_number] = nil
    end
end)

return capsule_routing