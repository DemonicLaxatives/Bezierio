--- Curve data and sampling.
---
--- A curve is plain data: an ordered list of control points and whether it is a
--- closed loop. It is drawn as a centripetal Catmull-Rom spline through the points.
--- Everything downstream only sees sample points.
local vect = require("scripts.vector_math")
local catmull_rom = require("scripts.curve.catmull_rom")

local lib = {}

--- @class Curve
--- @field kind "catmull_rom"
--- @field points Vector[]   # control points, in order
--- @field closed boolean    # loop back from the last point to the first (needs 3+ points)

--- @return Curve
function lib.new()
    return { kind = "catmull_rom", points = {}, closed = false }
end

--- @param point Vector
--- @return Vector
local function rounded(point)
    return { x = vect.scalar.round(point.x, 2), y = vect.scalar.round(point.y, 2) }
end

--- Add a point at the end. Coordinates are rounded to 0.01.
--- @param curve Curve
--- @param point Vector
--- @return integer index
function lib.append(curve, point)
    table.insert(curve.points, rounded(point))
    return #curve.points
end

--- Move an existing point.
--- @param curve Curve
--- @param idx integer
--- @param point Vector
function lib.set_point(curve, idx, point)
    if curve.points[idx] then curve.points[idx] = rounded(point) end
end

--- Remove a point; later points move up one place.
--- @param curve Curve
--- @param idx integer
function lib.remove(curve, idx)
    if curve.points[idx] then table.remove(curve.points, idx) end
end

--- @param curve Curve
function lib.clear(curve)
    curve.points = {}
end

--- Index of the control point nearest to `position`, if within `radius`.
--- @param curve Curve
--- @param position Vector
--- @param radius number
--- @return integer|nil
function lib.point_near(curve, position, radius)
    local best, best_d = nil, radius
    for i, p in ipairs(curve.points) do
        local d = vect.distance(p, position)
        if d <= best_d then best, best_d = i, d end
    end
    return best
end

--- Control points with consecutive duplicates removed (and, for a loop, a last
--- point equal to the first).
--- @param curve Curve
--- @return Vector[]
function lib.distinct_points(curve)
    local points = {}
    for _, p in ipairs(curve.points) do
        local last = points[#points]
        if not last or last.x ~= p.x or last.y ~= p.y then
            points[#points + 1] = { x = p.x, y = p.y }
        end
    end
    if lib.is_closed(curve) and #points > 1 then
        local first, last = points[1], points[#points]
        if first.x == last.x and first.y == last.y then points[#points] = nil end
    end
    return points
end

--- Whether the curve is drawn as a loop (closed flag and enough points).
--- @param curve Curve
--- @return boolean
function lib.is_closed(curve)
    return curve.closed == true and #curve.points >= 3
end

--- @param curve Curve
--- @return boolean
function lib.is_drawable(curve)
    return #lib.distinct_points(curve) >= 2
end

--- @class CurveSampler
--- @field state CatmullRomSampler
--- @field done boolean

--- A resumable sampler; nil when the curve has fewer than two distinct points.
--- @param curve Curve
--- @param max_step number
--- @return CurveSampler|nil
function lib.new_sampler(curve, max_step)
    local points = lib.distinct_points(curve)
    if #points < 2 then return nil end
    local closed = lib.is_closed(curve) and #points >= 3
    return { state = catmull_rom.new_sampler(points, max_step, closed), done = false }
end

--- Append up to about `budget` samples (world coordinates) to `out`.
--- @param sampler CurveSampler
--- @param out Vector[]
--- @param budget number
--- @return number used
function lib.step(sampler, out, budget)
    local used = catmull_rom.step(sampler.state, out, budget)
    sampler.done = sampler.state.done
    return used
end

--- All samples at once (small curves, tests).
--- @param curve Curve
--- @param max_step number
--- @return Vector[]
function lib.samples(curve, max_step)
    local out = {}
    local sampler = lib.new_sampler(curve, max_step)
    if not sampler then return out end
    while not sampler.done do lib.step(sampler, out, math.huge) end
    return out
end

return lib
