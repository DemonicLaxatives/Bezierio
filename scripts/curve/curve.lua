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

--- Insert a point so that it gets index `idx` (#points + 1 appends).
--- @param curve Curve
--- @param idx integer
--- @param point Vector
--- @return integer index
function lib.insert(curve, idx, point)
    idx = math.max(1, math.min(idx, #curve.points + 1))
    table.insert(curve.points, idx, rounded(point))
    return idx
end

--- Reverse the point order, which flips the direction of travel (layers swap sides).
--- @param curve Curve
function lib.reverse(curve)
    local points, n = curve.points, #curve.points
    for i = 1, math.floor(n / 2) do
        points[i], points[n + 1 - i] = points[n + 1 - i], points[i]
    end
end

--- @param curve Curve
function lib.clear(curve)
    curve.points = {}
end

--- Evaluations per segment when looking for the part of the curve nearest a click.
local NEAREST_STEPS = 16

--- Where a point inserted at `position` belongs: the index that puts it into the
--- stretch of curve passing nearest to it. On an open curve, a position beyond the
--- first or last point goes before or after it.
--- @param curve Curve
--- @param position Vector
--- @return integer index  # for lib.insert
function lib.insertion_index(curve, position)
    local raw = curve.points
    -- Distinct points, each mapped to the last raw index of its run of duplicates.
    local points, last_raw = {}, {}
    for i, p in ipairs(raw) do
        local prev = points[#points]
        if prev and prev.x == p.x and prev.y == p.y then
            last_raw[#points] = i
        else
            points[#points + 1] = p
            last_raw[#points] = i
        end
    end
    local closed = lib.is_closed(curve)
    if closed and #points > 1 and points[1].x == points[#points].x and points[1].y == points[#points].y then
        points[#points] = nil
    end
    closed = closed and #points >= 3
    if #points < 2 then return #raw + 1 end

    local best_seg, best_s, best_d = 1, 0, math.huge
    for j, seg in ipairs(catmull_rom.segments(points, closed)) do
        for k = 0, NEAREST_STEPS do
            local s = k / NEAREST_STEPS
            local d = vect.distance(catmull_rom.evaluate(seg, s), position)
            if d < best_d then best_seg, best_s, best_d = j, s, d end
        end
    end

    if not closed then
        local n = #points
        if best_seg == 1 and best_s == 0
            and vect.dot(vect.sub(position, points[1]), vect.sub(points[2], points[1])) < 0 then
            return 1
        end
        if best_seg == n - 1 and best_s == 1
            and vect.dot(vect.sub(position, points[n]), vect.sub(points[n - 1], points[n])) < 0 then
            return #raw + 1
        end
    end
    return last_raw[best_seg] + 1
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
