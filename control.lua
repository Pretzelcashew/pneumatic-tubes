-- control.lua
script.on_init(function()
    storage.tracked_cardinal_entities = {}
    storage.pneumatic_networks = {}
    storage.entity_to_network = {}
    storage.hubs = {}
end)

require("scripts.cardinal_entity_core")
require("scripts.cardinal_entity_visualizer")
require("scripts.pneumatic_networks-backup")
require("scripts.rotate_handler")
require("scripts.hub_gui")

-- Capsulization system (ACTIVE)
require("scripts.capsule_evaluator")
require("scripts.capsule_routing")
require("scripts.capsulizer")

-- Transport physics (DISABLED / CLEAN SLATE)
require("scripts.capsule_transport")