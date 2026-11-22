--- Curve data and sampling.
---
--- A curve is plain data. Its `kind` is either "catmull_rom", a centripetal
--- Catmull-Rom spline through an ordered list of control points (optionally a
--- closed loop), or a shape (circle, ellipse, arc; see shapes.lua) defined by a few
--- handles. Each kind keeps its own points, so switching kinds loses nothing; the
--- editing functions below work on the active kind's points.
--- Everything downstream only sees sample points.
local vect = require("scripts.vector_math")
local catmull_rom = require("scripts.curve.catmull_rom")
local shapes = require("scripts.curve.shapes")

local lib = {}

--- Curve kinds, in menu order (locale: bezierio-curve-kind.<kind>).
lib.KINDS = { "catmull_rom", "circle", "ellipse", "arc" }

--- @alias CurveKind "catmull_rom"|"circle"|"ellipse"|"arc"

--- @class Curve
--- @field kind CurveKind
--- @field points Vector[]   # spline control points, in order
--- @field closed boolean    # spline: loop back from the last point to the first (needs 3+ points)
--- @field handles table<string, Vector[]>  # shape kind -> its handles
--- @field reversed table<string, boolean>  # kind -> travel the other way (layers swap sides)

--- @return Curve
function lib.new()
    return { kind = "catmull_rom", points = {}, closed = false, handles = { circle = {}, ellipse = {}, arc = {} }, reversed = {} }
end

--- @param curve Curve
--- @return boolean
function lib.is_spline(curve)
    return curve.kind ~= "circle" and curve.kind ~= "ellipse" and curve.kind ~= "arc"
end

--- The points being edited: the spline's control points, or the shape's handles.
--- @param curve Curve
--- @return Vector[]
function lib.active(curve)
    if lib.is_spline(curve) then return curve.points end
    curve.handles = curve.handles or {}
    local list = curve.handles[curve.kind]
    if not list then
        list = {}
        curve.handles[curve.kind] = list
    end
    return list
end

--- How many points the active kind takes (nil: any number).
--- @param curve Curve
--- @return integer|nil
function lib.capacity(curve)
    local names = shapes.HANDLES[curve.kind]
    return names and #names or nil
end

--- @param point Vector
--- @return Vector
local function rounded(point)
    return { x = vect.scalar.round(point.x, 2), y = vect.scalar.round(point.y, 2) }
end

--- Add a point at the end. Coordinates are rounded to 0.01.
--- @param curve Curve
--- @param point Vector
--- @return integer|nil index  # nil when a shape has all its handles already
function lib.append(curve, point)
    local list, capacity = lib.active(curve), lib.capacity(curve)
    if capacity and #list >= capacity then return nil end
    table.insert(list, rounded(point))
    return #list
end

--- Move an existing point. A shape's centre handle moves the whole shape.
--- @param curve Curve
--- @param idx integer
--- @param point Vector
function lib.set_point(curve, idx, point)
    local list = lib.active(curve)
    local old = list[idx]
    if not old then return end
    if idx == 1 and not lib.is_spline(curve) then
        local p = rounded(point)
        lib.translate(curve, p.x - old.x, p.y - old.y)
        return
    end
    list[idx] = rounded(point)
end

--- Move every point of the active kind.
--- @param curve Curve
--- @param dx number
--- @param dy number
function lib.translate(curve, dx, dy)
    local list = lib.active(curve)
    for i, p in ipairs(list) do list[i] = rounded({ x = p.x + dx, y = p.y + dy }) end
end

--- The point a move puts where you click: a shape's centre, or the middle of a
--- spline's points (their bounding box).
--- @param curve Curve
--- @return Vector|nil
function lib.center(curve)
    local list = lib.active(curve)
    if #list == 0 then return nil end
    if not lib.is_spline(curve) then return { x = list[1].x, y = list[1].y } end
    local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(list) do
        x1, y1 = math.min(x1, p.x), math.min(y1, p.y)
        x2, y2 = math.max(x2, p.x), math.max(y2, p.y)
    end
    return { x = (x1 + x2) / 2, y = (y1 + y2) / 2 }
end

