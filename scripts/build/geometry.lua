--- Geometry of a sampled curve, measured on the tile grid.
---
--- Every sample gets a frame: position `p`, unit tangent `t`, unit normal `n` (to the
--- right of the direction of travel P1 -> Pn in Factorio's y-down world) and
--- `w = |n.x| + |n.y|`.
---
--- Distances across the curve are in "grid units": u = d / w, the width of one grid
--- cell projected onto the normal. A band one unit wide is then a 4-connected
--- staircase on diagonals (no corner-only joins between walls).
local vect = require("scripts.vector_math")

local lib = {}

--- @class CurveFrame
--- @field p Vector  # position
--- @field t Vector  # unit tangent
--- @field n Vector  # unit normal
--- @field w number  # |n.x| + |n.y|

--- Quantization of u: on rational slopes (45° especially) cell centres land exactly on
--- band edges, and sampling noise (~1e-5) would otherwise push both cells of a
--- staircase step out of the band, breaking 4-connectivity.
local U_QUANTUM = 1024

--- Bucket size of the spatial index, in tiles.
local BUCKET = 4

--- Max |along-tangent offset| for a frame to count as a foot point of a position
--- (samples are at most 0.25 apart).
local FOOT_TOLERANCE = 0.3

--- @param a Vector
--- @param b Vector
--- @return number
function lib.dist2(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
end

--- Unit tangent at sample i from its neighbours (zero vector for repeated points).
--- On a closed loop the first and last samples are the same point, so their
--- neighbours wrap around.
--- @param points Vector[]
--- @param i integer
--- @param closed boolean|nil
--- @return Vector
function lib.raw_tangent(points, i, closed)
    local count = #points
    local a, b
    if closed and count > 2 then
        a = points[i - 1] or points[count - 1]
        b = points[i + 1] or points[2]
    else
        a = points[math.max(1, i - 1)]
        b = points[math.min(count, i + 1)]
    end
    return vect.normalize(vect.sub(b, a))
end

--- @param t Vector
--- @return boolean
function lib.is_zero(t)
    return t.x == 0 and t.y == 0
end

--- Fill in normal and grid width once the frame's tangent is final.
--- @param frame CurveFrame
function lib.finish_frame(frame)
    frame.n = vect.perpendicular(frame.t)
    frame.w = math.abs(frame.n.x) + math.abs(frame.n.y)
end

--- @alias FrameIndex table<integer, table<integer, integer[]>>  # bucket x -> bucket y -> frame indices

--- Add frame j to a spatial index.
--- @param index FrameIndex
--- @param frames CurveFrame[]
--- @param j integer
function lib.index_add(index, frames, j)
    local p = frames[j].p
    local bx, by = math.floor(p.x / BUCKET), math.floor(p.y / BUCKET)
    local column = index[bx]
    if not column then column = {}; index[bx] = column end
    local list = column[by]
    if not list then list = {}; column[by] = list end
    list[#list + 1] = j
end

--- Index of the frame nearest to `c` (exact): search rings of buckets outward until
--- no unsearched bucket can hold anything closer.
--- @param frames CurveFrame[]
--- @param index FrameIndex
--- @param c Vector
--- @return integer index, number squared_distance
function lib.nearest_frame(frames, index, c)
    local dist2 = lib.dist2
    local cx, cy = math.floor(c.x / BUCKET), math.floor(c.y / BUCKET)
    local best, best_d = 1, math.huge
    local r = 0
    while true do
        for bx = cx - r, cx + r do
            local column = index[bx]
            if column then
                local edge = (bx == cx - r) or (bx == cx + r)
                local step = edge and 1 or 2 * r
                for by = cy - r, cy + r, step do
                    local list = column[by]
                    if list then
                        for _, j in ipairs(list) do
                            local d = dist2(c, frames[j].p)
                            if d < best_d or (d == best_d and j < best) then best, best_d = j, d end
                        end
                    end
                end
            end
        end
        -- Everything in rings beyond r is at least r * BUCKET away.
        if best_d <= (r * BUCKET) ^ 2 or r > 4096 then return best, best_d end
        r = r + 1
    end
end

--- Signed grid-unit distance of `c` measured from frame j, or nil when `c` isn't
--- beside the curve at that frame: more than half a cell ahead of or behind it
--- along the tangent. That cuts off the ends of open curves, and the spurs that
--- would otherwise stick out past hairpin tips and cusps (where the nearest point
--- is the tip, but the cell lies beyond it). On smooth stretches the nearest
--- sample is always within ~0.125 tiles along the tangent, so it never applies.
--- @param frames CurveFrame[]
--- @param j integer
--- @param c Vector
--- @return number|nil u, number along
local function frame_u(frames, j, c)
    local f = frames[j]
    local rel = vect.sub(c, f.p)
    local along = vect.dot(rel, f.t)
    local along_u = along / (math.abs(f.t.x) + math.abs(f.t.y))
    if along_u < -0.5 or along_u >= 0.5 then return nil, along end
    return vect.dot(rel, f.n) / f.w, along
end

--- Signed grid-unit distance of a position from the curve, or nil when it lies
--- beyond the ends of the curve.
---
--- Normally measured from the nearest point. Where the curve passes near itself,
--- another branch can be (slightly) farther in plain distance but closer in grid
--- units; the position then belongs to that branch, otherwise lines would get gaps
--- at junctions. Only foot points within sqrt(2) * nearest distance can win.
--- @param frames CurveFrame[]
--- @param index FrameIndex
--- @param c Vector
--- @return number|nil u, integer|nil j  # j: the sample it belongs to
function lib.grid_distance(frames, index, c)
    local j0, d0 = lib.nearest_frame(frames, index, c)
    local best_u = frame_u(frames, j0, c)
    local best_j = j0

    local radius = math.sqrt(d0) * 1.415 + 0.05
    local radius2 = radius * radius
    for bx = math.floor((c.x - radius) / BUCKET), math.floor((c.x + radius) / BUCKET) do
        local column = index[bx]
        if column then
            for by = math.floor((c.y - radius) / BUCKET), math.floor((c.y + radius) / BUCKET) do
                local list = column[by]
                if list then
                    for _, j in ipairs(list) do
                        if j ~= j0 and lib.dist2(c, frames[j].p) <= radius2 then
                            local u, along = frame_u(frames, j, c)
                            if u and math.abs(along) <= FOOT_TOLERANCE
                                and (best_u == nil or math.abs(u) < math.abs(best_u)) then
                                best_u, best_j = u, j
                            end
                        end
                    end
                end
            end
        end
    end
    if not best_u then return nil end
    return math.floor(best_u * U_QUANTUM + 0.5) / U_QUANTUM, best_j
end

--- The point at grid distance u from frame f (on the normal through it).
--- @param f CurveFrame
--- @param u number
--- @return Vector
function lib.offset_point(f, u)
    return vect.add(f.p, vect.scale(u * f.w, f.n))
end

return lib
