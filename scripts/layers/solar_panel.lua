local common = require("scripts.layers.common")

--- Solar panels, spaced along the middle of their band (spacing = size: side by side).
--- @type LayerType
return {
    name = "solar-panel",
    entity_types = { "solar-panel" },
    placement = "spaced",
    output = "entity",
    priority = 30,
    fields = { common.spacing(function(layer) return 4 * layer.size end) },
}
