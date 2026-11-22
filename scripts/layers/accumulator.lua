local common = require("scripts.layers.common")

--- Accumulators, spaced along the middle of their band.
--- @type LayerType
return {
    name = "accumulator",
    entity_types = { "accumulator" },
    placement = "spaced",
    output = "entity",
    priority = 30,
    fields = { common.spacing(function(layer) return 4 * layer.size end) },
}
