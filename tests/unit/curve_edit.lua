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
curve_lib.reverse(c)
check(c.points[1].x == 20 and c.points[5].x == -10 and c.points[3].x == 5, "reverse, odd count")
local even = make({ { x = 1, y = 0 }, { x = 2, y = 0 }, { x = 3, y = 0 }, { x = 4, y = 0 } })
curve_lib.reverse(even)
check(xs(even) == "4,0 3,0 2,0 1,0", "reverse, even count")

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
