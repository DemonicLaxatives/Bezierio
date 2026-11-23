local common = require("scripts.layers.common")

--- Transport belts: one or more lines along the band, each a continuous chain of
--- cells following the curve (see build/paths.lua), flowing forward or backward.
--- Long straight runs can go underground.
--- @type LayerType
return {
    name = "belt",
    entity_types = { "transport-belt" },
    placement = "path",
    output = "entity",
    priority = 90,
    fields = {
        common.lines,
        { name = "line_gap", widget = "slider", min = 0, max = 3, default = 0 },
        common.flow,
        { name = "undergrounds", widget = "checkbox", default = false },
    },
    thickness = common.path_thickness,
    --- @param layer Layer
    --- @param prototype LuaEntityPrototype
    init = function(layer, prototype)
        local underground = prototype.related_underground_belt
        layer.underground_name = underground and underground.name or nil
        layer.underground_item = underground and common.item_for(underground) or nil
        layer.underground_distance = underground and underground.max_underground_distance or nil
    end,
}
