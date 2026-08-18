-- scripts/pneumatic_networks.lua
local event_manager = require("scripts.events")
local gui_info = require("scripts.gui_info")
local tube_connections = require("scripts.tube_connections")
local capsule_evaluator = require("scripts.capsule_evaluator")

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

--------------------------------------------------------------------------------
-- CAPSULE NETWORK MIGRATION & SPILLING
--------------------------------------------------------------------------------

local function redistribute_harvested_capsules(harvested_capsules, fallback_pos)
    if not harvested_capsules or #harvested_capsules == 0 then return end

    for _, capsule in ipairs(harvested_capsules) do
        local pos = capsule.last_position or (fallback_pos and { x = fallback_pos.x, y = fallback_pos.y })
        local surface = (fallback_pos and fallback_pos.surface) or game.surfaces["nauvis"]
        local spill_pos = pos or { x = 0, y = 0 }
        local holder = capsule.holder

        if holder and holder.valid then
            local holder_inv = holder.get_inventory(defines.inventory.chest) or holder.get_inventory(1)
            
            if holder_inv and holder_inv.valid and surface and surface.valid then
                for i = 1, #holder_inv do
                    local stack = holder_inv[i]
                    if stack and stack.valid_for_read then
                        surface.spill_item_stack{
                            position = spill_pos,
                            stack = stack
                        }
                    end
                end
            end

            holder.destroy()
        end
    end
end

--------------------------------------------------------------------------------
-- SANITIZATION & CLUSTERING
--------------------------------------------------------------------------------

local function sanitize_network_storage()
    if not storage.pneumatic_networks then return end
    storage.entity_to_network = storage.entity_to_network or {}

    for net_id, members in pairs(storage.pneumatic_networks) do
        for u_num, entity in pairs(members) do
            if u_num ~= "capsules" and u_num ~= "length" then
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
        end

        local member_count = 0
        for k, _ in pairs(members) do
            if k ~= "capsules" and k ~= "length" then member_count = member_count + 1 end
        end

        if member_count == 0 then
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

--------------------------------------------------------------------------------
-- REBUILD NETWORK CLUSTER
--------------------------------------------------------------------------------

local function rebuild_cluster(cluster, excluded_unit_number)
    storage.pneumatic_networks = storage.pneumatic_networks or {}
    storage.entity_to_network = storage.entity_to_network or {}

    -- 1. Preserve active in-flight capsules across reset cluster entities
    local old_network_capsules = {}
    for u_num, _ in pairs(cluster) do
        local nets = storage.entity_to_network[u_num]
        if nets then
            for net_id, _ in pairs(nets) do
                local net_struct = storage.pneumatic_networks[net_id]
                if net_struct and net_struct.capsules then
                    old_network_capsules[net_id] = old_network_capsules[net_id] or {}
                    for cap_id, cap in pairs(net_struct.capsules) do
                        old_network_capsules[net_id][cap_id] = cap
                    end
                end
            end
        end
    end

    -- 2. Clear network bindings for entities in the cluster
    for u_num, entity in pairs(cluster) do
        local nets = storage.entity_to_network[u_num]
        if nets then
            for net_id, _ in pairs(nets) do
                local net_struct = storage.pneumatic_networks[net_id]
                if net_struct then
                    net_struct[u_num] = nil

                    local member_count = 0
                    for k, _ in pairs(net_struct) do
                        if k ~= "capsules" and k ~= "length" then
                            member_count = member_count + 1
                        end
                    end

                    if member_count == 0 then
                        storage.pneumatic_networks[net_id] = nil
                        release_network_id(net_id)
                    end
                end
            end
            storage.entity_to_network[u_num] = nil
        end
    end

    -- 3. Phase 1: Build Merge Networks (Tube Graphs)
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
                            -- Join entities (Hubs/Pumps) attach as boundary members without propagating traversal
                            boundary_joiners[neighbor.unit_number] = neighbor
                        else
                            -- Merge <-> Merge connection check
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

            -- Re-assign any migrating capsules belonging to this tube set
            for t_num, _ in pairs(tube_group) do
                for old_net_id, caps in pairs(old_network_capsules) do
                    for cap_id, cap in pairs(caps) do
                        net_members.capsules = net_members.capsules or {}
                        net_members.capsules[cap_id] = cap
                        cap.net_id = net_id
                        caps[cap_id] = nil
                    end
                end
            end

            storage.pneumatic_networks[net_id] = net_members
        end
    end

    -- 4. Phase 2: Join-to-Join Networks (Hub-to-Pump or Pump-to-Pump direct connections)
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
                            if netsB[id] then
                                already_connected = true
                                break
                            end
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

    -- 5. Phase 3: Standalone / Fallback Networks for isolated entities
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

local DIRECTION_NAMES = {
    [defines.direction.north] = "North",
    [defines.direction.east]  = "East",
    [defines.direction.south] = "South",
    [defines.direction.west]  = "West",
}

