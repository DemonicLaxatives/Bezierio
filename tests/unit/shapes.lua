---@diagnostic disable: undefined-global
-- Shapes from handles (scripts/curve/shapes.lua, curve.lua): what the handles mean,
-- exact sampling, direction, and editing shapes with the curve functions.
--   lua5.4 tests/unit/shapes.lua
dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")
local curve_lib = require("scripts.curve.curve")

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

--- A curve of a shape kind with these handles.
local function shape(kind, handles, reversed)
    local c = curve_lib.new()
    c.kind = kind
    for _, h in ipairs(handles) do curve_lib.append(c, h) end
    if reversed then curve_lib.reverse(c) end
    return c
end

-- Circle: centre + a point on it. Every sample is on the circle; closed; starts at
-- the radius handle; steps no longer than asked.
local c = shape("circle", { { x = 10.5, y = -3 }, { x = 10.5, y = -28 } })
check(curve_lib.is_drawable(c) and curve_lib.is_closed(c), "circle drawable and closed")
local s = curve_lib.samples(c, 0.25)
local worst, longest = 0, 0
for i, p in ipairs(s) do
    worst = math.max(worst, math.abs(math.sqrt((p.x - 10.5) ^ 2 + (p.y + 3) ^ 2) - 25))
    if i > 1 then longest = math.max(longest, math.sqrt((p.x - s[i - 1].x) ^ 2 + (p.y - s[i - 1].y) ^ 2)) end
