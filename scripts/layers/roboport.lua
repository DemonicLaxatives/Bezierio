--- Roboports, spaced along the middle of their band.
--- @type LayerType
return {
    name = "roboport",
    entity_types = { "roboport" },
    placement = "spaced",
    output = "entity",
    priority = 20,
    fields = {
        {
            name = "spacing", widget = "slider",
            min = function(layer) return layer.size end,
            max = function(layer) return math.max(layer.size, 2 * layer.logistic_radius) end,
            default = function(layer) return math.max(layer.size, layer.logistic_radius) end,
        },
    },
    --- @param layer Layer
    --- @param prototype LuaEntityPrototype
    init = function(layer, prototype)
        layer.logistic_radius = math.floor(prototype.logistic_radius or layer.size)
    end,
}