local function get_network_info(entity)
    if not (entity and entity.valid) then return nil end
    sanitize_network_storage()

    local net_ids = storage.entity_to_network and storage.entity_to_network[entity.unit_number]
    if not net_ids or table_size(net_ids) == 0 then return nil end

    local info = {}
    for net_id, _ in pairs(net_ids) do
        local network_entities = storage.pneumatic_networks and storage.pneumatic_networks[net_id]
        if network_entities then
            local member_count = 0
            for k, _ in pairs(network_entities) do
                if k ~= "capsules" and k ~= "length" then member_count = member_count + 1 end
            end

            table.insert(info, { key = "Network ID",  value = "#" .. tostring(net_id) })
            table.insert(info, { key = "Total Members", value = member_count })

            local capsule_count = network_entities.capsules and table_size(network_entities.capsules) or 0
            table.insert(info, { key = "Active Capsules", value = capsule_count })

            local pump_dirs = {}
            for u_num, member in pairs(network_entities) do
                if u_num ~= "capsules" and u_num ~= "length" and member and member.valid and member.name == "pneumatic-pump" then
                    local dir_label = DIRECTION_NAMES[member.direction] or "Unknown"
                    table.insert(pump_dirs, dir_label)
                end
            end

            if #pump_dirs > 0 then
                table.insert(info, { key = "Pumps", value = #pump_dirs })
                table.insert(info, { key = "Pump Directions", value = table.concat(pump_dirs, ", ") })
            else
                table.insert(info, { key = "Pumps", value = "0" })
            end

            if entity.name == "capsule-hub-horizontal" or entity.name == "capsule-hub-vertical" then
                local eval = capsule_evaluator.evaluate_hub_readiness(entity, net_id)
                if eval then
                    local payload_str = eval.payload_ready and ("Ready (" .. eval.payload_name .. " x" .. eval.capacity .. ")") or "Not Ready"
                    local flow_str = eval.flow_ready and ("Outward (" .. eval.flow_direction .. ")") or (eval.flow_direction and "Inward Flow" or "No Flow")
                    local status_str = eval.ready and "READY TO DISPATCH" or "WAITING"

                    table.insert(info, { key = "Payload Status", value = payload_str })
                    table.insert(info, { key = "Flow Direction", value = flow_str })
                    table.insert(info, { key = "Dispatch Status", value = status_str })
                end
            end
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

    -- Gather local connected cluster and rebuild network topology
    local cluster = gather_physical_cluster({entity})
    rebuild_cluster(cluster)
end

local function on_entity_removed(e)
    local entity = e.entity
    if not entity then return end

    local removed_unit_number = entity.unit_number
    if not removed_unit_number then return end

    local removed_position = {
        x = entity.position.x,
        y = entity.position.y,
        surface = entity.surface
    }

    local direct_conns = tube_connections.get_adjacent_connections(entity)
    local neighbors = {}
    for _, conn in ipairs(direct_conns) do
        if conn.neighbor and conn.neighbor.valid and conn.neighbor.unit_number ~= removed_unit_number then
            table.insert(neighbors, conn.neighbor)
        end
    end

    -- Target networks bound to the destroyed tile
    local target_net_ids = {}
    local removed_nets = storage.entity_to_network and storage.entity_to_network[removed_unit_number]
    if removed_nets then
        for net_id, _ in pairs(removed_nets) do
            target_net_ids[net_id] = true
        end
    end

    -- Harvest in-flight capsules strictly from destroyed networks
    local harvested_capsules = {}
    if storage.pneumatic_networks then
        for net_id, _ in pairs(target_net_ids) do
            local net_struct = storage.pneumatic_networks[net_id]
            if net_struct and net_struct.capsules then
                for _, capsule in pairs(net_struct.capsules) do
                    table.insert(harvested_capsules, capsule)
                end
            end
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

    -- Clear entity bindings and destroyed networks
    if storage.pneumatic_networks then
        for net_id, _ in pairs(target_net_ids) do
            local net_struct = storage.pneumatic_networks[net_id]
            if net_struct then
                for u_num, _ in pairs(net_struct) do
                    if u_num ~= "capsules" and u_num ~= "length" and storage.entity_to_network and storage.entity_to_network[u_num] then
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

    -- Rebuild surviving tube islands
    for _, island in ipairs(merged_islands) do
        rebuild_cluster(island, removed_unit_number)
    end

    -- Spill harvested in-flight capsules
    redistribute_harvested_capsules(harvested_capsules, removed_position)
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
-- LIVE GUI TICK UPDATE
--------------------------------------------------------------------------------

local function update_selected_gui()
    for _, player in pairs(game.connected_players) do
        local selected = player.selected
        if selected and selected.valid and tube_connections.is_connectable(selected.name) then
            local net_info = get_network_info(selected)
            if net_info then
                gui_info.update_panel(player, net_info)
            else
                gui_info.destroy_panel(player)
            end
        end
    end
end

event_manager.register(defines.events.on_tick, update_selected_gui)

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

event_manager.register(defines.events.on_player_rotated_entity, function(e)
    on_selected_entity_changed({ player_index = e.player_index })
end)