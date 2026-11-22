---@diagnostic disable: undefined-global
-- Editing control points (scripts/curve/curve.lua): insert, reverse, and where a
-- shift-click inserts a point.
--   lua5.4 tests/unit/curve_edit.lua
local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")
local curve_lib = require("scripts.curve.curve")

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

local function make(points, closed)
    local c = curve_lib.new()
    for _, p in ipairs(points) do curve_lib.append(c, p) end
    c.closed = closed or false
    return c
end

local function xs(c)
    local out = {}
    for i, p in ipairs(c.points) do out[i] = string.format("%g,%g", p.x, p.y) end
    return table.concat(out, " ")
end

-- insert / reverse
local c = make({ { x = 0, y = 0 }, { x = 10, y = 0 } })
check(curve_lib.insert(c, 2, { x = 5.004, y = 1 }) == 2 and xs(c) == "0,0 5,1 10,0", "insert in the middle, rounded")
check(curve_lib.insert(c, 99, { x = 20, y = 0 }) == 4, "insert past the end appends")
check(curve_lib.insert(c, 0, { x = -10, y = 0 }) == 1 and c.points[1].x == -10, "insert before the start")
-- Reverse: the points stay put, the curve runs the other way
local before = xs(c)
curve_lib.reverse(c)
check(xs(c) == before and curve_lib.is_reversed(c), "reverse keeps the points")
local forward = curve_lib.samples(make({ { x = 0, y = 0 }, { x = 10, y = 5 }, { x = 20, y = 0 } }), 0.25)
local rc = make({ { x = 0, y = 0 }, { x = 10, y = 5 }, { x = 20, y = 0 } })
curve_lib.reverse(rc)
local backward = curve_lib.samples(rc, 0.25)
local same = #forward == #backward
for i = 1, #forward do
    local f, b = forward[i], backward[#backward + 1 - i]
    if not b or math.abs(f.x - b.x) > 1e-9 or math.abs(f.y - b.y) > 1e-9 then same = false end
end
check(same, "an open curve is sampled exactly backwards")
local loop = make({ { x = 0, y = 0 }, { x = 10, y = 0 }, { x = 10, y = 10 }, { x = 0, y = 10 } }, true)
curve_lib.reverse(loop)
local ls = curve_lib.samples(loop, 0.25)
check(ls[1].x == 0 and ls[1].y == 0 and ls[#ls].x == 0 and ls[#ls].y == 0, "a reversed loop still starts and ends at P1")
check(ls[3].y > 0 and math.abs(ls[3].x) < 1, "and heads for P4 first")
curve_lib.reverse(loop)
check(not curve_lib.is_reversed(loop), "reverse twice: back to forwards")

-- insertion_index on an open line P1 (0,0) - P2 (10,0) - P3 (20,0)
local line = make({ { x = 0, y = 0 }, { x = 10, y = 0 }, { x = 20, y = 0 } })
check(curve_lib.insertion_index(line, { x = 5, y = 1 }) == 2, "between P1 and P2")
check(curve_lib.insertion_index(line, { x = 15, y = -1 }) == 3, "between P2 and P3")
check(curve_lib.insertion_index(line, { x = -3, y = 0.5 }) == 1, "before the start")
check(curve_lib.insertion_index(line, { x = 25, y = 0 }) == 4, "after the end")
check(curve_lib.insertion_index(line, { x = 0.5, y = 3 }) == 2, "beside P1, not before it")

-- The nearest stretch of curve, not the nearest chord: an S-bend
local bend = make({ { x = 0, y = 0 }, { x = 10, y = 10 }, { x = 20, y = 0 }, { x = 30, y = 10 } })
check(curve_lib.insertion_index(bend, { x = 15, y = 5 }) == 3, "middle of the S")

-- A closed square: the closing stretch from P4 back to P1 appends
local square = make({ { x = 0, y = 0 }, { x = 10, y = 0 }, { x = 10, y = 10 }, { x = 0, y = 10 } }, true)
check(curve_lib.insertion_index(square, { x = 5, y = 11 }) == 4, "loop: between P3 and P4")
check(curve_lib.insertion_index(square, { x = -1, y = 5 }) == 5, "loop: between P4 and P1")
check(curve_lib.insertion_index(square, { x = 5, y = -1 }) == 2, "loop: between P1 and P2")

-- Duplicate points: insert after the whole run
local dup = make({ { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 10, y = 0 } })
check(curve_lib.insertion_index(dup, { x = 5, y = 0.5 }) == 3, "after a run of duplicates")

-- Too few points: append
check(curve_lib.insertion_index(make({ { x = 1, y = 1 } }), { x = 5, y = 5 }) == 2, "one point: append")
check(curve_lib.insertion_index(make({}), { x = 5, y = 5 }) == 1, "no points: append")

-- Inserting where the curve already passes keeps it drawable and in order
local r = helpers.rng(7)
for _ = 1, 50 do
    local pts = helpers.random_points(r)
    local closed = #pts >= 3 and r.int(0, 1) == 1
    local cv = make(pts, closed)
    local samples = curve_lib.samples(cv, 0.25)
    if #samples > 2 then
        local target = samples[r.int(2, #samples - 1)]
        local idx = curve_lib.insertion_index(cv, target)
        check(idx >= 1 and idx <= #cv.points + 1, "index in range")
        curve_lib.insert(cv, idx, target)
        check(curve_lib.is_drawable(cv), "still drawable")
    end
end

print(string.format("%d/%d curve edit checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
