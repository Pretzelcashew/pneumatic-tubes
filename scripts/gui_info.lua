local GUI = {}

local FRAME_NAME = "pneumatic_info_frame"

--- Destroys the info panel if it exists
function GUI.destroy_panel(player)
    if player.gui.left[FRAME_NAME] then
        player.gui.left[FRAME_NAME].destroy()
    end
end

--- Displays or updates the network info panel
-- @param player LuaPlayer
-- @param network_data table List of {key = string, value = string|number}
function GUI.update_panel(player, network_data)
    if not network_data or #network_data == 0 then
        GUI.destroy_panel(player)
        return
    end

    local frame = player.gui.left[FRAME_NAME]

    -- Create frame if it doesn't exist
    if not frame then
        frame = player.gui.left.add{
            type = "frame",
            name = FRAME_NAME,
            direction = "vertical",
            caption = {"", "Pneumatic Network"}
        }
        frame.style.padding = 8
        frame.style.use_header_filler = true
    end

    -- Clear previous dynamic content container
    if frame.content_table then
        frame.content_table.destroy()
    end

    -- Create 2-column grid for Key/Value pairs
    local table_grid = frame.add{
        type = "table",
        name = "content_table",
        column_count = 2
    }
    table_grid.style.horizontal_spacing = 12
    table_grid.style.vertical_spacing = 4

    -- Dynamically generate labels for any key-value pair provided
    for _, item in ipairs(network_data) do
        local label_key = table_grid.add{
            type = "label",
            caption = tostring(item.key) .. ":"
        }
        label_key.style.font = "default-bold"
        label_key.style.font_color = {r = 0.8, g = 0.8, b = 0.8}

        local label_val = table_grid.add{
            type = "label",
            caption = tostring(item.value)
        }
        label_val.style.font_color = {r = 1, g = 1, b = 1}
    end
end

return GUI