local event_manager = require("scripts.events")
local gui_info = require("scripts.gui_info")
local tube_connections = require("scripts.tube_connections")

--------------------------------------------------------------------------------
-- HELPER & CLUSTER MANAGEMENT
--------------------------------------------------------------------------------

local function release_network_id(net_id)
    if not net_id then return end
    storage.free_network_ids = storage.free_network_ids or {}
    storage.free_network_ids[net_id] = true
end

local function allocate_fresh_network_id()
    storage.free_network_ids = storage.free_network_ids or {}

    local recycled_id = next(storage.free_network_ids)
    if recycled_id then
        storage.free_network_ids[recycled_id] = nil
        return recycled_id
    end

    storage.next_network_id = (storage.next_network_id or 0) + 1
    return storage.next_network_id
end

local function bind_entity_to_network(unit_number, net_id)
    storage.entity_to_network = storage.entity_to_network or {}
    storage.entity_to_network[unit_number] = storage.entity_to_network[unit_number] or {}
    storage.entity_to_network[unit_number][net_id] = true
end

local function sanitize_network_storage()
    if not storage.pneumatic_networks then return end
    storage.entity_to_network = storage.entity_to_network or {}

    for net_id, members in pairs(storage.pneumatic_networks) do
        for u_num, entity in pairs(members) do
            if not (entity and entity.valid) then
                members[u_num] = nil
                if storage.entity_to_network[u_num] then
                    storage.entity_to_network[u_num][net_id] = nil
                    if table_size(storage.entity_to_network[u_num]) == 0 then
                        storage.entity_to_network[u_num] = nil
                    end
                end
            end
        end
        if table_size(members) == 0 then
            storage.pneumatic_networks[net_id] = nil
            release_network_id(net_id)
        end
    end
end

local function gather_physical_cluster(initial_entities, excluded_unit_number)
    sanitize_network_storage()

    local cluster = {}
    local queue = {}
    local visited = {}

    if excluded_unit_number then
        visited[excluded_unit_number] = true
    end

    for _, e in ipairs(initial_entities) do
        if e and e.valid and tube_connections.is_connectable(e.name) then
            if not visited[e.unit_number] then
                visited[e.unit_number] = true
                cluster[e.unit_number] = e
                table.insert(queue, e)
            end
        end
    end

    while #queue > 0 do
        local current = table.remove(queue, 1)

        local conns = tube_connections.get_adjacent_connections(current)
        for _, conn in ipairs(conns) do
            local neighbor = conn.neighbor
            if neighbor and neighbor.valid and neighbor.unit_number ~= excluded_unit_number and not visited[neighbor.unit_number] then
                visited[neighbor.unit_number] = true
                cluster[neighbor.unit_number] = neighbor
                table.insert(queue, neighbor)
            end
        end
    end

    return cluster
end