end
check(worst < 1e-9, "samples exactly on the circle: " .. worst)
check(longest <= 0.25 + 1e-9, "steps short enough: " .. longest)
check(near(s[1].x, 10.5) and near(s[1].y, -28), "starts at the radius handle")
check(s[#s].x == s[1].x and s[#s].y == s[1].y, "loop ends exactly where it starts")
-- clockwise on screen: from north, the next samples go east (x grows)
check(s[5].x > s[1].x, "runs clockwise")
local r = curve_lib.samples(shape("circle", { { x = 10.5, y = -3 }, { x = 10.5, y = -28 } }, true), 0.25)
check(r[5].x < r[1].x, "reversed runs the other way")

-- Ellipse: centre, axis end (radius + rotation), width point (other radius)
local e = shape("ellipse", { { x = 0, y = 0 }, { x = 30, y = 30 }, { x = -5, y = 5 } })
local d = curve_lib.shape(e)
check(d and near(d.a, math.sqrt(1800)) and near(d.b, math.sqrt(50)) and near(d.rot, math.pi / 4), "ellipse radii and rotation")
local on = true
for _, p in ipairs(curve_lib.samples(e, 0.25)) do
    -- in the rotated frame: (u/a)^2 + (v/b)^2 = 1
    local u = (p.x + p.y) / math.sqrt(2)
    local v = (p.y - p.x) / math.sqrt(2)
    if not near((u / d.a) ^ 2 + (v / d.b) ^ 2, 1, 1e-9) then on = false end
end
check(on, "samples exactly on the rotated ellipse")
check(curve_lib.is_closed(e), "ellipse is closed")
check(not curve_lib.is_drawable(shape("ellipse", { { x = 0, y = 0 }, { x = 30, y = 30 }, { x = 30.1, y = 30.1 } })), "flat ellipse not drawn")

-- Arc: centre, start (radius), end (direction only); clockwise from start to end
local a = shape("arc", { { x = 0, y = 0 }, { x = 0, y = -20 }, { x = 50, y = 0 } })
check(curve_lib.is_drawable(a) and not curve_lib.is_closed(a), "arc drawable, open")
s = curve_lib.samples(a, 0.25)
check(near(s[1].x, 0) and near(s[1].y, -20) and near(s[#s].x, 20) and near(s[#s].y, 0), "north to east, the end at the start's radius")
local all_ne = true
for _, p in ipairs(s) do if p.x < -1e-9 or p.y > 1e-9 then all_ne = false end end
check(all_ne, "the short way round, clockwise")
local long = curve_lib.samples(shape("arc", { { x = 0, y = 0 }, { x = 20, y = 0 }, { x = 0, y = -5 } }), 0.25)
check(#long > 2.9 * #s and #long < 3.1 * #s, "east to north clockwise is three quarters")
s = curve_lib.samples(shape("arc", { { x = 0, y = 0 }, { x = 0, y = -20 }, { x = 50, y = 0 } }, true), 0.25)
check(near(s[1].x, 20) and near(s[#s].y, -20), "reversed arc runs from the end back to the start")

-- Construction: what the drawing shows about how the handles are used
local shapes = require("scripts.curve.shapes")
local con = shapes.construction("ellipse", { { x = 0, y = 0 }, { x = 10, y = 0 }, { x = 7, y = -4 } })
local at = con.used[1].at
check(con.used[1].handle == 3 and near(at.x, 0) and near(at.y, -4), "ellipse width handle projected onto the perpendicular axis")
check(#con.axes == 2 and near(con.axes[1].from.x, -10) and near(con.axes[1].to.x, 10)
    and near(math.abs(con.axes[2].from.y), 4) and near(con.axes[2].from.x, 0), "both axes, through the centre")
con = shapes.construction("arc", { { x = 0, y = 0 }, { x = 0, y = -20 }, { x = 3, y = 4 } })
at = con.used[1].at
check(near(at.x, 12) and near(at.y, 16), "arc end at the start's radius, in the end handle's direction")
check(#shapes.construction("circle", { { x = 0, y = 0 }, { x = 5, y = 0 } }).used == 0, "a circle uses its handles as they are")
check(shapes.construction("arc", { { x = 0, y = 0 } }) == nil, "nothing for an incomplete shape")

-- Incomplete or too small
check(not curve_lib.is_drawable(shape("circle", { { x = 0, y = 0 } })), "circle needs two handles")
check(not curve_lib.is_drawable(shape("circle", { { x = 0, y = 0 }, { x = 0.2, y = 0 } })), "tiny circle not drawn")
check(not curve_lib.is_drawable(shape("arc", { { x = 0, y = 0 }, { x = 5, y = 0 }, { x = 9, y = 0 } })), "zero-length arc not drawn")

-- Editing: handles are capped, the centre moves the whole shape, kinds keep their points
local k = curve_lib.new()
curve_lib.append(k, { x = 1, y = 1 }); curve_lib.append(k, { x = 2, y = 2 }); curve_lib.append(k, { x = 3, y = 1 })
k.kind = "circle"
check(#curve_lib.active(k) == 0, "circle starts with no handles")
check(curve_lib.append(k, { x = 0, y = 0 }) == 1 and curve_lib.append(k, { x = 10, y = 0 }) == 2, "two handles")
check(curve_lib.append(k, { x = 5, y = 5 }) == nil and #curve_lib.active(k) == 2, "a third is refused")
curve_lib.set_point(k, 1, { x = 3, y = 4 })
local h = curve_lib.active(k)
check(h[1].x == 3 and h[1].y == 4 and h[2].x == 13 and h[2].y == 4, "moving the centre moves the shape")
curve_lib.set_point(k, 2, { x = 3, y = 14 })
check(h[1].x == 3 and h[2].y == 14, "the radius handle moves alone")
curve_lib.reverse(k)
check(curve_lib.is_reversed(k) and h[1].x == 3, "reverse flips the direction, not the handles")
k.kind = "catmull_rom"
check(#curve_lib.active(k) == 3 and k.points[3].x == 3, "the spline's points are untouched")
check(not curve_lib.is_reversed(k), "each kind has its own direction")
check(curve_lib.insert(shape("arc", { { x = 0, y = 0 } }), 1, { x = 5, y = 5 }) == 2, "insert on a shape appends")

-- Move: the centre goes where you click
curve_lib.move_to(k, { x = 10, y = 10 })
local center = curve_lib.center(k)
-- points (1,1) (2,2) (3,1): the middle of their bounding box is (2, 1.5)
check(center.x == 10 and center.y == 10 and k.points[1].x == 9 and k.points[1].y == 9.5, "spline moved by its middle")
k.kind = "circle"
curve_lib.move_to(k, { x = -5, y = 0 })
check(h[1].x == -5 and h[1].y == 0 and h[2].x == -5 and h[2].y == 10, "circle moved by its centre")
curve_lib.clear(k)
check(#curve_lib.active(k) == 0 and #k.points == 3, "clear empties only the active kind")

print(string.format("%d/%d shape checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
