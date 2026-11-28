local common = require("scripts.layers.common")
local rails = require("scripts.build.rails")

--- Rails: track fitted to the middle of the band from the game's rail pieces
--- (build/rails.lua), with signals every so many wagons on the side trains travel
--- (both sides for track used both ways).
--- @type LayerType
return {
    name = "straight-rail",
    entity_types = { "straight-rail" },
    placement = "rail",
    output = "entity",
    priority = 1,
    fields = {
        {
            name = "direction_of_travel", widget = "slider", min = -1, max = 1, default = 1,
            labels = {
                [-1] = { "label.direction-backwards" },
                [0] = { "label.direction-both" },
                [1] = { "label.direction-forwards" },
            },
        },
        { name = "signal_spacing", widget = "slider", min = 0, max = 20, default = 0 },
        -- 0: as close to the curve as rails go; higher: longer straights and
        -- steadier bends, straying further (build/rails.lua, `smoothing`); 2
        -- calms the back and forth of the tightest fit, staying close
        { name = "smoothing", widget = "slider", min = 0, max = 6, default = 2 },
        {
            name = "wall_gates", widget = "checkbox", default = true,
            visible_if = function(layer) return layer.gate_name ~= nil end,
        },
        {
            name = "elevated", widget = "checkbox", default = false,
            visible_if = function(layer) return layer.can_elevate == true end,
        },
        {
            name = "ramps", widget = "checkbox", default = true,
            visible_if = function(layer) return layer.can_elevate == true and layer.elevated == true end,
        },
    },
    --- Ground track is as wide as its rails (the footprint size). Elevated track
    --- stands on supports and ramps twice as wide: its band makes room for them,
    --- so the layers beside it don't run into them.
    --- @param layer Layer
    thickness = function(layer)
        if layer.elevated and layer.can_elevate then return math.max(layer.size or 1, rails.elevated_width()) end
        return layer.size or 1
    end,
    --- @param layer Layer
    init = function(layer)
        -- Rail items per piece (curved and half-diagonal pieces cost more).
        layer.rail_costs = {}
        for _, name in ipairs({ "straight-rail", "half-diagonal-rail", "curved-rail-a", "curved-rail-b" }) do
            local p = prototypes.entity[name]
            local items = p and p.items_to_place_this
            layer.rail_costs[name] = items and items[1] and items[1].count or 1
        end
        local gate = prototypes.entity["gate"]
        layer.gate_name = gate and gate.type == "gate" and gate.name or nil
        local signal = prototypes.entity["rail-signal"]
        layer.signal_name = signal and signal.name or nil
        layer.signal_item = signal and common.item_for(signal) or nil
        -- Elevated rails (elevated-rails mod): supports and ramps.
        local support, ramp = prototypes.entity["rail-support"], prototypes.entity["rail-ramp"]
        layer.can_elevate = (prototypes.entity["elevated-straight-rail"] ~= nil and support ~= nil) or nil
        layer.support_name = support and support.name or nil
        layer.support_item = support and common.item_for(support) or nil
        layer.ramp_item = ramp and common.item_for(ramp) or nil
    end,
}