local function rebuild_cluster(cluster, excluded_unit_number)
    storage.pneumatic_networks = storage.pneumatic_networks or {}
    storage.entity_to_network = storage.entity_to_network or {}

    for u_num, _ in pairs(cluster) do
        storage.entity_to_network[u_num] = nil
    end

    for net_id, members in pairs(storage.pneumatic_networks) do
        for u_num, _ in pairs(cluster) do
            members[u_num] = nil
        end
        if table_size(members) == 0 then
            storage.pneumatic_networks[net_id] = nil
            release_network_id(net_id)
        end
    end

    -- Rebuild Tube Networks (including passthrough channels)
    local processed_tubes = {}

    for u_num, entity in pairs(cluster) do
        if entity.valid and not tube_connections.is_join_only(entity) and not processed_tubes[u_num] then
            local tube_queue = {entity}
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

                            -- Pass-through traversal across hub channels
                            if conn.target_port and conn.target_port.mode == "join_passthrough" then
                                local opp_port = tube_connections.get_opposite_passthrough_port(neighbor, conn.target_port)
                                if opp_port then
                                    local opp_conns = tube_connections.get_adjacent_connections(neighbor)
                                    for _, opp_conn in ipairs(opp_conns) do
                                        if opp_conn.source_port.port_id == opp_port.port_id then
                                            local opp_neighbor = opp_conn.neighbor
                                            if opp_neighbor and opp_neighbor.valid
                                               and opp_neighbor.unit_number ~= excluded_unit_number
                                               and not tube_connections.is_join_only(opp_neighbor) then
                                                if cluster[opp_neighbor.unit_number] and not processed_tubes[opp_neighbor.unit_number] then
                                                    processed_tubes[opp_neighbor.unit_number] = true
                                                    table.insert(tube_queue, opp_neighbor)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
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
        end
    end

    -- Rebuild Direct Join-to-Join Networks
    for u_num, entity in pairs(cluster) do
        if entity.valid and tube_connections.is_join_only(entity) then
            local conns = tube_connections.get_adjacent_connections(entity)
            for _, conn in ipairs(conns) do
                local neighbor = conn.neighbor
                if neighbor and neighbor.valid and neighbor.unit_number ~= excluded_unit_number and tube_connections.is_join_only(neighbor) then
                    local netsA = storage.entity_to_network[entity.unit_number]
                    local netsB = storage.entity_to_network[neighbor.unit_number]
                    local already_connected = false

                    if netsA and netsB then
                        for id, _ in pairs(netsA) do
                            if netsB[id] then already_connected = true break end
                        end
                    end

                    if not already_connected then
                        local net_id = allocate_fresh_network_id()
                        local net_members = {
                            [entity.unit_number] = entity,
                            [neighbor.unit_number] = neighbor
                        }
                        bind_entity_to_network(entity.unit_number, net_id)
                        bind_entity_to_network(neighbor.unit_number, net_id)
                        storage.pneumatic_networks[net_id] = net_members
                    end
                end
            end
        end
    end

    -- Dedicated Internal Sub-Networks for Join Entities
    for u_num, entity in pairs(cluster) do
        if entity.valid and tube_connections.is_join_only(entity) then
            local net_ids = storage.entity_to_network[u_num]
            local has_sub_network = false

            if net_ids then
                for net_id, _ in pairs(net_ids) do
                    local members = storage.pneumatic_networks[net_id]
                    if members and table_size(members) == 1 then
                        has_sub_network = true
                        break
                    end
                end
            end

            if not has_sub_network then
                local net_id = allocate_fresh_network_id()
                bind_entity_to_network(u_num, net_id)
                storage.pneumatic_networks[net_id] = { [u_num] = entity }
            end
        end
    end

    -- Standalone Entities
    for u_num, entity in pairs(cluster) do
        if entity.valid then
            local net_ids = storage.entity_to_network[u_num]
            if not net_ids or table_size(net_ids) == 0 then
                local net_id = allocate_fresh_network_id()
                bind_entity_to_network(u_num, net_id)
                storage.pneumatic_networks[net_id] = { [u_num] = entity }
            end
        end
    end
end

--------------------------------------------------------------------------------
-- UI DATA PROVIDER
--------------------------------------------------------------------------------

local function get_network_info(entity)
    if not (entity and entity.valid) then return nil end
    sanitize_network_storage()

    local net_ids = storage.entity_to_network and storage.entity_to_network[entity.unit_number]
    if not net_ids or table_size(net_ids) == 0 then return nil end

    local info = {}
    for net_id, _ in pairs(net_ids) do
        local network_entities = storage.pneumatic_networks and storage.pneumatic_networks[net_id]
        if network_entities then
            table.insert(info, { key = "Network ID",  value = "#" .. tostring(net_id) })
            table.insert(info, { key = "Total Members", value = table_size(network_entities) })
        end
    end

    return #info > 0 and info or nil
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

