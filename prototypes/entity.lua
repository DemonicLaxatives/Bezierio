local nothing = {
    direction_count = 8,
    frame_count = 1,
    filename = "__Bezierio__/graphics/blank.png",
    width = 1,
    height = 1,
    priority = "low"
  }

local connection_points = {red = {0,0}, green = {0,0}}

flags = {"hide-alt-info", "not-on-map", "not-upgradable", "not-deconstructable", "not-blueprintable", "placeable-off-grid", "hidden", "placeable-neutral", "player-creation","not-in-kill-statistics"}

connector = {
  type = "container",
  name = "curve-projector-p1",
  icon = "__Bezierio__/graphics/icons/curve-projector.png",
  inventory_size = 0,
  picture = nothing,
  icon_size = 64,
  flags = flags,
  max_health = 250,
  collision_mask = {},
  circuit_wire_max_distance = 5,
  selection_priority = 52,
  minable = nil,
}

curve_projector_p1 = table.deepcopy(connector)
curve_projector_p1.collision_box = {{-0.4, -0.4},{0.4, 0.4}}
curve_projector_p1.selection_box = {{-0.4, -0.4},{0.4, 0.4}}
curve_projector_p2 = table.deepcopy(curve_projector_p1)
curve_projector_p1.name = "curve-projector-p1"
curve_projector_p2.name = "curve-projector-p2"

controller = table.deepcopy(connector)
controller.name = "curve-projector-controller"
controller.collision_box = {{-0.8, -0.4},{0.8, 0.4}}
controller.selection_box = {{-0.8, -0.4},{0.8, 0.4}}
controller.inventory_size = 2

data:extend{
    curve_projector_p1,
    curve_projector_p2,
    controller,
    {
      type = "container",
      name = "curve-projector",
      icon = "__Bezierio__/graphics/icons/curve-projector.png",
      icon_size = 64,
      flags = {"placeable-neutral", "placeable-player", "player-creation", "no-automated-item-removal", "no-automated-item-insertion"},
      minable = {mining_time = 0.2, result = "curve-projector"},
      max_health = 250,
      collision_box = {{-1.8, -0.4}, {1.8, 0.4}},
      selection_box = {{-2, -0.5}, {2, 0.5}},
      vehicle_impact_sound = { filename = "__base__/sound/car-metal-impact.ogg", volume = 0.65 },
      inventory_size = 0,
      picture = {filename = "__Bezierio__/graphics/entity/curve-projector.png",
      priority = "extra-high",
      width = 128,
      height = 32},

      selection_priority = 0,
    },

}