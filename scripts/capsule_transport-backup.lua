-- scripts/capsule_transport.lua
local tube_connections = require("scripts.tube_connections")
local event_manager = require("scripts.events")

local capsule_transport = {}
capsule_transport.BASE_SPEED_TILES_PER_SEC = 10.0

local function get_direction_vector(flow_dir)
    local d = tonumber(flow_dir)
    if d then
        if d == 0 or d == defines.direction.north then return 0, -1
        elseif d == 1 or d == defines.direction.northeast then return 1, -1
        elseif d == 2 or d == defines.direction.east then return 1, 0
        elseif d == 3 or d == defines.direction.southeast then return 1, 1
        elseif d == 4 or d == defines.direction.south then return 0, 1
        elseif d == 5 or d == defines.direction.southwest then return -1, 1
        elseif d == 6 or d == defines.direction.west then return -1, 0
        elseif d == 7 or d == defines.direction.northwest then return -1, -1
        end
    end

    if type(flow_dir) == "string" then
        local lower = flow_dir:lower()
        if lower == "north" then return 0, -1
        elseif lower == "northeast" then return 1, -1
        elseif lower == "east" then return 1, 0
        elseif lower == "southeast" then return 1, 1
        elseif lower == "south" then return 0, 1
        elseif lower == "southwest" then return -1, 1
        elseif lower == "west" then return -1, 0
        elseif lower == "northwest" then return -1, -1
        end
    end

    return 0, 1
end

local function get_valid_entity(unit_num, member)
    if member and type(member) ~= "boolean" and type(member) ~= "number" and member.valid then
        return member
    end
    if type(member) == "table" and member.entity and member.entity.valid then
        return member.entity
    end
    if type(unit_num) == "number" then
        if storage.hubs and storage.hubs[unit_num] then
            local h = storage.hubs[unit_num]
            if h.entity and h.entity.valid then return h.entity end
            if h.valid then return h end
        end
        if storage.tubes and storage.tubes[unit_num] then
            local t = storage.tubes[unit_num]
            if t.entity and t.entity.valid then return t.entity end
            if t.valid then return t end
        end
        if storage.pumps and storage.pumps[unit_num] then
            local p = storage.pumps[unit_num]
            if p.entity and p.entity.valid then return p.entity end
            if p.valid then return p end
        end
    end
    return nil
end

local function get_network_segment_length(net_id)
    local net = storage.pneumatic_networks and storage.pneumatic_networks[net_id]
    if not net then return 1 end

    if net.length then
        return math.max(1, net.length)
    end

    local count = 0
    for k, member in pairs(net) do
        if k ~= "capsules" and k ~= "length" then
            local entity = get_valid_entity(k, member)
            if entity and entity.valid then
                count = count + 1
            end
        end
    end
    return math.max(1, count)
end

local function get_effective_flow(net_id, requested_flow)
    local net = storage.pneumatic_networks and storage.pneumatic_networks[net_id]
    if net then
        for u_num, member in pairs(net) do
            if u_num ~= "capsules" and u_num ~= "length" then
                local entity = get_valid_entity(u_num, member)
                if entity and entity.valid and entity.name == "pneumatic-pump" then
                    return entity.direction
                end
            end
        end
    end
    return requested_flow or defines.direction.south
end

local function get_segment_entry_position(net_id, fdx, fdy)
    local net = storage.pneumatic_networks and storage.pneumatic_networks[net_id]
    if not net then return nil end

    local min_proj = math.huge
    local entry_pos = nil

    for unit_num, member in pairs(net) do
        if unit_num ~= "capsules" and unit_num ~= "length" then
            local entity = get_valid_entity(unit_num, member)
            if entity and entity.valid then
                local proj = (entity.position.x * fdx) + (entity.position.y * fdy)
                if proj < min_proj then
                    min_proj = proj
                    entry_pos = { x = entity.position.x, y = entity.position.y }
                end
            end
        end
    end

    return entry_pos
end

local function is_valid_downstream_network(candidate_net_id, current_net_id)
    if not candidate_net_id or candidate_net_id == current_net_id then return false end
    local net = storage.pneumatic_networks and storage.pneumatic_networks[candidate_net_id]
    if not net then return false end

    for k, member in pairs(net) do
        if k ~= "capsules" and k ~= "length" then
            local entity = get_valid_entity(k, member)
            if entity and entity.valid then
                return true
            end
        end
    end
    return false
end