local function on_entity_built(e)
    local entity = e.created_entity or e.entity or e.destination
    if not entity or not entity.valid then return end
    if not tube_connections.is_connectable(entity.name) then return end

    storage.pneumatic_networks = storage.pneumatic_networks or {}
    storage.entity_to_network = storage.entity_to_network or {}

    local u_num = entity.unit_number
    local is_join = tube_connections.is_join_only(entity)
    local conns = tube_connections.get_adjacent_connections(entity)

    if not is_join then
        ------------------------------------------------------------------------
        -- TUBE PLACEMENT
        ------------------------------------------------------------------------
        local adjacent_tube_nets = {}
        local adjacent_joiners = {}

        for _, conn in ipairs(conns) do
            local neighbor = conn.neighbor
            if neighbor and neighbor.valid then
                local n_num = neighbor.unit_number
                if tube_connections.is_join_only(neighbor) then
                    table.insert(adjacent_joiners, neighbor)

                    -- Check if building next to a passthrough channel
                    if conn.target_port and conn.target_port.mode == "join_passthrough" then
                        local opp_port = tube_connections.get_opposite_passthrough_port(neighbor, conn.target_port)
                        if opp_port then
                            local opp_conns = tube_connections.get_adjacent_connections(neighbor)
                            for _, opp_conn in ipairs(opp_conns) do
                                if opp_conn.source_port.port_id == opp_port.port_id then
                                    local opp_neighbor = opp_conn.neighbor
                                    if opp_neighbor and opp_neighbor.valid and not tube_connections.is_join_only(opp_neighbor) then
                                        local nets = storage.entity_to_network[opp_neighbor.unit_number]
                                        if nets then
                                            for net_id, _ in pairs(nets) do
                                                adjacent_tube_nets[net_id] = true
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    if conn.source_port and conn.source_port.mode == "merge"
                       and conn.target_port and conn.target_port.mode == "merge" then
                        local nets = storage.entity_to_network[n_num]
                        if nets then
                            for net_id, _ in pairs(nets) do
                                adjacent_tube_nets[net_id] = true
                            end
                        end
                    end
                end
            end
        end

        local target_net_id = nil
        local net_id_list = {}
        for net_id, _ in pairs(adjacent_tube_nets) do
            table.insert(net_id_list, net_id)
        end

        if #net_id_list == 0 then
            target_net_id = allocate_fresh_network_id()
            storage.pneumatic_networks[target_net_id] = {}
        else
            target_net_id = net_id_list[1]
            for i = 2, #net_id_list do
                local sec_net_id = net_id_list[i]
                local sec_members = storage.pneumatic_networks[sec_net_id]
                if sec_members then
                    for member_unum, member_ent in pairs(sec_members) do
                        storage.pneumatic_networks[target_net_id][member_unum] = member_ent
                        bind_entity_to_network(member_unum, target_net_id)
                        if storage.entity_to_network[member_unum] then
                            storage.entity_to_network[member_unum][sec_net_id] = nil
                        end
                    end
                end
                storage.pneumatic_networks[sec_net_id] = nil
                release_network_id(sec_net_id)
            end
        end

        storage.pneumatic_networks[target_net_id][u_num] = entity
        bind_entity_to_network(u_num, target_net_id)

        for _, joiner in ipairs(adjacent_joiners) do
            if not storage.pneumatic_networks[target_net_id][joiner.unit_number] then
                storage.pneumatic_networks[target_net_id][joiner.unit_number] = joiner
                bind_entity_to_network(joiner.unit_number, target_net_id)
            end
        end

    else
        ------------------------------------------------------------------------
        -- JOINER PLACEMENT (Hubs, Pumps, etc.)
        ------------------------------------------------------------------------
        -- Merge opposing tube networks across passthrough channels
        local passthrough_pairs = tube_connections.get_passthrough_pairs(entity)
        for pair_id, ports in pairs(passthrough_pairs) do
            local channel_nets = {}
            for _, port in ipairs(ports) do
                for _, conn in ipairs(conns) do
                    if conn.source_port and conn.source_port.port_id == port.port_id then
                        local neighbor = conn.neighbor
                        if neighbor and neighbor.valid and not tube_connections.is_join_only(neighbor) then
                            local nets = storage.entity_to_network[neighbor.unit_number]
                            if nets then
                                for net_id, _ in pairs(nets) do
                                    table.insert(channel_nets, net_id)
                                end
                            end
                        end
                    end
                end
            end

            if #channel_nets > 1 then
                local primary_net_id = channel_nets[1]
                for i = 2, #channel_nets do
                    local sec_net_id = channel_nets[i]
                    if sec_net_id ~= primary_net_id then
                        local sec_members = storage.pneumatic_networks[sec_net_id]
                        if sec_members then
                            for member_unum, member_ent in pairs(sec_members) do
                                storage.pneumatic_networks[primary_net_id][member_unum] = member_ent
                                bind_entity_to_network(member_unum, primary_net_id)
                                if storage.entity_to_network[member_unum] then
                                    storage.entity_to_network[member_unum][sec_net_id] = nil
                                end
                            end
                        end
                        storage.pneumatic_networks[sec_net_id] = nil
                        release_network_id(sec_net_id)
                    end
                end
            end
        end

        for _, conn in ipairs(conns) do
            local neighbor = conn.neighbor
            if neighbor and neighbor.valid then
                local n_num = neighbor.unit_number
                if tube_connections.is_join_only(neighbor) then
                    local net_id = allocate_fresh_network_id()
                    storage.pneumatic_networks[net_id] = {
                        [u_num] = entity,
                        [n_num] = neighbor
                    }
                    bind_entity_to_network(u_num, net_id)
                    bind_entity_to_network(n_num, net_id)
                else
                    local nets = storage.entity_to_network[n_num]
                    if nets then
                        for net_id, _ in pairs(nets) do
                            storage.pneumatic_networks[net_id][u_num] = entity
                            bind_entity_to_network(u_num, net_id)
                        end
                    end
                end
            end
        end

        local sub_net_id = allocate_fresh_network_id()
        storage.pneumatic_networks[sub_net_id] = { [u_num] = entity }
        bind_entity_to_network(u_num, sub_net_id)
    end
