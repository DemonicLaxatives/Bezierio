--- Electric poles, spaced along the middle of their band.
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
            max = function(layer) return layer.wire_distance end,
            -- Leave a tile of slack: positions get snapped to the grid after spacing.
            default = function(layer) return math.max(layer.size, layer.wire_distance - 1) end,
        },
        { name = "smart_placement",            widget = "checkbox", default = false },
        { name = "connect_with_circuit_wires", widget = "checkbox", default = false },
    },
    --- @param layer Layer
    --- @param prototype LuaEntityPrototype
    init = function(layer, prototype)
        layer.wire_distance = math.floor(prototype.get_max_wire_distance(layer.quality))
        layer.reach = math.floor(prototype.get_supply_area_distance(layer.quality) or 0)
    end,
}
