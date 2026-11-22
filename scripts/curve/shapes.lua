--- Exact shapes defined by handles placed with the pointer:
---   circle   centre, a point on the circle
---   ellipse  centre, the end of one axis (sets its radius and the rotation), a
---            point whose distance from that axis sets the other radius
---   arc      centre, start (sets the radius), end (only its direction counts);
---            the arc runs clockwise on screen from start to end
--- Shapes are sampled directly (not through control points), so they are exact.
--- Plain functions on data (no game API).
local lib = {}

--- Handles each shape needs, and their labels (locale: bezierio-handle.<label>).
lib.HANDLES = {
    circle = { "center", "radius" },
    ellipse = { "center", "axis", "width" },
    arc = { "center", "start", "end" },
}

--- Shapes smaller than this (tiles) aren't drawn.
lib.MIN_RADIUS = 0.5

--- @class ShapeDescription
--- @field cx number
--- @field cy number
--- @field a number        # radius along the rotated x axis
--- @field b number        # radius along the rotated y axis
--- @field rot number      # rotation of the axes (radians)
--- @field from number     # parameter angle where travel starts (radians)
--- @field span number     # parameter angle travelled (radians, > 0)
--- @field closed boolean

--- The shape the handles describe, or nil when they're incomplete or too small.
--- Angles grow clockwise on screen (the map's y axis points down).
--- @param kind string  # "circle", "ellipse" or "arc"
--- @param h Vector[]
--- @return ShapeDescription|nil
function lib.describe(kind, h)
    local names = lib.HANDLES[kind]
    if not names or #h < #names then return nil end
    local c = h[1]
    local dx, dy = h[2].x - c.x, h[2].y - c.y
    local r = math.sqrt(dx * dx + dy * dy)
    if r < lib.MIN_RADIUS then return nil end
    local start = math.atan2(dy, dx)
    if kind == "circle" then
        return { cx = c.x, cy = c.y, a = r, b = r, rot = 0, from = start, span = 2 * math.pi, closed = true }
    elseif kind == "ellipse" then
        local ux, uy = dx / r, dy / r
        local b = math.abs(ux * (h[3].y - c.y) - uy * (h[3].x - c.x))
        if b < lib.MIN_RADIUS then return nil end
        return { cx = c.x, cy = c.y, a = r, b = b, rot = start, from = 0, span = 2 * math.pi, closed = true }
    else -- arc
        local ex, ey = h[3].x - c.x, h[3].y - c.y
        if ex == 0 and ey == 0 then return nil end
        local span = (math.atan2(ey, ex) - start) % (2 * math.pi)
        if span < 1e-6 then return nil end
        return { cx = c.x, cy = c.y, a = r, b = r, rot = 0, from = start, span = span, closed = false }
    end
end

--- How the handles are used, for drawing the construction: for each handle that
--- is only partly used, the point actually used (`handle` -> `at`), and for an
--- ellipse its two axes as segments through the centre.
--- @param kind string  # "circle", "ellipse" or "arc"
--- @param h Vector[]
--- @return {used: {handle: integer, at: Vector}[], axes: {from: Vector, to: Vector}[]}|nil
function lib.construction(kind, h)
    local d = lib.describe(kind, h)
    if not d then return nil end
    local c = { x = d.cx, y = d.cy }
    if kind == "ellipse" then
        local ux, uy = math.cos(d.rot), math.sin(d.rot)
        local nx, ny = -uy, ux
        -- The width handle, projected onto the perpendicular axis.
        local side = (h[3].x - c.x) * nx + (h[3].y - c.y) * ny >= 0 and 1 or -1
        local at = { x = c.x + side * d.b * nx, y = c.y + side * d.b * ny }
        return {
            used = { { handle = 3, at = at } },
            axes = {
                { from = { x = c.x - d.a * ux, y = c.y - d.a * uy }, to = { x = c.x + d.a * ux, y = c.y + d.a * uy } },
                { from = { x = c.x - d.b * nx, y = c.y - d.b * ny }, to = { x = c.x + d.b * nx, y = c.y + d.b * ny } },
            },
        }
    elseif kind == "arc" then
        -- The end handle's direction, at the start's radius.
        return { used = { { handle = 3, at = lib.point(d, 1) } }, axes = {} }
    end
    return { used = {}, axes = {} }
end

--- Point at parameter t in [0, 1] along the shape.
--- @param d ShapeDescription
--- @param t number
--- @return Vector
function lib.point(d, t)
    local phi = d.from + t * d.span
    local x, y = d.a * math.cos(phi), d.b * math.sin(phi)
    local cos_r, sin_r = math.cos(d.rot), math.sin(d.rot)
    return { x = d.cx + x * cos_r - y * sin_r, y = d.cy + x * sin_r + y * cos_r }
end

--- @class ShapeSampler
--- @field kind "shape"
--- @field shape ShapeDescription
--- @field reversed boolean
--- @field n integer
--- @field i integer
--- @field done boolean

--- A resumable sampler with no step longer than max_step. Closed shapes end on
--- exactly their first sample, as the planner expects of loops.
--- @param d ShapeDescription
--- @param max_step number
--- @param reversed boolean  # travel the other way
--- @return ShapeSampler
function lib.new_sampler(d, max_step, reversed)
    -- The speed along the shape is at most max(a, b) per radian.
    local n = math.max(4, math.ceil(d.span * math.max(d.a, d.b) / max_step))
    return { kind = "shape", shape = d, reversed = reversed == true, n = n, i = 0, done = false }
end

--- Append up to `budget` samples to `out`.
--- @param s ShapeSampler
--- @param out Vector[]
--- @param budget number
--- @return number used
function lib.step(s, out, budget)
    local used = 0
    while s.i <= s.n and used < budget do
        local t = s.i / s.n
        if s.reversed then t = 1 - t end
        if s.shape.closed and s.i == s.n then
            out[#out + 1] = { x = out[1].x, y = out[1].y }
        else
            out[#out + 1] = lib.point(s.shape, t)
        end
        s.i = s.i + 1
        used = used + 1
    end
    s.done = s.i > s.n
    return used
end

return lib
