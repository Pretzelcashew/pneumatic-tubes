-- scripts/events.lua
local event_manager = {}
local registry = {}

-- Evaluates entity filters in Lua so scripts don't choke each other out at the engine level
local function entity_matches_filters(entity, filters)
    if not filters or #filters == 0 then
        return true
    end

    if not entity or not entity.valid then
        return false
    end

    for _, f in ipairs(filters) do
        if f.filter == "name" and f.name then
            local match = (entity.name == f.name)
            if f.invert then match = not match end
            if match then return true end
        elseif f.filter == "type" and f.type then
            local match = (entity.type == f.type)
            if f.invert then match = not match end
            if match then return true end
        elseif f.filter == "ghost_name" and f.name then
            local match = (entity.name == "entity-ghost" and entity.ghost_name == f.name)
            if f.invert then match = not match end
            if match then return true end
        elseif f.filter == "ghost_type" and f.type then
            local match = (entity.name == "entity-ghost" and entity.ghost_type == f.type)
            if f.invert then match = not match end
            if match then return true end
        end
    end

    return false
end

function event_manager.register(event_id, callback, filters)
    if not event_id then return end

    if not registry[event_id] then
        registry[event_id] = {}
        -- Register to Factorio globally WITHOUT engine-level filters
        script.on_event(event_id, function(e)
            local entity = e.created_entity or e.entity or e.destination or e.source
            for _, entry in ipairs(registry[event_id]) do
                if not entry.filters or entity_matches_filters(entity, entry.filters) then
                    entry.callback(e)
                end
            end
        end)
    end
    table.insert(registry[event_id], {callback = callback, filters = filters})
end

return event_manager