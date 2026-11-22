local vect = require("scripts.vector_math")
local state = require("scripts.state")
local calc = require("scripts.curve_math.calc")

local lib = {}

--- Collect the defined control points in index order (1..9), relative to the first one.
--- @param points table<integer, Vector|nil>
--- @return Vector[], Vector|nil
function lib.processControlPoints(points)
    local filtered_points = {}
    local p0 = nil
    for i = 1, state.MAX_CONTROL_POINTS do
        local point = points[i]
        if point and point.x and point.y then
            if not p0 then
                p0 = { x = point.x, y = point.y }
            end
            table.insert(filtered_points, vect.sub(point, p0))
        end
    end
    return filtered_points, p0
end

--- Set (or clear, with point = nil) one control point and recompute the curve.
--- @param player LuaPlayer
--- @param idx integer
--- @param point Vector|nil
function lib.updateControlPoint(player, idx, point)
    local curve = state.curve(player.index)

    if point then
        point = { x = point.x, y = point.y }
        if point.x then point.x = vect.D1.round(point.x, 2) end
        if point.y then point.y = vect.D1.round(point.y, 2) end
    end

    curve.raw_control_points[idx] = point
    lib.recompute(player.index)
end

--- @param player_index integer
function lib.recompute(player_index)
    local curve = state.curve(player_index)
    local control_points, p0 = lib.processControlPoints(curve.raw_control_points)
    curve.control_points = control_points
    curve.p0 = p0
    curve.degree = #control_points - 1
    curve.parameters_changed = true
    state.mark_dirty(player_index)
end

--- @param player_index integer
function lib.clear(player_index)
    local curve = state.curve(player_index)
    curve.raw_control_points = {}
    lib.recompute(player_index)
end

--- Curve sample points in world coordinates.
--- @param curve BezierCurve
--- @param max_distance number
--- @return Vector[]
function lib.worldSamples(curve, max_distance)
    if curve.degree < 1 or not curve.p0 then return {} end
    local points = calc.sampleBezierCurve(curve.control_points, max_distance)
    for i = 1, #points do
        points[i] = vect.add(points[i], curve.p0)
    end
    return points
end

return lib
