-- scripts/tube_connections.lua

local connections = {}

connections.definitions = {
    ["pneumatic-tube"] = {
        orientations = {
            [defines.direction.north] = "vertical",
            [defines.direction.south] = "vertical",
            [defines.direction.east]  = "horizontal",
            [defines.direction.west]  = "horizontal",
        },
        ports = {
            ["horizontal"] = {
                { offset = {x = -2, y = 0}, mode = "merge", port_id = "west" },
                { offset = {x =  2, y = 0}, mode = "merge", port_id = "east" },
            },
            ["vertical"] = {
                { offset = {x = 0, y = -2}, mode = "merge", port_id = "north" },
                { offset = {x = 0, y =  2}, mode = "merge", port_id = "south" },
            },
        },
        can_connect = function(source, target, source_port, target_port)
            return source_port ~= nil and target_port ~= nil
        end,
    },

    ["pneumatic-pump"] = {
        orientations = {
            [defines.direction.north] = "north",
            [defines.direction.south] = "south",
            [defines.direction.east]  = "east",
            [defines.direction.west]  = "west",
        },
        ports = {
            ["north"] = {
                { offset = {x = 0, y = -2}, mode = "join", port_id = "output" },
                { offset = {x = 0, y =  2}, mode = "join", port_id = "input"  },
            },
            ["south"] = {
                { offset = {x = 0, y =  2}, mode = "join", port_id = "output" },
                { offset = {x = 0, y = -2}, mode = "join", port_id = "input"  },
            },
            ["east"] = {
                { offset = {x =  2, y = 0}, mode = "join", port_id = "output" },
                { offset = {x = -2, y = 0}, mode = "join", port_id = "input"  },
            },
            ["west"] = {
                { offset = {x = -2, y = 0}, mode = "join", port_id = "output" },
                { offset = {x =  2, y = 0}, mode = "join", port_id = "input"  },
            },
        },
        can_connect = function(source, target, source_port, target_port)
            return source_port ~= nil and target_port ~= nil
        end,
    },

    ["capsule-hub-horizontal"] = {
        orientations = {
            [defines.direction.north] = "default",
            [defines.direction.south] = "default",
            [defines.direction.east]  = "default",
            [defines.direction.west]  = "default",
        },
        ports = {
            ["default"] = {
                -- Ends (West & East) - Independent Join Only
                { offset = {x = -2, y = 0}, mode = "join", port_id = "west_end" },
                { offset = {x =  2, y = 0}, mode = "join", port_id = "east_end" },

                -- West Side Ports - Independent Join Only
                { offset = {x = -0.5, y = -1}, mode = "join", port_id = "north_west" },
                { offset = {x = -0.5, y =  1}, mode = "join", port_id = "south_west" },

                -- East Side Ports - Independent Join Only
                { offset = {x =  0.5, y = -1}, mode = "join", port_id = "north_east" },
                { offset = {x =  0.5, y =  1}, mode = "join", port_id = "south_east" },
            },
        },
        can_connect = function(source, target, source_port, target_port)
            return source_port ~= nil and target_port ~= nil
        end,
    },

    ["capsule-hub-vertical"] = {
        orientations = {
            [defines.direction.north] = "default",
            [defines.direction.south] = "default",
            [defines.direction.east]  = "default",
            [defines.direction.west]  = "default",
        },
        ports = {
            ["default"] = {
                -- Ends (North & South) - Independent Join Only
                { offset = {x = 0, y = -2}, mode = "join", port_id = "north_end" },
                { offset = {x = 0, y =  2}, mode = "join", port_id = "south_end" },

                -- North Side Ports - Independent Join Only
                { offset = {x = -1, y = -0.5}, mode = "join", port_id = "west_north" },
                { offset = {x =  1, y = -0.5}, mode = "join", port_id = "east_north" },

                -- South Side Ports - Independent Join Only
                { offset = {x = -1, y =  0.5}, mode = "join", port_id = "west_south" },
                { offset = {x =  1, y =  0.5}, mode = "join", port_id = "east_south" },
            },
        },
        can_connect = function(source, target, source_port, target_port)
            return source_port ~= nil and target_port ~= nil
        end,
    },
}

function connections.is_connectable(entity_name)
    return connections.definitions[entity_name] ~= nil
end

function connections.get_orientation(entity)
    if not (entity and entity.valid) then return nil end
    local def = connections.definitions[entity.name]
    if not def then return nil end
    return def.orientations[entity.direction]
end

function connections.get_ports(entity)
    if not (entity and entity.valid) then return {} end
    local def = connections.definitions[entity.name]
    if not def then return {} end
    local orient = connections.get_orientation(entity)
    return def.ports[orient] or {}
end

function connections.get_offsets(entity)
    local ports = connections.get_ports(entity)
    local offsets = {}
    for _, port in ipairs(ports) do
        table.insert(offsets, port.offset)
    end
    return offsets
end

function connections.is_join_only(entity)
    local ports = connections.get_ports(entity)
    if #ports == 0 then return false end
    for _, port in ipairs(ports) do
        if port.mode ~= "join" then
            return false
        end
    end
    return true
end

--- World-space proximity scanning to reliably detect adjacent ports
function connections.get_adjacent_connections(entity, ignore_unit_number)
    local result = {}
    if not (entity and entity.valid) then return result end

    local surface = entity.surface
    local ports = connections.get_ports(entity)

    for _, source_port in ipairs(ports) do
        local source_world_pos = {
            x = entity.position.x + source_port.offset.x,
            y = entity.position.y + source_port.offset.y
        }
        local found = surface.find_entities_filtered{position = source_world_pos, radius = 1.5}
        for _, e in ipairs(found) do
            if e.valid and e.unit_number ~= entity.unit_number and e.unit_number ~= ignore_unit_number then
                if connections.is_connectable(e.name) then
                    local neighbor_ports = connections.get_ports(e)
                    for _, target_port in ipairs(neighbor_ports) do
                        local target_world_pos = {
                            x = e.position.x + target_port.offset.x,
                            y = e.position.y + target_port.offset.y
                        }
                        local dx = source_world_pos.x - target_world_pos.x
                        local dy = source_world_pos.y - target_world_pos.y
                        if (dx * dx + dy * dy) < 1.0 then
                            table.insert(result, {
                                neighbor = e,
                                source_port = source_port,
                                target_port = target_port
                            })
                            break
                        end
                    end
                end
            end
        end
    end

    return result
end

return connections