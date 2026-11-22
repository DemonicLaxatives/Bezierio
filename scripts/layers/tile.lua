local common = require("scripts.layers.common")

--- Floor tiles fill their band. With `under`, the band doesn't push the layers
--- further out away: they sit on top of the tiles (see planner.bands).
--- @type LayerType
return {
    name = "tile",
    tile = true,
    placement = "band",
    output = "tile",
    priority = 100,
    fields = {
        common.checkerboard,
        common.radius,
        { name = "under", widget = "checkbox", default = false },
    },
    thickness = common.band_thickness,
}
