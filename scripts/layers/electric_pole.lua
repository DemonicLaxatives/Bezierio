local common = require("scripts.layers.common")

--- Electric poles along the middle of their band: every `spacing` tiles, or with
--- `smart` placement as far apart as the wires reach, closer where powered entities
--- in the plan need it (see build/smart_poles.lua).
--- @type LayerType
return {
    name = "electric-pole",
    entity_types = { "electric-pole" },
    placement = "spaced",
    output = "entity",
    priority = 10,
    fields = {
        {
            name = "spacing", widget = "slider",
            min = function(layer) return layer.size end,
            max = function(layer) return math.max(layer.size, layer.wire_distance) end,
            -- Leave a tile of slack: positions get snapped to the grid after spacing.
            default = function(layer) return math.max(layer.size, layer.wire_distance - 1) end,
            disabled_by = "smart",
        },
        { name = "smart", widget = "checkbox", default = false },
        common.red_wire,
        common.green_wire,
    },
    --- @param layer Layer
    --- @param prototype LuaEntityPrototype
    init = function(layer, prototype)
        layer.wire_distance = math.floor(prototype.get_max_wire_distance(layer.quality))
        layer.reach = prototype.get_supply_area_distance(layer.quality) or 0 -- supply area half-size (e.g. 2.5)
    end,
}
