-- scripts/RotateHandler.lua
local EventManager = require("scripts.events")

local rotate_pairs = {
    ["capsule-hub-horizontal"] = "capsule-hub-vertical",
    ["capsule-hub-vertical"] = "capsule-hub-horizontal",
}

local get_counterpart = function(item_name)
    return rotate_pairs[item_name]
end

local last_held_cache = {}

-- 1. Handles manual rotation key (R) press
EventManager.register("capsule-hub-rotate-catcher", function(event)
    local player = game.players[event.player_index]
    
    if not player.cursor_stack or not player.cursor_stack.valid_for_read then return end
    
    local current_item = player.cursor_stack.name
    local target_item = get_counterpart(current_item)
    
    if target_item then
        local count = player.cursor_stack.count
        local quality = player.cursor_stack.quality
        local health = player.cursor_stack.health
        
        last_held_cache[event.player_index] = {name = target_item, quality = quality.name}
        
        player.cursor_stack.clear()
        player.cursor_stack.set_stack({
            name = target_item,
            count = count,
            quality = quality,
            health = health
        })
    end
end)

-- 2. Track what the player is holding & handle auto-refill/conversion when empty
EventManager.register(defines.events.on_player_cursor_stack_changed, function(event)
    local player = game.players[event.player_index]
    
    if player.cursor_stack and player.cursor_stack.valid_for_read then
        local item_name = player.cursor_stack.name
        if rotate_pairs[item_name] then
            last_held_cache[event.player_index] = {
                name = item_name,
                quality = player.cursor_stack.quality.name
            }
        end
        return
    end
    
    local cached = last_held_cache[event.player_index]
    if not cached then return end
    
    local needed_item_in_inventory = get_counterpart(cached.name)
    local target_quality = cached.quality
    
    if not needed_item_in_inventory then return end
    
    local main_inventory = player.get_main_inventory()
    if not main_inventory then return end

    for i = 1, #main_inventory do
        local stack = main_inventory[i]
        if stack and stack.valid_for_read then
            if stack.name == needed_item_in_inventory and stack.quality.name == target_quality then
                local count = stack.count
                local quality = stack.quality
                local health = stack.health
                
                stack.clear()
                
                player.cursor_stack.set_stack({
                    name = cached.name,
                    count = count,
                    quality = quality,
                    health = health
                })
                
                break
            end
        end
    end
end)