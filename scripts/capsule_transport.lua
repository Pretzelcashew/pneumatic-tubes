-- scripts/capsule_transport.lua
local tube_connections = require("scripts.tube_connections")

local capsule_transport = {}
local CAPSULE_SPEED = 0.2 -- Tiles moved per tick

--- Finds connected input/output networks for a pump
local function get_pump_networks(pump_entity)
    local in_net, out_net = nil, nil
    local conns = tube_connections.get_adjacent_connections(pump_entity)

    for _, conn in ipairs(conns) do
        local neighbor = conn.neighbor
        if neighbor and neighbor.valid then
            local neighbor_nets = storage.entity_to_network and storage.entity_to_network[neighbor.unit_number]
            if neighbor_nets then
                local net_id = next(neighbor_nets)
                if conn.source_port and conn.source_port.port_id == "input" then
                    in_net = net_id
                elseif conn.source_port and conn.source_port.port_id == "output" then
                    out_net = net_id
                end
            end
        end
    end
    return in_net, out_net
end

--- Figures out total tile length and flow direction (+1 or -1) for a single tube segment
local function get_segment_info(net_struct)
    local min_c, max_c = math.huge, -math.huge
    local axis = "x"
    local exit_pump = nil
    local flow_dir = 0
    local count = 0

    for unit_number, entity in pairs(net_struct) do
        if unit_number ~= "capsules" and unit_number ~= "length" and entity and entity.valid then
            count = count + 1
            if count == 1 then
                local orient = tube_connections.get_orientation(entity)
                if orient == "vertical" or entity.name == "capsule-hub-vertical" then
                    axis = "y"
                end
            end

            local val = entity.position[axis]
            if val < min_c then min_c = val end
            if val > max_c then max_c = val end

            -- Check if this entity is a pump dictating flow
            if entity.name == "pneumatic-pump" then
                local conns = tube_connections.get_adjacent_connections(entity)
                for _, conn in ipairs(conns) do
                    if conn.source_port and conn.source_port.port_id == "input" then
                        exit_pump = entity
                        -- Pulling toward this pump's position
                        flow_dir = (val >= max_c) and 1 or -1
                    end
                end
            end
        end
    end

    local length = math.max(1, max_c - min_c)
    return length, flow_dir, exit_pump
end

--- Moves capsule IDs along their network's 1D line and passes them across pumps
function capsule_transport.update()
    if not storage.pneumatic_networks then return end

    for net_id, net_struct in pairs(storage.pneumatic_networks) do
        if net_struct.capsules and next(net_struct.capsules) then
            local length, flow_dir, exit_pump = get_segment_info(net_struct)

            if flow_dir ~= 0 then
                for capsule_id, capsule in pairs(net_struct.capsules) do
                    -- Step 1D progress forward
                    capsule.progress = (capsule.progress or 0) + CAPSULE_SPEED

                    -- Reached the end of the segment
                    if capsule.progress >= length then
                        if exit_pump then
                            local _, next_net_id = get_pump_networks(exit_pump)
                            
                            -- Pass capsule ID to the next network
                            if next_net_id and storage.pneumatic_networks[next_net_id] then
                                net_struct.capsules[capsule_id] = nil
                                
                                local next_net = storage.pneumatic_networks[next_net_id]
                                next_net.capsules = next_net.capsules or {}
                                
                                capsule.net_id = next_net_id
                                capsule.progress = 0
                                next_net.capsules[capsule_id] = capsule
                            end
                        else
                            -- Dead end: hold at segment limit
                            capsule.progress = length
                        end
                    end
                end
            end
        end
    end
end

script.on_nth_tick(1, function()
    capsule_transport.update()
end)

return capsule_transport