--- Move the curve so that its centre (see lib.center) lands on `position`.
--- @param curve Curve
--- @param position Vector
function lib.move_to(curve, position)
    local c = lib.center(curve)
    if c then lib.translate(curve, position.x - c.x, position.y - c.y) end
end

--- Remove a point; later points move up one place.
--- @param curve Curve
--- @param idx integer
function lib.remove(curve, idx)
    local list = lib.active(curve)
    if list[idx] then table.remove(list, idx) end
end

--- Insert a spline point so that it gets index `idx` (#points + 1 appends).
--- Shapes just get the point appended (if they still need one).
--- @param curve Curve
--- @param idx integer
--- @param point Vector
--- @return integer|nil index
function lib.insert(curve, idx, point)
    if not lib.is_spline(curve) then return lib.append(curve, point) end
    idx = math.max(1, math.min(idx, #curve.points + 1))
    table.insert(curve.points, idx, rounded(point))
    return idx
end

--- Flip the direction of travel (layers swap sides). The points stay as they
--- are; each kind remembers its own direction.
--- @param curve Curve
function lib.reverse(curve)
    if type(curve.reversed) ~= "table" then curve.reversed = {} end
    curve.reversed[curve.kind] = not lib.is_reversed(curve) or nil
end

--- Whether the active kind runs the other way.
--- @param curve Curve
--- @return boolean
function lib.is_reversed(curve)
    return type(curve.reversed) == "table" and curve.reversed[curve.kind] == true
end

--- Remove all points of the active kind.
--- @param curve Curve
function lib.clear(curve)
    local list = lib.active(curve)
    for i = #list, 1, -1 do list[i] = nil end
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

--- Index of the (active kind's) point nearest to `position`, if within `radius`.
--- @param curve Curve
--- @param position Vector
--- @param radius number
--- @return integer|nil
function lib.point_near(curve, position, radius)
    local best, best_d = nil, radius
    for i, p in ipairs(lib.active(curve)) do
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

--- The shape the active handles describe (nil for splines, or incomplete shapes).
--- @param curve Curve
--- @return ShapeDescription|nil
function lib.shape(curve)
    if lib.is_spline(curve) then return nil end
    return shapes.describe(curve.kind, lib.active(curve))
end

--- Whether the curve is drawn as a loop: a spline with the closed flag and enough
--- points, a circle or an ellipse.
--- @param curve Curve
--- @return boolean
function lib.is_closed(curve)
    if not lib.is_spline(curve) then
        local shape = lib.shape(curve)
        return shape ~= nil and shape.closed
    end
    return curve.closed == true and #curve.points >= 3
end

--- @param curve Curve
--- @return boolean
function lib.is_drawable(curve)
    if not lib.is_spline(curve) then return lib.shape(curve) ~= nil end
    return #lib.distinct_points(curve) >= 2
end

--- @class CurveSampler
--- @field state CatmullRomSampler|ShapeSampler
--- @field done boolean

--- A resumable sampler; nil when there's nothing to draw yet.
--- @param curve Curve
--- @param max_step number
--- @return CurveSampler|nil
function lib.new_sampler(curve, max_step)
    if not lib.is_spline(curve) then
        local shape = lib.shape(curve)
        if not shape then return nil end
        return { state = shapes.new_sampler(shape, max_step, lib.is_reversed(curve)), done = false }
    end
    local points = lib.distinct_points(curve)
    if #points < 2 then return nil end
    local closed = lib.is_closed(curve) and #points >= 3
    if lib.is_reversed(curve) then
        -- Travel the points backwards; a loop still starts (and has its seam) at P1.
        local backwards = {}
        local first = closed and 1 or 0
        if closed then backwards[1] = points[1] end
        for i = #points, 1 + first, -1 do backwards[#backwards + 1] = points[i] end
        points = backwards
    end
    return { state = catmull_rom.new_sampler(points, max_step, closed), done = false }
end

--- Append up to about `budget` samples (world coordinates) to `out`.
--- @param sampler CurveSampler
--- @param out Vector[]
--- @param budget number
--- @return number used
function lib.step(sampler, out, budget)
    local used
    if sampler.state.kind == "shape" then
        used = shapes.step(sampler.state, out, budget)
    else
        used = catmull_rom.step(sampler.state, out, budget)
    end
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
