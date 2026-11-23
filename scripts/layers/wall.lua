local common = require("scripts.layers.common")

--- Walls fill their band. With `gates`, a wall cell that lands on an existing
--- straight rail becomes a gate when building (build/executor.lua). Walls only
--- join side by side, so cells meeting only at a corner get a corner cell filled
--- (`join_corners`, the planner's joins stage).
--- @type LayerType
return {
    name = "wall",
    entity_types = { "wall" },
    placement = "band",
    output = "entity",
    priority = 100,
    join_corners = true,
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
