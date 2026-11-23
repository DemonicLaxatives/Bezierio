local common = require("scripts.layers.common")

--- Walls fill their band. With `gates`, a wall cell that lands on an existing
--- straight rail becomes a gate when building (build/executor.lua).
--- @type LayerType
return {
    name = "wall",
    entity_types = { "wall" },
    placement = "band",
    output = "entity",
    priority = 100,
    fields = {
        common.checkerboard,
        common.radius,
        {
            name = "gates", widget = "checkbox", default = true,
            visible_if = function(layer) return layer.gate_name ~= nil end,
        },
    },
    thickness = common.band_thickness,
    --- @param layer Layer
    init = function(layer)
        local gate = prototypes.entity["gate"]
        if not (gate and gate.type == "gate") then
            gate = nil
            for _, p in pairs(prototypes.get_entity_filtered { { filter = "type", type = "gate" } }) do
                gate = gate or p
            end
        end
        layer.gate_name = gate and gate.name or nil
    end,
}
