-- scripts/pneumatic_networks.lua
local tube_connections = require("scripts.tube_connections")

local pneumatic_networks = {}

local function allocate_fresh_network_id()
    storage.next_network_id = storage.next_network_id or 1
    local id = storage.next_network_id
    storage.next_network_id = id + 1
    return id
end

local function release_network_id(net_id)
    -- Intentionally left open for pool recycling if desired
end

local function bind_entity_to_network(unit_number, net_id)
    storage.entity_to_network = storage.entity_to_network or {}
    storage.entity_to_network[unit_number] = storage.entity_to_network[unit_number] or {}
    storage.entity_to_network[unit_number][net_id] = true
end

--------------------------------------------------------------------------------
-- REBUILD NETWORK CLUSTER (THREE-PASS GRAPH RESOLUTION)
--------------------------------------------------------------------------------

local function rebuild_cluster(cluster, excluded_unit_number)
    storage.pneumatic_networks = storage.pneumatic_networks or {}
    storage.entity_to_network = storage.entity_to_network or {}
    storage.primary_networks = storage.primary_networks or {}

    -- Step -1: Preserve all in-flight capsules in this cluster before wiping
    local active_capsules = {}
    for u_num, _ in pairs(cluster) do
        if u_num ~= excluded_unit_number then
            local old_nets = storage.entity_to_network[u_num]
            if old_nets then
                for net_id, _ in pairs(old_nets) do
                    local net = storage.pneumatic_networks[net_id]
                    if net and net.capsules then
                        for cap_id, capsule in pairs(net.capsules) do
                            active_capsules[cap_id] = capsule
                        end
                        net.capsules = nil
                    end
                end
            end
        end
    end

    -- Step 0: Unbind all entities in this cluster from their current networks
    for u_num, entity in pairs(cluster) do
        if u_num ~= excluded_unit_number then
            storage.primary_networks[u_num] = nil
            local old_nets = storage.entity_to_network[u_num]
            if old_nets then
                for net_id, _ in pairs(old_nets) do
                    local net = storage.pneumatic_networks[net_id]
                    if net then
                        net[u_num] = nil
                        local remaining = 0
                        for k, _ in pairs(net) do
                            if k ~= "capsules" and k ~= "length" then remaining = remaining + 1 end
                        end
                        if remaining == 0 then
                            storage.pneumatic_networks[net_id] = nil
                            release_network_id(net_id)
                        end
                    end
                end
                storage.entity_to_network[u_num] = nil
            end
        end
    end

    -- Step 1: Process Tube Networks (Merge <-> Merge unions + boundary Joiners)
    local processed_tubes = {}

    for u_num, entity in pairs(cluster) do
        if entity.valid and u_num ~= excluded_unit_number and not tube_connections.is_join_only(entity) and not processed_tubes[u_num] then
            local tube_queue = { entity }
            processed_tubes[u_num] = true

            local tube_group = {}
            local boundary_joiners = {}

            while #tube_queue > 0 do
                local curr_tube = table.remove(tube_queue, 1)
                tube_group[curr_tube.unit_number] = curr_tube

                local conns = tube_connections.get_adjacent_connections(curr_tube)
                for _, conn in ipairs(conns) do
                    local neighbor = conn.neighbor
                    if neighbor and neighbor.valid and neighbor.unit_number ~= excluded_unit_number then
                        if tube_connections.is_join_only(neighbor) then
                            boundary_joiners[neighbor.unit_number] = neighbor
                        else
                            if conn.source_port and conn.source_port.mode == "merge"
                               and conn.target_port and conn.target_port.mode == "merge" then
                                if cluster[neighbor.unit_number] and not processed_tubes[neighbor.unit_number] then
                                    processed_tubes[neighbor.unit_number] = true
                                    table.insert(tube_queue, neighbor)
                                end
                            end
                        end
                    end
                end
            end

            local net_id = allocate_fresh_network_id()
            local net_members = {}

            for t_num, tube in pairs(tube_group) do
                net_members[t_num] = tube
                bind_entity_to_network(t_num, net_id)
            end
            for j_num, joiner in pairs(boundary_joiners) do
                net_members[j_num] = joiner
                bind_entity_to_network(j_num, net_id)
            end

            storage.pneumatic_networks[net_id] = net_members

            -- Migrate preserved capsules into the newly built tube network
            for cap_id, capsule in pairs(active_capsules) do
                if capsule.current_net_id == nil or net_members[capsule.source_hub_unit] then
                    net_members.capsules = net_members.capsules or {}
                    net_members.capsules[cap_id] = capsule
                    capsule.current_net_id = net_id
                end
            end
        end
    end

    -- Step 2: Entity Primary Networks (Every Joiner gets 1 master network spanning itself + connected neighbors)
    for u_num, entity in pairs(cluster) do
        if entity.valid and u_num ~= excluded_unit_number and tube_connections.is_join_only(entity) then
            local conns = tube_connections.get_adjacent_connections(entity)
            if #conns > 0 then
                local entity_net_id = allocate_fresh_network_id()
                local net_members = { [u_num] = entity }
                bind_entity_to_network(u_num, entity_net_id)

                -- Save explicit reference to this Joiner's primary network
                storage.primary_networks[u_num] = entity_net_id

                for _, conn in ipairs(conns) do
                    local neighbor = conn.neighbor
                    if neighbor and neighbor.valid and neighbor.unit_number ~= excluded_unit_number then
                        net_members[neighbor.unit_number] = neighbor
                        bind_entity_to_network(neighbor.unit_number, entity_net_id)
                    end
                end

                storage.pneumatic_networks[entity_net_id] = net_members
            end
        end
    end

    -- Step 3: Isolated single-member fallback (ONLY for entities with 0 connections)
    for u_num, entity in pairs(cluster) do
        if entity.valid and u_num ~= excluded_unit_number then
            local net_ids = storage.entity_to_network[u_num]
            if not net_ids or table_size(net_ids) == 0 then
                local net_id = allocate_fresh_network_id()
                bind_entity_to_network(u_num, net_id)
                storage.pneumatic_networks[net_id] = { [u_num] = entity }
            end
        end
    end
end

function pneumatic_networks.rebuild_cluster(cluster, excluded_unit_number)
    rebuild_cluster(cluster, excluded_unit_number)
end

return pneumatic_networks