--- Pieces shared by several layer types.
local lib = {}

--- Layer 0 bands are centred on the curve, so a radius r band is 2r-1 tiles wide;
--- side bands are r tiles wide.
--- @param layer Layer
--- @return number
function lib.band_thickness(layer)
    if layer.idx == 0 then
        return 2 * layer.radius - 1
    end
    return layer.radius
end

--- @type LayerField
lib.checkerboard = { name = "checkerboard", widget = "slider", min = -10, max = 10, default = 0 }

--- @type LayerField
lib.radius = { name = "radius", widget = "slider", min = 1, max = 10, default = 1 }

return lib