end

local function on_entity_removed(e)
    local entity = e.entity
    if not entity then return end

    local removed_unit_number = entity.unit_number
    if not removed_unit_number then return end

    local direct_conns = tube_connections.get_adjacent_connections(entity)
    local neighbors = {}
    for _, conn in ipairs(direct_conns) do
        if conn.neighbor and conn.neighbor.valid and conn.neighbor.unit_number ~= removed_unit_number then
            table.insert(neighbors, conn.neighbor)
        end
    end

    local raw_branches = {}
    for _, neighbor in ipairs(neighbors) do
        local branch = gather_physical_cluster({neighbor}, removed_unit_number)
        if table_size(branch) > 0 then
            table.insert(raw_branches, branch)
        end
    end

    local merged_islands = {}
    for _, branch in ipairs(raw_branches) do
        local overlapping_indices = {}
        for idx, existing_island in ipairs(merged_islands) do
            local overlaps = false
            for u_num, _ in pairs(branch) do
                if existing_island[u_num] then
                    overlaps = true
                    break
                end
            end
            if overlaps then
                table.insert(overlapping_indices, idx)
            end
        end

        if #overlapping_indices == 0 then
            table.insert(merged_islands, branch)
        else
            local target_idx = overlapping_indices[1]
            for u_num, member in pairs(branch) do
                merged_islands[target_idx][u_num] = member
            end
            for i = #overlapping_indices, 2, -1 do
                local other_idx = overlapping_indices[i]
                for u_num, member in pairs(merged_islands[other_idx]) do
                    merged_islands[target_idx][u_num] = member
                end
                table.remove(merged_islands, other_idx)
            end
        end
    end

    local target_net_ids = {}

    local removed_nets = storage.entity_to_network and storage.entity_to_network[removed_unit_number]
    if removed_nets then
        for net_id, _ in pairs(removed_nets) do
            target_net_ids[net_id] = true
        end
    end

    for _, neighbor in ipairs(neighbors) do
        local neighbor_nets = storage.entity_to_network and storage.entity_to_network[neighbor.unit_number]
        if neighbor_nets then
            for net_id, _ in pairs(neighbor_nets) do
                target_net_ids[net_id] = true
            end
        end
    end

    if storage.pneumatic_networks then
        for net_id, _ in pairs(target_net_ids) do
            local members = storage.pneumatic_networks[net_id]
            if members then
                for u_num, _ in pairs(members) do
                    if storage.entity_to_network and storage.entity_to_network[u_num] then
                        storage.entity_to_network[u_num][net_id] = nil
                        if table_size(storage.entity_to_network[u_num]) == 0 then
                            storage.entity_to_network[u_num] = nil
                        end
                    end
                end
            end
            storage.pneumatic_networks[net_id] = nil
            release_network_id(net_id)
        end
    end

    if storage.entity_to_network then
        storage.entity_to_network[removed_unit_number] = nil
    end

    for _, island in ipairs(merged_islands) do
        rebuild_cluster(island, removed_unit_number)
    end
end

local function on_selected_entity_changed(e)
    local player = game.get_player(e.player_index)
    if not player then return end

    local selected = player.selected
    if selected and selected.valid and tube_connections.is_connectable(selected.name) then
        local net_info = get_network_info(selected)
        if net_info then
            gui_info.update_panel(player, net_info)
            return
        end
    end

    gui_info.destroy_panel(player)
end

--------------------------------------------------------------------------------
-- EVENT REGISTRATIONS
--------------------------------------------------------------------------------

local build_events = {
    defines.events.on_built_entity,
    defines.events.on_robot_built_entity,
    defines.events.script_raised_built,
    defines.events.on_entity_cloned,
}
if defines.events.on_space_platform_built_entity then
    table.insert(build_events, defines.events.on_space_platform_built_entity)
end

local remove_events = {
    defines.events.on_player_mined_entity,
    defines.events.on_robot_mined_entity,
    defines.events.on_entity_died,
    defines.script_raised_destroy,
}
if defines.events.on_space_platform_mined_entity then
    table.insert(remove_events, defines.events.on_space_platform_mined_entity)
end

for _, event in ipairs(build_events) do
    event_manager.register(event, on_entity_built)
end

for _, event in ipairs(remove_events) do
    event_manager.register(event, on_entity_removed)
end

event_manager.register(defines.events.on_selected_entity_changed, on_selected_entity_changed)