-- scripts/capsule_transport.lua
local capsule_transport = {}

-- Metatable safety net to prevent nil-function crashes from other files
setmetatable(capsule_transport, {
    __index = function(tbl, key)
        return function(...) return nil end
    end
})

return capsule_transport