--- Curve data and sampling, independent of how the curve is defined.
---
--- A curve is plain data: a kind and numbered control points (sparse: unset or
--- half-entered points are skipped). Everything downstream only sees sample points,
--- so new kinds (e.g. piecewise cubic) only need a sampler module here.
local vect = require("scripts.vector_math")

local lib = {}

--- @class Curve
--- @field kind string                              # key in lib.kinds
--- @field points table<integer, {x: number?, y: number?}>  # sparse, by control point number

--- @class CurveKind
--- @field new_sampler fun(points: Vector[], max_step: number): table
--- @field step fun(sampler: table, out: Vector[], budget: number): number

--- @type table<string, CurveKind>
lib.kinds = {
    bezier = require("scripts.curve.bezier"),
}

--- @param kind string|nil
--- @return Curve
function lib.new(kind)
    return { kind = kind or "bezier", points = {} }
end

--- Set one control point (coordinates rounded to 0.01), or clear it with nil.
--- A point with only x or only y is kept but not used until complete.
--- @param curve Curve
--- @param idx integer
--- @param point {x: number?, y: number?}|nil
function lib.set_point(curve, idx, point)
    if point then
        point = {
            x = point.x and vect.scalar.round(point.x, 2),
            y = point.y and vect.scalar.round(point.y, 2),
        }
        if point.x == nil and point.y == nil then point = nil end
    end
    curve.points[idx] = point
end

--- @param curve Curve
function lib.clear(curve)
    curve.points = {}
end

--- Complete control points in order of their numbers.
--- @param curve Curve
--- @return Vector[]
function lib.defined_points(curve)
    local indices = {}
    for idx, p in pairs(curve.points) do
        if p.x and p.y then table.insert(indices, idx) end
    end
    table.sort(indices)
    local points = {}
    for i, idx in ipairs(indices) do
        local p = curve.points[idx]
        points[i] = { x = p.x, y = p.y }
    end
    return points
end

--- @param curve Curve
--- @return boolean
function lib.is_drawable(curve)
    return #lib.defined_points(curve) >= 2
end

--- @class CurveSampler
--- @field kind string
--- @field state table
--- @field done boolean

--- A resumable sampler; nil when the curve has fewer than two points.
--- @param curve Curve
--- @param max_step number
--- @return CurveSampler|nil
function lib.new_sampler(curve, max_step)
    local points = lib.defined_points(curve)
    if #points < 2 then return nil end
    local kind = lib.kinds[curve.kind] or error("Unknown curve kind: " .. tostring(curve.kind))
    return { kind = curve.kind, state = kind.new_sampler(points, max_step), done = false }
end

--- Append up to about `budget` samples (world coordinates) to `out`.
--- @param sampler CurveSampler
--- @param out Vector[]
--- @param budget number
--- @return number used
function lib.step(sampler, out, budget)
    local used = lib.kinds[sampler.kind].step(sampler.state, out, budget)
    sampler.done = sampler.state.done
    return used
end

--- All samples at once (for small curves and tests).
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