local function find_next_network_segment(current_net_id, flow_dir)
    local net = storage.pneumatic_networks and storage.pneumatic_networks[current_net_id]
    if not net then return nil, nil end

    local fdx, fdy = get_direction_vector(flow_dir)
    if fdx == 0 and fdy == 0 then return nil, nil end

    local max_proj = -math.huge
    local exit_entities = {}

    for unit_num, member in pairs(net) do
        if unit_num ~= "capsules" and unit_num ~= "length" then
            local entity = get_valid_entity(unit_num, member)
            if entity and entity.valid then
                local proj = (entity.position.x * fdx) + (entity.position.y * fdy)
                if proj > max_proj + 0.01 then
                    max_proj = proj
                    exit_entities = { entity }
                elseif math.abs(proj - max_proj) <= 0.01 then
                    table.insert(exit_entities, entity)
                end
            end
        end
    end

    local function check_entity_connections(entity)
        local conns = tube_connections.get_adjacent_connections(entity)
        if not conns then return nil end

        for _, conn in ipairs(conns) do
            local neighbor = conn.neighbor
            if neighbor and neighbor.valid then
                -- Check Hub Passthrough Channel Connection
                if conn.target_port and conn.target_port.pair_id then
                    local opp_port = tube_connections.get_opposite_passthrough_port(neighbor, conn.target_port)
                    if opp_port then
                        local hub_conns = tube_connections.get_adjacent_connections(neighbor)
                        for _, h_conn in ipairs(hub_conns) do
                            if h_conn.source_port and h_conn.source_port.port_id == opp_port.port_id then
                                local pt_neighbor = h_conn.neighbor
                                if pt_neighbor and pt_neighbor.valid then
                                    local pt_nets = storage.entity_to_network and storage.entity_to_network[pt_neighbor.unit_number]
                                    if pt_nets then
                                        for next_net_id, _ in pairs(pt_nets) do
                                            if is_valid_downstream_network(next_net_id, current_net_id) then
                                                return next_net_id, flow_dir
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                -- Direct Tube/Pump Connection
                local dx = neighbor.position.x - entity.position.x
                local dy = neighbor.position.y - entity.position.y
                if (dx * fdx + dy * fdy) > -0.1 then
                    local neighbor_nets = storage.entity_to_network and storage.entity_to_network[neighbor.unit_number]
                    if neighbor_nets then
                        for next_net_id, _ in pairs(neighbor_nets) do
                            if is_valid_downstream_network(next_net_id, current_net_id) then
                                return next_net_id, flow_dir
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    -- 1. Try downstream exit entities
    for _, exit_entity in ipairs(exit_entities) do
        local next_net_id, next_flow = check_entity_connections(exit_entity)
        if next_net_id then return next_net_id, next_flow end
    end

    -- 2. Fallback: check all segment entities
    for unit_num, member in pairs(net) do
        if unit_num ~= "capsules" and unit_num ~= "length" then
            local entity = get_valid_entity(unit_num, member)
            if entity and entity.valid then
                local next_net_id, next_flow = check_entity_connections(entity)
                if next_net_id then return next_net_id, next_flow end
            end
        end
    end

    return nil, nil
end

--- Locates an adjacent Hub entity at the terminal exit of a network segment
local function find_terminal_hub(net_id, flow_dir)
    local net = storage.pneumatic_networks and storage.pneumatic_networks[net_id]
    if not net then return nil end

    local fdx, fdy = get_direction_vector(flow_dir)
    if fdx == 0 and fdy == 0 then return nil end

    local max_proj = -math.huge
    local exit_entities = {}

    for unit_num, member in pairs(net) do
        if unit_num ~= "capsules" and unit_num ~= "length" then
            local entity = get_valid_entity(unit_num, member)
            if entity and entity.valid then
                local proj = (entity.position.x * fdx) + (entity.position.y * fdy)
                if proj > max_proj + 0.01 then
                    max_proj = proj
                    exit_entities = { entity }
                elseif math.abs(proj - max_proj) <= 0.01 then
                    table.insert(exit_entities, entity)
                end
            end
        end
    end

    -- 1. Check max projection exit entities (and their neighbors)
    for _, exit_entity in ipairs(exit_entities) do
        if exit_entity.name:find("capsule%-hub") or (storage.hubs and storage.hubs[exit_entity.unit_number]) then
            return exit_entity
        end

        local conns = tube_connections.get_adjacent_connections(exit_entity)
        if conns then
            for _, conn in ipairs(conns) do
                local neighbor = conn.neighbor
                if neighbor and neighbor.valid then
                    if neighbor.name:find("capsule%-hub") or (storage.hubs and storage.hubs[neighbor.unit_number]) then
                        local dx = neighbor.position.x - exit_entity.position.x
                        local dy = neighbor.position.y - exit_entity.position.y
                        if (dx * fdx + dy * fdy) > -0.1 then
                            return neighbor
                        end
                    end
                end
            end
        end
    end

    -- 2. Fallback scan across all network entities
    for unit_num, member in pairs(net) do
        if unit_num ~= "capsules" and unit_num ~= "length" then
            local entity = get_valid_entity(unit_num, member)
            if entity and entity.valid then
                if entity.name:find("capsule%-hub") or (storage.hubs and storage.hubs[entity.unit_number]) then
                    return entity
                end
                local conns = tube_connections.get_adjacent_connections(entity)
                if conns then
                    for _, conn in ipairs(conns) do
                        local neighbor = conn.neighbor
                        if neighbor and neighbor.valid then
                            if neighbor.name:find("capsule%-hub") or (storage.hubs and storage.hubs[neighbor.unit_number]) then
                                local dx = neighbor.position.x - entity.position.x
                                local dy = neighbor.position.y - entity.position.y
                                if (dx * fdx + dy * fdy) > -0.1 then
                                    return neighbor
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

