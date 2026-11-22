local common = require("scripts.layers.common")

--- Land mines over their band: scattered (each cell gets one with a probability
--- of `density` percent, the same cells every time) or on a regular grid (every
--- `spacing` tiles in both directions, aligned to the map), optionally connected
--- with red and/or green wire.
--- @type LayerType

--- A well-mixed number 0..99 per cell, the same on every machine (exact integer
--- arithmetic that stays below 2^53, so doubles and integers agree).
--- @param x integer
--- @param y integer
--- @return integer
local function cell_roll(x, y)
    local p = 1000003
    local h = (x * 92821 + y * 68917 + 12345) % p
    h = (h * h + 7919) % p
    h = (h * h + 104729) % p
    return h % 100
end

return {
    name = "land-mine",
    entity_types = { "land-mine" },
    placement = "band",
    output = "entity",
    priority = 100,
    fields = {
        { name = "pattern", widget = "choice", options = { "scattered", "grid" }, label_prefix = "bezierio-mine-pattern", default = "scattered" },
        {
            name = "density", widget = "slider", min = 1, max = 100, default = 20,
            visible_if = function(layer) return layer.pattern ~= "grid" end,
        },
        {
            name = "mine_spacing", widget = "slider", min = 1, max = 16, default = 3,
            visible_if = function(layer) return layer.pattern == "grid" end,
        },
        { name = "radius", widget = "slider", min = 1, max = 32, default = 3 },
        common.red_wire,
        common.green_wire,
    },
    thickness = common.band_thickness,
    keep = function(layer, x, y)
        if layer.pattern == "grid" then
            local step = layer.mine_spacing or 3
            return x % step == 0 and y % step == 0
        end
        return cell_roll(x, y) < (layer.density or 20)
    end,
    --- @param layer Layer
    --- @param prototype LuaEntityPrototype
    init = function(layer, prototype)
        layer.circuit_distance = prototype.get_max_circuit_wire_distance(layer.quality) or 0
    end,
    cell_roll = cell_roll,
}
