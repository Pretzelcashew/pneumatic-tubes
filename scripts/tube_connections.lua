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
                -- End Join Ports (West & East)
                { offset = {x = -2.0, y = 0.0}, mode = "join", port_id = "west_end" },
                { offset = {x =  2.0, y = 0.0}, mode = "join", port_id = "east_end" },

                -- North Side Join Ports
                { offset = {x = -0.5, y = -1.0}, mode = "join", port_id = "north_west" },
                { offset = {x =  0.5, y = -1.0}, mode = "join", port_id = "north_east" },

                -- South Side Join Ports
                { offset = {x = -0.5, y =  1.0}, mode = "join", port_id = "south_west" },
                { offset = {x =  0.5, y =  1.0}, mode = "join", port_id = "south_east" },
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
                -- End Join Ports (North & South)
                { offset = {x = 0.0, y = -2.0}, mode = "join", port_id = "north_end" },
                { offset = {x = 0.0, y =  2.0}, mode = "join", port_id = "south_end" },

                -- West Side Join Ports
                { offset = {x = -1.0, y = -0.5}, mode = "join", port_id = "west_north" },
                { offset = {x = -1.0, y =  0.5}, mode = "join", port_id = "west_south" },

                -- East Side Join Ports
                { offset = {x =  1.0, y = -0.5}, mode = "join", port_id = "east_north" },
                { offset = {x =  1.0, y =  0.5}, mode = "join", port_id = "east_south" },
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

--- 0.6 tolerance accommodates 0.5 tile center shifts between 1x2 and 2x1 entities
function connections.get_port_at_offset(entity, offset_x, offset_y)
    local ports = connections.get_ports(entity)
    for _, port in ipairs(ports) do
        if math.abs(port.offset.x - offset_x) < 0.6 and math.abs(port.offset.y - offset_y) < 0.6 then
            return port
        end
    end
    return nil
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

function connections.can_connect_entities(source, target)
    if not (source and source.valid and target and target.valid) then return false end

    local source_def = connections.definitions[source.name]
    local target_def = connections.definitions[target.name]
    if not (source_def and target_def) then return false end

    local dx = target.position.x - source.position.x
    local dy = target.position.y - source.position.y

    local source_port = connections.get_port_at_offset(source, dx, dy)
    local target_port = connections.get_port_at_offset(target, -dx, -dy)

    return source_def.can_connect(source, target, source_port, target_port)
end

--- Scans entity ports and returns all connected valid neighbors
function connections.get_adjacent_connections(entity, ignore_unit_number)
    local result = {}
    if not (entity and entity.valid) then return result end

    local surface = entity.surface
    local ports = connections.get_ports(entity)

    for _, port in ipairs(ports) do
        local world_pos = {
            x = entity.position.x + port.offset.x,
            y = entity.position.y + port.offset.y
        }
        local found = surface.find_entities_filtered{position = world_pos, radius = 1.0}
        for _, e in ipairs(found) do
            if e.valid and e.unit_number ~= entity.unit_number and e.unit_number ~= ignore_unit_number then
                if connections.is_connectable(e.name) then
                    local dx = e.position.x - entity.position.x
                    local dy = e.position.y - entity.position.y
                    local target_port = connections.get_port_at_offset(e, -dx, -dy)
                    if target_port then
                        table.insert(result, {
                            neighbor = e,
                            source_port = port,
                            target_port = target_port
                        })
                    end
                end
            end
        end
    end

    return result
end

return connections