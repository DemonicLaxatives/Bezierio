local common = require("scripts.layers.common")
local palette = require("scripts.palette")

--- Lamps, spaced along the middle of their band, in the lamp's own colour, one
--- colour, or a rainbow that cycles along the curve.
--- @type LayerType

local options = { "default" }
for _, entry in ipairs(palette.NAMED) do table.insert(options, entry.name) end
table.insert(options, "rainbow")

--- Hue (0..1) to a fully saturated colour.
--- @param h number
--- @return Color
local function hue(h)
    local function f(n)
        local k = (n + h * 6) % 6
        return 1 - math.max(0, math.min(k, 4 - k, 1))
    end
    return { r = f(5), g = f(3), b = f(1) }
end

return {
    name = "lamp",
    entity_types = { "lamp" },
    placement = "spaced",
    output = "entity",
    priority = 30,
    fields = {
        common.spacing(function() return 32 end, function() return 4 end),
        { name = "color", widget = "choice", options = options, label_prefix = "bezierio-lamp-color", default = "default" },
        {
            name = "rainbow_length", widget = "slider", min = 8, max = 512, default = 64,
            visible_if = function(layer) return layer.color == "rainbow" end,
        },
    },
    --- @param layer Layer
    --- @param entity PlannedEntity
    --- @param info PlacementInfo
    decorate = function(layer, entity, info)
        if layer.color == "rainbow" then
            entity.color = hue(((info.arc or 0) / (layer.rainbow_length or 64)) % 1)
        elseif layer.color and layer.color ~= "default" then
            local c = palette.named(layer.color)
            entity.color = { r = c.r, g = c.g, b = c.b }
        end
    end,
    hue = hue,
}
