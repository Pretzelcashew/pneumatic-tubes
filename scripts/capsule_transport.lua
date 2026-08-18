-- scripts/capsule_transport.lua
local event_manager = require("scripts.events")
local tube_connections = require("scripts.tube_connections")

local capsule_transport = {}

--------------------------------------------------------------------------------
-- UNIVERSAL SEGMENT FLOW EVALUATION
--------------------------------------------------------------------------------

--- Evaluates the flow state for any given network segment ID
function capsule_transport.get_segment_flow(net_id)
    local net = storage.pneumatic_networks and storage.pneumatic_networks[net_id]
    if not net then
        return { status = "No Flow", flow_type = "none" }
    end

    local outflow_targets = {}
    local inflow_sources = {}

    for unit_num, entity in pairs(net) do
        if unit_num ~= "capsules" and unit_num ~= "length" and entity and entity.valid then
            if entity.name == "pneumatic-pump" then
                local conns = tube_connections.get_adjacent_connections(entity)
                local input_net_id = nil
                local output_net_id = nil

                for _, conn in ipairs(conns) do
                    local neighbor = conn.neighbor
                    local port = conn.source_port
                    if port and neighbor and neighbor.valid then
                        local neighbor_nets = storage.entity_to_network and storage.entity_to_network[neighbor.unit_number]
                        if neighbor_nets then
                            for target_id, _ in pairs(neighbor_nets) do
                                if port.port_id == "input" then
                                    input_net_id = target_id
                                elseif port.port_id == "output" then
                                    output_net_id = target_id
                                end
                            end
                        end
                    end
                end

                -- Pushing air OUT of net_id into downstream output network
                if input_net_id == net_id and output_net_id and output_net_id ~= net_id then
                    table.insert(outflow_targets, output_net_id)
                end

                -- Pulling air INTO net_id from upstream input network
                if output_net_id == net_id and input_net_id and input_net_id ~= net_id then
                    table.insert(inflow_sources, input_net_id)
                end
            end
        end
    end

    if #outflow_targets > 0 and #inflow_sources == 0 then
        return {
            status = "Outward",
            flow_type = "outward",
            target_net_id = outflow_targets[1],
            outflow_targets = outflow_targets
        }
    elseif #inflow_sources > 0 and #outflow_targets == 0 then
        return {
            status = "Inward",
            flow_type = "inward",
            source_net_id = inflow_sources[1],
            inflow_sources = inflow_sources
        }
    elseif #outflow_targets > 0 and #inflow_sources > 0 then
        return { status = "Conflict", flow_type = "conflict" }
    else
        return { status = "No Flow", flow_type = "none" }
    end
end

--------------------------------------------------------------------------------
-- CAPSULE TRANSFER LOGIC
--------------------------------------------------------------------------------

function capsule_transport.transfer_capsule(capsule_id, source_net_id, target_net_id)
    local source_net = storage.pneumatic_networks and storage.pneumatic_networks[source_net_id]
    local target_net = storage.pneumatic_networks and storage.pneumatic_networks[target_net_id]

    if not (source_net and target_net and source_net.capsules and source_net.capsules[capsule_id]) then
        return false
    end

    local capsule = source_net.capsules[capsule_id]
    source_net.capsules[capsule_id] = nil

    target_net.capsules = target_net.capsules or {}
    target_net.capsules[capsule_id] = capsule
    capsule.current_net_id = target_net_id

    return true
end

function capsule_transport.update()
    if not storage.pneumatic_networks then return end

    local pending_transfers = {}

    for net_id, net_data in pairs(storage.pneumatic_networks) do
        if net_data.capsules and table_size(net_data.capsules) > 0 then
            local flow = capsule_transport.get_segment_flow(net_id)

            if flow.flow_type == "outward" and flow.target_net_id then
                for capsule_id, capsule in pairs(net_data.capsules) do
                    table.insert(pending_transfers, {
                        capsule_id = capsule_id,
                        from_net = net_id,
                        to_net = flow.target_net_id
                    })
                end
            end
        end
    end

    for _, transfer in ipairs(pending_transfers) do
        capsule_transport.transfer_capsule(transfer.capsule_id, transfer.from_net, transfer.to_net)
    end
end

event_manager.register(defines.events.on_tick, capsule_transport.update)

setmetatable(capsule_transport, {
    __index = function(tbl, key)
        return function(...) return nil end
    end
})

return capsule_transport