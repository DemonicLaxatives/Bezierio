local common = require("scripts.layers.common")

--- Floor tiles fill their band. Tiles don't compete with entities for cells.
--- @type LayerType
return {
    name = "tile",
    tile = true,
    placement = "band",
    output = "tile",
    priority = 100,
    fields = { common.checkerboard, common.radius },
    thickness = common.band_thickness,
}
