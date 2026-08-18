

data:extend({
  -- ITEM CAPSULE
  {
    type = "item",
    name = "item-capsule",
    icon = "__base__/graphics/icons/iron-plate.png",
    icon_size = 64,
    subgroup = "intermediate-product",
    order = "a[capsule]",
    stack_size = 1
  },
  {
    type = "recipe",
    name = "item-capsule",
    enabled = true,
    ingredients = {
      {type = "item", name = "steel-plate", amount = 2}
    },
    results = {
      {type = "item", name = "item-capsule", amount = 1}
    }
  },

  -- CAPSULE HUB HORIZONTAL (2x1)
  {
    type = "item",
    name = "capsule-hub-horizontal",
    icon = "__base__/graphics/icons/steel-chest.png",
    icon_size = 64,
    subgroup = "storage",
    order = "b[hub-horizontal]",
    stack_size = 5,
    place_result = "capsule-hub-horizontal"
  },
  {
    type = "container",
    name = "capsule-hub-horizontal",
    icon = "__base__/graphics/icons/steel-chest.png",
    icon_size = 64,
    flags = {"placeable-neutral", "placeable-player", "player-creation"},
    rotatable = true,
    minable = {mining_time = 0.5, result = "capsule-hub-horizontal"},
    max_health = 250,
    collision_box = {{-0.9, -0.4}, {0.9, 0.4}},
    selection_box = {{-1.0, -0.5}, {1.0, 0.5}},
    inventory_size = 6,
    inventory_type = "with_filters",
    picture = {
      layers = {
        {
          filename = "__base__/graphics/entity/steel-chest/steel-chest.png",
          width = 64,
          height = 64,
          scale = 0.5,
          shift = {-0.5, 0}
        },
        {
          filename = "__base__/graphics/entity/steel-chest/steel-chest.png",
          width = 64,
          height = 64,
          scale = 0.5,
          shift = {0.5, 0}
        }
      }
    },
    circuit_wire_connection_point = circuit_connector_definitions["chest"].points,
    circuit_connector_sprites = circuit_connector_definitions["chest"].sprites,
    circuit_wire_max_distance = default_circuit_wire_max_distance
  },
  {
    type = "recipe",
    name = "capsule-hub-horizontal",
    enabled = true,
    ingredients = {
      {type = "item", name = "steel-chest", amount = 1},
      {type = "item", name = "electronic-circuit", amount = 2}
    },
    results = {
      {type = "item", name = "capsule-hub-horizontal", amount = 1}
    }
  },

  -- CAPSULE HUB VERTICAL (1x2)
  {
    type = "item",
    name = "capsule-hub-vertical",
    icon = "__base__/graphics/icons/steel-chest.png",
    icon_size = 64,
    subgroup = "storage",
    order = "b[hub-vertical]",
    stack_size = 5,
    place_result = "capsule-hub-vertical"
  },
  {
    type = "container",
    name = "capsule-hub-vertical",
    icon = "__base__/graphics/icons/steel-chest.png",
    icon_size = 64,
    flags = {"placeable-neutral", "placeable-player", "player-creation"},
    rotatable = true,
    minable = {mining_time = 0.5, result = "capsule-hub-vertical"},
    max_health = 250,
    collision_box = {{-0.4, -0.9}, {0.4, 0.9}},
    selection_box = {{-0.5, -1.0}, {0.5, 1.0}},
    inventory_size = 6,
    inventory_type = "with_filters",
    picture = {
      layers = {
        {
          filename = "__base__/graphics/entity/steel-chest/steel-chest.png",
          width = 64,
          height = 64,
          scale = 0.5,
          shift = {0, -0.5}
        },
        {
          filename = "__base__/graphics/entity/steel-chest/steel-chest.png",
          width = 64,
          height = 64,
          scale = 0.5,
          shift = {0, 0.5}
        }
      }
    },
    circuit_wire_connection_point = circuit_connector_definitions["chest"].points,
    circuit_connector_sprites = circuit_connector_definitions["chest"].sprites,
    circuit_wire_max_distance = default_circuit_wire_max_distance
  },
  {
    type = "recipe",
    name = "capsule-hub-vertical",
    enabled = true,
    ingredients = {
      {type = "item", name = "steel-chest", amount = 1},
      {type = "item", name = "electronic-circuit", amount = 2}
    },
    results = {
      {type = "item", name = "capsule-hub-vertical", amount = 1}
    }
  },

  -- INVISIBLE LIMINAL HOLDER
  {
    type = "container",
    name = "invisible-capsule-holder",
    icon = "__base__/graphics/icons/wooden-chest.png",
    icon_size = 64,
    flags = {
      "not-on-map",
      "placeable-off-grid",
      "not-selectable-in-game",
      "no-automated-item-removal",
      "no-automated-item-insertion"
    },
    hidden = true,
    hidden_in_factoriopedia = true,
    max_health = 1,
    destructible = false,
    operable = false,
    collision_mask = {layers = {}},
    inventory_size = 10,
    picture = util.empty_sprite()
  },

  -- PNEUMATIC TUBE
  {
    type = "item",
    name = "pneumatic-tube",
    icon = "__base__/graphics/icons/pipe.png",
    icon_size = 64,
    subgroup = "energy-pipe-distribution",
    order = "a[pneumatic-tube]",
    stack_size = 50,
    place_result = "pneumatic-tube"
  },
  {
    type = "simple-entity-with-owner",
    name = "pneumatic-tube",
    icon = "__base__/graphics/icons/pipe.png",
    icon_size = 64,
    flags = {"placeable-neutral", "placeable-player", "player-creation"},
    rotatable = true,
    operable = true,
    minable = {mining_time = 0.2, result = "pneumatic-tube"},
    max_health = 100,
    collision_box = {{-0.4, -0.9}, {0.4, 0.9}},
    selection_box = {{-0.5, -1.0}, {0.5, 1.0}},
    picture = {
      north = {
        layers = {
          {
            filename = "__base__/graphics/entity/pipe/pipe-straight-vertical.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
            shift = {0, -0.5}
          },
          {
            filename = "__base__/graphics/entity/pipe/pipe-straight-vertical.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
            shift = {0, 0.5}
          }
        }
      },
      east = {
        layers = {
          {
            filename = "__base__/graphics/entity/pipe/pipe-straight-horizontal.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
            shift = {-0.5, 0}
          },
          {
            filename = "__base__/graphics/entity/pipe/pipe-straight-horizontal.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
            shift = {0.5, 0}
          }
        }
      },
      south = {
        layers = {
          {
            filename = "__base__/graphics/entity/pipe/pipe-straight-vertical.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
            shift = {0, -0.5}
          },
          {
            filename = "__base__/graphics/entity/pipe/pipe-straight-vertical.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
            shift = {0, 0.5}
          }
        }
      },
      west = {
        layers = {
          {
            filename = "__base__/graphics/entity/pipe/pipe-straight-horizontal.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
            shift = {-0.5, 0}
          },
          {
            filename = "__base__/graphics/entity/pipe/pipe-straight-horizontal.png",
            priority = "extra-high",
            width = 128,
            height = 128,
            scale = 0.5,
            shift = {0.5, 0}
          }
        }
      }
    }
  },
  {
    type = "recipe",
    name = "pneumatic-tube",
    enabled = true,
    ingredients = {
      {type = "item", name = "iron-plate", amount = 1}
    },
    results = {
      {type = "item", name = "pneumatic-tube", amount = 1}
    }
  },

  -- PNEUMATIC PUMP
  {
    type = "item",
    name = "pneumatic-pump",
    icon = "__base__/graphics/icons/pump.png",
    icon_size = 64,
    subgroup = "energy-pipe-distribution",
    order = "b[pneumatic-pump]",
    stack_size = 20,
    place_result = "pneumatic-pump"
  },
  {
    type = "simple-entity-with-owner",
    name = "pneumatic-pump",
    icon = "__base__/graphics/icons/pump.png",
    icon_size = 64,
    flags = {"placeable-neutral", "placeable-player", "player-creation"},
    rotatable = true,
    fast_replaceable_group = "pneumatic-pump",
    minable = {mining_time = 0.2, result = "pneumatic-pump"},
    max_health = 180,
    collision_box = {{-0.4, -0.9}, {0.4, 0.9}},
    selection_box = {{-0.5, -1.0}, {0.5, 1.0}},
    picture = {
      north = {
        filename = "__base__/graphics/entity/pump/pump-north.png",
        priority = "high",
        width = 64,
        height = 128,
        scale = 0.5
      },
      east = {
        filename = "__base__/graphics/entity/pump/pump-east.png",
        priority = "high",
        width = 128,
        height = 64,
        scale = 0.5
      },
      south = {
        filename = "__base__/graphics/entity/pump/pump-south.png",
        priority = "high",
        width = 64,
        height = 128,
        scale = 0.5
      },
      west = {
        filename = "__base__/graphics/entity/pump/pump-west.png",
        priority = "high",
        width = 128,
        height = 64,
        scale = 0.5
      }
    }
  },
  {
    type = "recipe",
    name = "pneumatic-pump",
    enabled = true,
    ingredients = {
      {type = "item", name = "steel-plate", amount = 2},
      {type = "item", name = "engine-unit", amount = 1}
    },
    results = {
      {type = "item", name = "pneumatic-pump", amount = 1}
    }
  },


-- CUSTOM INPUT FOR ROTATION CATCHER
  {
    type = "custom-input",
    name = "capsule-hub-rotate-catcher",
    key_sequence = "",
    linked_game_control = "rotate",
    action = "lua"
  }










})