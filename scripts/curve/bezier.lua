--- A single Bézier curve through all control points (degree = points - 1).
local vect = require("scripts.vector_math")

local lib = {}

--- De Casteljau evaluation.
--- @param points Vector[]
--- @param t number
--- @return Vector
function lib.evaluate(points, t)
    local work = {}
    for i, p in ipairs(points) do work[i] = { x = p.x, y = p.y } end
    for r = 1, #points - 1 do
        for i = 1, #points - r do
            work[i] = vect.add(vect.scale(1 - t, work[i]), vect.scale(t, work[i + 1]))
        end
    end
    return work[1]
end

--- Append samples for t in (t_start, t_end] so that no step is longer than max_step.
--- @param points Vector[]
--- @param t_start number
--- @param t_end number
--- @param max_step number
--- @param out Vector[]
local function sample_segment(points, t_start, t_end, max_step, out)
    local p_start = lib.evaluate(points, t_start)
    local p_end = lib.evaluate(points, t_end)
    if vect.distance(p_start, p_end) <= max_step then
        table.insert(out, p_end)
    else
        local t_mid = 0.5 * (t_start + t_end)
        sample_segment(points, t_start, t_mid, max_step, out)
        sample_segment(points, t_mid, t_end, max_step, out)
    end
end

--- @class BezierSampler
--- @field origin Vector     # first control point; math is done relative to it for precision
--- @field relative Vector[]
--- @field max_step number
--- @field segments integer  # uniform pieces sampled one at a time
--- @field next_segment integer
--- @field done boolean

--- @param points Vector[]  # defined control points, in order (at least 2)
--- @param max_step number
--- @return BezierSampler
function lib.new_sampler(points, max_step)
    local origin = { x = points[1].x, y = points[1].y }
    local relative = {}
    for i, p in ipairs(points) do relative[i] = vect.sub(p, origin) end
    return {
        origin = origin,
        relative = relative,
        max_step = max_step,
        -- Start from a few uniform segments: subdividing only on endpoint distance
        -- would stop immediately on closed curves (first point == last point).
        segments = 4 * math.max(1, #points - 1),
        next_segment = -1, -- -1: the start point hasn't been emitted yet
        done = false,
    }
end

--- Emit samples (in world coordinates) into `out`.
--- @param sampler BezierSampler
--- @param out Vector[]
--- @param budget number  # max samples to emit (a segment is never split)
--- @return number used
function lib.step(sampler, out, budget)
    local used = 0
    if sampler.next_segment < 0 then
        table.insert(out, vect.add(lib.evaluate(sampler.relative, 0.0), sampler.origin))
        sampler.next_segment = 0
        used = used + 1
    end
    local n = sampler.segments
    while sampler.next_segment < n and used < budget do
        local k = sampler.next_segment
        local local_out = {}
        sample_segment(sampler.relative, k / n, (k + 1) / n, sampler.max_step, local_out)
        for _, p in ipairs(local_out) do
            table.insert(out, vect.add(p, sampler.origin))
        end
        used = used + #local_out
        sampler.next_segment = k + 1
    end
    sampler.done = sampler.next_segment >= n
    return used
end

return lib
