--- Centripetal Catmull-Rom spline: passes through every control point, and each
--- point only bends the curve between its neighbours. The centripetal form
--- (alpha = 0.5) never forms cusps or self-loops within a segment.
local vect = require("scripts.vector_math")

local lib = {}

local ALPHA = 0.5

--- Interpolate between a and b for t in [ta, tb].
local function lerp(a, b, ta, tb, t)
    local span = tb - ta
    return vect.add(vect.scale((tb - t) / span, a), vect.scale((t - ta) / span, b))
end

--- @class CatmullRomSegment
--- @field p Vector[]   # 4 points: before, start, end, after
--- @field t number[]   # 4 knots

--- @param p0 Vector
--- @param p1 Vector
--- @param p2 Vector
--- @param p3 Vector
--- @return CatmullRomSegment
local function segment(p0, p1, p2, p3)
    local t0 = 0
    local t1 = t0 + vect.distance(p0, p1) ^ ALPHA
    local t2 = t1 + vect.distance(p1, p2) ^ ALPHA
    local t3 = t2 + vect.distance(p2, p3) ^ ALPHA
    return { p = { p0, p1, p2, p3 }, t = { t0, t1, t2, t3 } }
end

--- Point on a segment, s in [0, 1] from its start to its end (Barry-Goldman).
--- @param seg CatmullRomSegment
--- @param s number
--- @return Vector
function lib.evaluate(seg, s)
    local p, k = seg.p, seg.t
    local t = k[2] + s * (k[3] - k[2])
    local a1 = lerp(p[1], p[2], k[1], k[2], t)
    local a2 = lerp(p[2], p[3], k[2], k[3], t)
    local a3 = lerp(p[3], p[4], k[3], k[4], t)
    local b1 = lerp(a1, a2, k[1], k[3], t)
    local b2 = lerp(a2, a3, k[2], k[4], t)
    return lerp(b1, b2, k[2], k[3], t)
end

--- Segments through the points. Open curves get reflected end neighbours so the
--- curve starts at the first point and ends at the last; closed curves wrap.
--- @param points Vector[]  # at least 2, no consecutive duplicates
--- @param closed boolean
--- @return CatmullRomSegment[]
function lib.segments(points, closed)
    local n = #points
    local segs = {}
    if closed then
        for i = 1, n do
            local p0 = points[(i - 2) % n + 1]
            local p1 = points[i]
            local p2 = points[i % n + 1]
            local p3 = points[(i + 1) % n + 1]
            segs[i] = segment(p0, p1, p2, p3)
        end
    else
        for i = 1, n - 1 do
            local p1, p2 = points[i], points[i + 1]
            local p0 = points[i - 1] or vect.sub(vect.scale(2, p1), p2)
            local p3 = points[i + 2] or vect.sub(vect.scale(2, p2), p1)
            segs[i] = segment(p0, p1, p2, p3)
        end
    end
    return segs
end

--- Append samples for s in (s_start, s_end] so that no step is longer than max_step.
local function sample_range(seg, s_start, s_end, max_step, out)
    local a = lib.evaluate(seg, s_start)
    local b = lib.evaluate(seg, s_end)
    if vect.distance(a, b) <= max_step then
        table.insert(out, b)
    else
        local s_mid = 0.5 * (s_start + s_end)
        sample_range(seg, s_start, s_mid, max_step, out)
        sample_range(seg, s_mid, s_end, max_step, out)
    end
end

--- Pieces each segment is split into before adaptive subdivision, so a segment
--- that bulges between close endpoints is still sampled.
local PIECES = 4

--- @class CatmullRomSampler
--- @field origin Vector          # math is done relative to the first point for precision
--- @field segments CatmullRomSegment[]
--- @field max_step number
--- @field next_piece integer     # -1: start point not emitted yet
--- @field done boolean

--- @param points Vector[]
--- @param max_step number
--- @param closed boolean
--- @return CatmullRomSampler
function lib.new_sampler(points, max_step, closed)
    local origin = { x = points[1].x, y = points[1].y }
    local relative = {}
    for i, p in ipairs(points) do relative[i] = vect.sub(p, origin) end
    return {
        origin = origin,
        segments = lib.segments(relative, closed),
        max_step = max_step,
        next_piece = -1,
        done = false,
    }
end

--- Emit samples (world coordinates) into `out`.
--- @param sampler CatmullRomSampler
--- @param out Vector[]
--- @param budget number  # max samples to emit (a piece is never split)
--- @return number used
function lib.step(sampler, out, budget)
    local used = 0
    local total = #sampler.segments * PIECES
    if sampler.next_piece < 0 then
        table.insert(out, vect.add(lib.evaluate(sampler.segments[1], 0), sampler.origin))
        sampler.next_piece = 0
        used = used + 1
    end
    while sampler.next_piece < total and used < budget do
        local piece = sampler.next_piece
        local seg = sampler.segments[math.floor(piece / PIECES) + 1]
        local k = piece % PIECES
        local local_out = {}
        sample_range(seg, k / PIECES, (k + 1) / PIECES, sampler.max_step, local_out)
        for _, p in ipairs(local_out) do
            table.insert(out, vect.add(p, sampler.origin))
        end
        used = used + #local_out
        sampler.next_piece = piece + 1
    end
    sampler.done = sampler.next_piece >= total
    return used
end

return lib
