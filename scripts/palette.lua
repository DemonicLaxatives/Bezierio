--- Colours: one per layer (shared by the layer list and the build preview), and the
--- named colours players can pick for the rest of the drawing (view settings).
local lib = {}

local LAYER_COLORS = {
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
    local c = LAYER_COLORS[(slot - 1) % #LAYER_COLORS + 1]
    return { r = c.r, g = c.g, b = c.b, a = alpha or 1 }
end

--- Colours offered in the view settings, in menu order. Names are locale keys
--- (bezierio-color.<name>) and what's stored.
lib.NAMED = {
    { name = "white",   color = { r = 1.00, g = 1.00, b = 1.00 } },
    { name = "grey",    color = { r = 0.55, g = 0.55, b = 0.55 } },
    { name = "black",   color = { r = 0.05, g = 0.05, b = 0.05 } },
    { name = "red",     color = { r = 1.00, g = 0.10, b = 0.10 } },
    { name = "orange",  color = { r = 1.00, g = 0.50, b = 0.10 } },
    { name = "amber",   color = { r = 1.00, g = 0.85, b = 0.20 } },
    { name = "green",   color = { r = 0.20, g = 0.85, b = 0.20 } },
    { name = "teal",    color = { r = 0.20, g = 0.80, b = 0.75 } },
    { name = "blue",    color = { r = 0.10, g = 0.30, b = 0.70 } },
    { name = "sky",     color = { r = 0.35, g = 0.70, b = 1.00 } },
    { name = "violet",  color = { r = 0.50, g = 0.00, b = 1.00 } },
    { name = "magenta", color = { r = 0.90, g = 0.20, b = 0.80 } },
    { name = "crimson", color = { r = 0.50, g = 0.00, b = 0.20 } },
}

--- @type table<string, integer>
local named_index = {}
for i, entry in ipairs(lib.NAMED) do named_index[entry.name] = i end

--- @param name string
--- @return integer|nil  # position in lib.NAMED
function lib.named_index(name)
    return named_index[name]
end

--- @param name string
--- @param alpha number|nil
--- @return Color
function lib.named(name, alpha)
    local entry = lib.NAMED[named_index[name] or 1]
    local c = entry.color
    return { r = c.r, g = c.g, b = c.b, a = alpha or 1 }
end

--- @class ViewSettings
--- @field curve_color string        # names from palette.NAMED
--- @field point_color string
--- @field selected_color string
--- @field order_color string        # the dashed lines joining the points in order
--- @field warning_color string
--- @field curve_width integer       # pixels
--- @field map_scale integer         # the curve and points on the map: sizes times this
--- @field preview_opacity integer   # percent, for entities; tiles get half

--- Per-player drawing settings (the view settings pane). Defaults match the
--- drawing before the settings existed.
--- @type ViewSettings
lib.VIEW_DEFAULTS = {
    curve_color = "blue",
    point_color = "crimson",
    selected_color = "amber",
    order_color = "violet",
    warning_color = "red",
    curve_width = 5,
    map_scale = 3,
    preview_opacity = 30,
}

--- The colour settings, in the order the view settings pane shows them.
lib.VIEW_COLORS = { "curve_color", "point_color", "selected_color", "order_color", "warning_color" }

--- The number settings: range and step.
lib.VIEW_NUMBERS = {
    { name = "curve_width",     min = 1, max = 10,  step = 1 },
    { name = "map_scale",       min = 1, max = 10,  step = 1 },
    { name = "preview_opacity", min = 5, max = 100, step = 5 },
}

return lib
