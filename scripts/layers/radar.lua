local common = require("scripts.layers.common")

--- Radars, spaced along the middle of their band. The spacing slider goes up to
--- the width of the area a radar keeps revealed (chunks around its own), and
--- defaults to a chunk less, so neighbouring areas overlap.
--- @type LayerType
return {
    name = "radar",
    entity_types = { "radar" },
    placement = "spaced",
    output = "entity",
    priority = 30,
    fields = {
        common.spacing(
            function(layer) return (2 * (layer.reveal_chunks or 0) + 1) * 32 end,
            function(layer) return math.max(layer.size, 2 * (layer.reveal_chunks or 0) * 32) end),
    },
    --- @param layer Layer
    --- @param prototype LuaEntityPrototype
    init = function(layer, prototype)
        layer.reveal_chunks = prototype.get_max_distance_of_nearby_sector_revealed(layer.quality) or 0
    end,
}
