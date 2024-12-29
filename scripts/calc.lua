local vect = require("scripts.vector_math")
local util = require("__core__/lualib/util")

local lib = {}

--- Evaluate a Bezier curve with De Casteljau's algorithm
--- @param controlPoints Vector[]
--- @param t number
--- @return Vector
function lib.calculateBezierPoint(controlPoints, t)
    local points = util.table.deepcopy(controlPoints)

    -- De Casteljau's algorithm:
    -- Repeatedly interpolate between consecutive points until only one point remains.
    for r = 1, #controlPoints-1 do
        for i = 1, #controlPoints - r do
            local p1, p2 = points[i], points[i+1]
            points[i] = vect.add(vect.scale(1 - t, p1), vect.scale(t, p2))
        end
    end
    return points[1]
end

--- Recursive function to sample points from tStart to tEnd
--- Ensures no segment is longer than maxDistance
--- @param controlPoints Vector[]
--- @param tStart number
--- @param tEnd number
--- @param maxDistance number
--- @param result Vector[]
function lib.sampleBezierSegment(controlPoints, tStart, tEnd, maxDistance, result)
    local pStart = lib.calculateBezierPoint(controlPoints, tStart)
    local pEnd = lib.calculateBezierPoint(controlPoints, tEnd)

    local d = vect.distance(pStart, pEnd)
    if d <= maxDistance then
        table.insert(result, pEnd)
    else
        local tMid = 0.5 * (tStart + tEnd)
        lib.sampleBezierSegment(controlPoints, tStart, tMid, maxDistance, result)
        lib.sampleBezierSegment(controlPoints, tMid, tEnd, maxDistance, result)
    end
end

--- Main function to sample a Bezier curve
--- @param controlPoints Vector[]
--- @param maxDistance number
--- @return Vector[]
function lib.sampleBezierCurve(controlPoints, maxDistance)
    local result = {}
    table.insert(result, lib.calculateBezierPoint(controlPoints, 0.0))
    lib.sampleBezierSegment(controlPoints, 0.0, 1.0, maxDistance, result)
    return result
end

--- Round a curve to a grid
--- @param curve_points Vector[]
--- @param size integer
--- @param cell_center boolean|nil
--- @return Vector[]
function lib.curveRound(curve_points, size, cell_center)
    if cell_center == nil then
        cell_center = size % 2 == 1
    end
    local rounded_curve_points = {vect.cc_round(curve_points[1], cell_center)}

    local j = 1
    for i =  2, #curve_points do
        local point = curve_points[i]
        local rounded_point = vect.cc_round(point, cell_center)
        local dp = vect.sub(rounded_point, rounded_curve_points[j])
        local dp_abs = vect.abs(dp)
        local db_sign = vect.sign(dp)
        local size_offset = vect.sub({x = size, y = size}, dp_abs)

        local insert = false
        for key, elem in pairs(size_offset) do
            if elem <= 0 then
                insert = true
                rounded_point[key] = rounded_point[key] - elem * db_sign[key]
            end
        end

        if insert then
            table.insert(rounded_curve_points, rounded_point)
            j = j + 1
        end
    end
    return rounded_curve_points
end


return lib