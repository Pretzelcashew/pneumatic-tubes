-- scripts/print_all_events.lua
local event_manager = require("scripts.events")

if defines and defines.events then
    for event_name, event_id in pairs(defines.events) do
        -- Exclude high-frequency events like on_tick and chunk charted to prevent chat spam
        if event_name ~= "on_tick" and event_name ~= "on_chunk_charted" then
            event_manager.register(event_id, function(e)
                game.print("Event triggered: " .. event_name)
            end)
        end
    end
end