--- Unpacks an arrived capsule back into physical inventory items inside the Hub
local function unload_capsule_into_hub(hub_entity, capsule)
    if not (hub_entity and hub_entity.valid) then return false end

    local inv = hub_entity.get_inventory(defines.inventory.chest)
    if not inv then
        if defines.inventory.hub then inv = hub_entity.get_inventory(defines.inventory.hub) end
    end
    if not inv then inv = hub_entity.get_inventory(1) end
    if not inv then return false end

    local shell_quality = capsule.capsule_quality or "normal"

    -- 1. Insert capsule shell into inventory (prefer Slot 1)
    local slot1 = inv[1]
    if slot1 and slot1.valid_for_read and slot1.name == "item-capsule" then
        slot1.count = slot1.count + 1
    else
        inv.insert({ name = "item-capsule", count = 1, quality = shell_quality })
    end

    -- 2. Insert cargo payload items into inventory
    if capsule.payload_name and capsule.cargo and capsule.cargo > 0 then
        inv.insert({
            name = capsule.payload_name,
            count = capsule.cargo,
            quality = capsule.payload_quality or "normal"
        })
    end

    return true
end

function capsule_transport.update_active_capsules(current_tick)
    if not storage.pneumatic_networks then return end
    local delta_tiles_per_tick = capsule_transport.BASE_SPEED_TILES_PER_SEC / 60

    for net_id, net_struct in pairs(storage.pneumatic_networks) do
        if net_struct.capsules then
            local capsule_list = {}
            for capsule_key, capsule in pairs(net_struct.capsules) do
                table.insert(capsule_list, { key = capsule_key, capsule = capsule })
            end

            for _, entry in ipairs(capsule_list) do
                local capsule_key = entry.key
                local capsule = entry.capsule

                if capsule.last_updated_tick ~= current_tick then
                    capsule.last_updated_tick = current_tick

                    local flow_dir = get_effective_flow(net_id, capsule.flow_direction)
                    
                    -- Handle pump flow direction flipping mid-transit
                    if capsule.last_flow_dir ~= nil and capsule.last_flow_dir ~= flow_dir then
                        capsule.progress = math.max(0.0, 1.0 - (capsule.progress or 0))
                        capsule.segment_start_pos = nil
                    end
                    capsule.last_flow_dir = flow_dir

                    local segment_length = get_network_segment_length(net_id)
                    local fdx, fdy = get_direction_vector(flow_dir)

                    if not capsule.segment_start_pos then
                        capsule.segment_start_pos = get_segment_entry_position(net_id, fdx, fdy) or capsule.last_position
                    end

                    capsule.progress = (capsule.progress or 0) + (delta_tiles_per_tick / segment_length)

                    if capsule.segment_start_pos then
                        local tile_offset = capsule.progress * segment_length
                        capsule.last_position = {
                            x = capsule.segment_start_pos.x + (fdx * tile_offset),
                            y = capsule.segment_start_pos.y + (fdy * tile_offset)
                        }
                    end

                    if capsule.progress >= 1.0 then
                        local next_net_id, next_flow = find_next_network_segment(net_id, flow_dir)
                        if next_net_id and storage.pneumatic_networks[next_net_id] then
                            local dest_net = storage.pneumatic_networks[next_net_id]
                            dest_net.capsules = dest_net.capsules or {}

                            capsule.source_hub = nil
                            capsule.origin = nil
                            capsule.source = nil
                            capsule.hub = nil
                            capsule.hub_unit_number = nil
                            capsule.owner = nil
                            capsule.from_hub = nil

                            capsule.flow_direction = next_flow or flow_dir
                            capsule.progress = math.max(0.0, capsule.progress - 1.0)

                            local n_fdx, n_fdy = get_direction_vector(capsule.flow_direction)
                            local new_start_pos = get_segment_entry_position(next_net_id, n_fdx, n_fdy)
                            capsule.segment_start_pos = new_start_pos or capsule.last_position or capsule.segment_start_pos

                            dest_net.capsules[capsule_key] = capsule
                            net_struct.capsules[capsule_key] = nil
                        else
                            -- Check if we arrived at a terminal Hub endpoint
                            local terminal_hub = find_terminal_hub(net_id, flow_dir)
                            if terminal_hub then
                                unload_capsule_into_hub(terminal_hub, capsule)
                                net_struct.capsules[capsule_key] = nil
                            else
                                capsule.progress = 1.0
                            end
                        end
                    end
                end
            end
        end
    end
end

event_manager.register(defines.events.on_tick, function(e)
    capsule_transport.update_active_capsules(e.tick)
end)

return capsule_transport