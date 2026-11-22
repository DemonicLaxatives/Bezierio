--- One colour per layer, shared by the layer list and the build preview.
local lib = {}

local COLORS = {
    { r = 0.95, g = 0.75, b = 0.20 }, -- layer 0: amber
    { r = 0.30, g = 0.70, b = 1.00 }, -- 1: blue
    { r = 0.95, g = 0.40, b = 0.40 }, -- -1: red
    { r = 0.50, g = 0.90, b = 0.40 }, -- 2: green
    { r = 0.80, g = 0.50, b = 1.00 }, -- -2: purple
    { r = 0.30, g = 0.90, b = 0.85 }, -- 3: teal
    { r = 1.00, g = 0.60, b = 0.85 }, -- -3: pink
    { r = 0.80, g = 0.80, b = 0.80 }, -- 4: grey
}

--- @param layer_idx integer
--- @param alpha number|nil
--- @return Color
function lib.layer_color(layer_idx, alpha)
    -- 0, 1, -1, 2, -2, ... -> 1, 2, 3, 4, 5, ...
    local slot = layer_idx > 0 and 2 * layer_idx or (layer_idx < 0 and -2 * layer_idx + 1 or 1)
    local c = COLORS[(slot - 1) % #COLORS + 1]
    return { r = c.r, g = c.g, b = c.b, a = alpha or 1 }
end

return lib
