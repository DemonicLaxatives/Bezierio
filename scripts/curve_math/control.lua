local vect = require("scripts.vector_math")

local lib = {}

--- Filter out points containting nil 
--- @param points Vector[]
--- @return Vector[], Vector|nil
function lib.processControlPoints(points)
    local filtered_points = {}
    local p0 = nil
    for _, point in pairs(points) do
        if point then
            if point.x and point.y then
                if not p0 then
                    p0 = point
                end
                table.insert(filtered_points, vect.sub(point, p0))
            end
        end
    end
    return filtered_points, p0
end

--- @param player LuaPlayer
--- @param idx integer
--- @param point Vector|nil
function lib.updateControlPoint(player, idx, point)
    local curve_cache = storage.controllers[player.index].curve_cache[0]

    if point then
        if point.x then
            point.x = vect.D1.round(point.x, 2)
        end
        if point.y then
            point.y = vect.D1.round(point.y, 2)
        end
    end

    curve_cache.raw_control_points[idx] = point
    local control_points, p0 = lib.processControlPoints(curve_cache.raw_control_points)

    curve_cache.control_points = control_points
    curve_cache.p0 = p0
    curve_cache.degree = #control_points - 1
    curve_cache.parameters_changed = true
end

return lib