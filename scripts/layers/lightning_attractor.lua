local common = require("scripts.layers.common")

--- Lightning attractors (Space Age: lightning rods and collectors), spaced along
--- the middle of their band. The spacing slider goes up to twice the attraction
--- range (`get_attraction_range_elongation`, taken as the radius they protect),
--- where neighbouring circles just touch on the line, and defaults to the range,
--- so they also cover a strip about 0.87 of it wide on each side. Ones that
--- turn lightning into electricity need to be on the network, so smart poles
--- power them like any consumer (`needs_power`, from the electric energy source).
--- @type LayerType
return {
    name = "lightning-attractor",
    entity_types = { "lightning-attractor" },
    placement = "spaced",
    output = "entity",
    priority = 30,
    fields = {
        common.spacing(
            function(layer) return math.floor(2 * (layer.attraction_range or 0)) end,
            function(layer) return math.max(layer.size, math.floor(layer.attraction_range or 0)) end),
    },
    --- @param layer Layer
    --- @param prototype LuaEntityPrototype
    init = function(layer, prototype)
        layer.attraction_range = prototype.get_attraction_range_elongation(layer.quality) or 0
    end,
}
