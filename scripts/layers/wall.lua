local common = require("scripts.layers.common")

--- Walls fill their band.
--- @type LayerType
return {
    name = "wall",
    entity_types = { "wall" },
    placement = "band",
    output = "entity",
    priority = 100,
    fields = { common.checkerboard, common.radius },
    thickness = common.band_thickness,
}
