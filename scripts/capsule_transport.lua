-- scripts/capsule_transport.lua
local event_manager = require("scripts.events")
local tube_connections = require("scripts.tube_connections")

local capsule_transport = {}

--------------------------------------------------------------------------------
-- FLOW DETERMINATION HELPERS
--------------------------------------------------------------------------------

--- Checks if a pump has 'input' connected to current_net_id and returns the downstream net_id connected to its 'output'.
local function get_pump_outflow_network(pump, current_net_id)
    if not (pump and pump.valid) then return nil end

    local conns = tube_connections.get_adjacent_connections(pump)
    local is_input_connected = false
    local output_net_id = nil

    for _, conn in ipairs(conns) do
        local neighbor = conn.neighbor
        local pump_port = conn.source_port

        if pump_port and neighbor and neighbor.valid then
            local neighbor_nets = storage.entity_to_network and storage.entity_to_network[neighbor.unit_number]
            if neighbor_nets then
                -- Input port pulls from current_net_id
                if pump_port.port_id == "input" and neighbor_nets[current_net_id] then
                    is_input_connected = true
                -- Output port pushes into target network
                elseif pump_port.port_id == "output" then
                    for target_id, _ in pairs(neighbor_nets) do
                        if target_id ~= current_net_id then
                            output_net_id = target_id
                            break
                        end
                    end
                end
            end
        end
    end

    if is_input_connected and output_net_id then
        return output_net_id
    end

    return nil
end

--- Scans network entities to find the active downstream network target driven by flow
local function get_network_outflow_target(net_id)
    local net = storage.pneumatic_networks and storage.pneumatic_networks[net_id]
    if not net then return nil end

    for unit_num, entity in pairs(net) do
        if unit_num ~= "capsules" and unit_num ~= "length" and entity and entity.valid then
            if entity.name == "pneumatic-pump" then
                local next_net_id = get_pump_outflow_network(entity, net_id)
                if next_net_id then
                    return { type = "network", target_net_id = next_net_id }
                end
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- CAPSULE TRANSFER CORE LOGIC
--------------------------------------------------------------------------------

--- Transfers a single capsule ID from source network to target network segment
function capsule_transport.transfer_capsule(capsule_id, source_net_id, target_net_id)
    local source_net = storage.pneumatic_networks and storage.pneumatic_networks[source_net_id]
    local target_net = storage.pneumatic_networks and storage.pneumatic_networks[target_net_id]

    if not (source_net and target_net and source_net.capsules and source_net.capsules[capsule_id]) then
        return false
    end

    local capsule = source_net.capsules[capsule_id]

    -- Remove from current network segment
    source_net.capsules[capsule_id] = nil

    -- Insert into downstream network segment
    target_net.capsules = target_net.capsules or {}
    target_net.capsules[capsule_id] = capsule
    capsule.current_net_id = target_net_id

    return true
end

--- Main tick process: Scans networks and moves capsules along active flow
function capsule_transport.update()
    if not storage.pneumatic_networks then return end

    local pending_transfers = {}

    for net_id, net_data in pairs(storage.pneumatic_networks) do
        if net_data.capsules and table_size(net_data.capsules) > 0 then
            local outflow = get_network_outflow_target(net_id)

            if outflow and outflow.type == "network" then
                for capsule_id, capsule in pairs(net_data.capsules) do
                    table.insert(pending_transfers, {
                        capsule_id = capsule_id,
                        from_net = net_id,
                        to_net = outflow.target_net_id
                    })
                end
            end
        end
    end

    for _, transfer in ipairs(pending_transfers) do
        capsule_transport.transfer_capsule(transfer.capsule_id, transfer.from_net, transfer.to_net)
    end
end

--------------------------------------------------------------------------------
-- EVENT REGISTRATION
--------------------------------------------------------------------------------

event_manager.register(defines.events.on_tick, capsule_transport.update)

--------------------------------------------------------------------------------
-- METATABLE SAFETY NET
--------------------------------------------------------------------------------

setmetatable(capsule_transport, {
    __index = function(tbl, key)
        return function(...) return nil end
    end
})

return capsule_transport