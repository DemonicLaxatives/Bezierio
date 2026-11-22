local common = require("scripts.layers.common")

--- Electric turrets (laser, tesla), spaced along the middle of their band. Ones
--- that can't turn all the way round face outward or inward.
--- @type LayerType
return {
    name = "electric-turret",
    entity_types = { "electric-turret" },
    placement = "spaced",
    output = "entity",
    priority = 50,
    fields = {
        {
            name = "spacing", widget = "slider",
            min = function(layer) return layer.size end,
            max = function(layer) return math.max(layer.size, 10) end,
            default = function(layer) return layer.size end,
        },
        common.facing,
    },
    init = common.init_turret,
    decorate = common.decorate_turret,
}
