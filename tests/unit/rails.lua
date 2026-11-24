---@diagnostic disable: undefined-global
-- Rail track fitting (scripts/build/rails.lua, rail_data.lua): continuous track
-- near the curve, loops that close, elevated track with ramps and supports in
-- reach, signal spacing.
--   lua5.4 tests/unit/rails.lua
local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")
local rails = require("scripts.build.rails")
local data = require("scripts.build.rail_data")

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

local function rail_layer(extra)
    local l = { idx = 0, type = "straight-rail", name = "straight-rail", quality = "normal", size = 2, offset = 0, direction_of_travel = 1,
        signal_spacing = 0, signal_name = "rail-signal", signal_item = "rail-signal", support_name = "rail-support", support_item = "rail-support",
        ramp_item = "rail-ramp", can_elevate = true, rail_costs = {} }
    for k, v in pairs(extra or {}) do l[k] = v end
    return l
end

--- Track pieces of a plan in order, and whether each joins the one before.
local function track(plan)
    local pieces, joined = {}, true
    for _, e in ipairs(plan.entities) do
        if e.track then
            local prev = pieces[#pieces]
            if prev and (prev.track.to.x ~= e.track.from.x or prev.track.to.y ~= e.track.from.y) then joined = false end
            pieces[#pieces + 1] = e
        end
    end
    return pieces, joined
end

--- Furthest a joint lies from the curve samples.
local function stray(pieces, samples)
    local worst = 0
    for _, p in ipairs(pieces) do
        local best = math.huge
        for _, q in ipairs(samples) do best = math.min(best, (q.x - p.track.to.x) ^ 2 + (q.y - p.track.to.y) ^ 2) end
        worst = math.max(worst, math.sqrt(best))
    end
    return worst
end

local curve_lib = require("scripts.curve.curve")
local function samples_of(points, closed)
    local c = curve_lib.new()
    for _, p in ipairs(points) do curve_lib.append(c, p) end
    c.closed = closed or false
    return curve_lib.samples(c, 0.5)
end

-- The data: three ways on from every end, the same geometry for elevated track
for d = 0, 15 do
    local _, entry = next(data.ends[d])
    check(#entry.extensions == 3, "direction " .. d .. ": straight on, left, right")
end
check(data.ramps and data.ramps.up[0] and data.ramps.down[0] and data.support and data.support.range, "ramps and supports recorded")

-- Calm random curves: continuous track, close to the curve
local r = helpers.rng(2468)
local worst_all, warned = 0, 0
for it = 1, 25 do
    local pts, x, y, ang = {}, 0, 0, r.range(0, 6.28)
    for i = 1, 4 do pts[i] = { x = x, y = y }; ang = ang + r.range(-0.7, 0.7); x, y = x + 50 * math.cos(ang), y + 50 * math.sin(ang) end
    local plan = helpers.plan(pts, { [0] = rail_layer() })
    local pieces, joined = track(plan)
    check(#pieces > 20 and joined, "calm curve #" .. it .. ": one continuous track")
    worst_all = math.max(worst_all, stray(pieces, samples_of(pts)))
    warned = warned + #plan.warnings
end
check(worst_all <= 2.5, string.format("track stays within 2.5 tiles of calm curves (worst %.2f)", worst_all))
print(string.format("(calm curves: worst stray %.2f tiles, %d warnings)", worst_all, warned))

-- Loops close onto their start
for _, radius in ipairs({ 30, 60, 120 }) do
    local c = helpers.shape_curve("circle", { { x = 0.5, y = 0.5 }, { x = 0.5, y = 0.5 - radius } })
    local plan = helpers.plan_curve(c, { [0] = rail_layer() })
    local pieces, joined = track(plan)
    local first, last = pieces[1], pieces[#pieces]
    check(joined and last.track.to.x == first.track.from.x and last.track.to.y == first.track.from.y,
        "circle r=" .. radius .. ": the loop closes")
    check(#plan.warnings == 0, "circle r=" .. radius .. ": stays on the circle (" .. #plan.warnings .. " warnings)")
end

-- Elevated: elevated pieces, a ramp up and down (ramps only go straight, so this
-- curve starts and ends heading roughly east), every joint within reach of a
-- support or a ramp's top
local pts = { { x = 0.5, y = 0.5 }, { x = 40.5, y = 0.5 }, { x = 110.5, y = 30.5 }, { x = 160.5, y = 30.5 } }
local plan = helpers.plan(pts, { [0] = rail_layer({ elevated = true, ramps = true }) })
local pieces, joined = track(plan)
check(joined, "elevated track continuous")
check(pieces[1].name == "rail-ramp" and pieces[#pieces].name == "rail-ramp", "ramp up at the start, down at the end")
local ok_names = true
for i = 2, #pieces - 1 do if not pieces[i].name:find("^elevated%-") then ok_names = false end end
check(ok_names, "elevated pieces between the ramps")
local supports = {}
for _, e in ipairs(plan.entities) do if e.name == "rail-support" then supports[#supports + 1] = e.position end end
check(#supports >= 10, "supports: " .. #supports)
local range, ramp_range = data.support.range - 1, data.support.ramp_range - 1
local uncovered = 0
for i = 2, #pieces - 1 do
    local j = pieces[i].track.to
    local covered = false
    for _, s in ipairs(supports) do if math.sqrt((s.x - j.x) ^ 2 + (s.y - j.y) ^ 2) <= range then covered = true end end
    for _, ramp in ipairs({ pieces[1].track.to, pieces[#pieces].track.from }) do
        if math.sqrt((ramp.x - j.x) ^ 2 + (ramp.y - j.y) ^ 2) <= ramp_range then covered = true end
    end
    if not covered then uncovered = uncovered + 1 end
end
check(uncovered == 0, "every joint within reach of a support or a ramp: " .. uncovered .. " not")
check(#plan.warnings == 0, "elevated track stays on the curve, ramps included (" .. #plan.warnings .. " warnings)")
-- A curve starting at an angle: the ramp has to go straight, so the track is off
-- for a while after it, and says so.
local slanted = helpers.plan({ { x = 0.5, y = 0.5 }, { x = 80.5, y = 30.5 }, { x = 160.5, y = 34.5 } }, { [0] = rail_layer({ elevated = true, ramps = true }) })
check(#slanted.warnings > 0, "a ramp that can't follow the curve is reported")
-- Elevated track leaves the ground free: a wall right beside it isn't cut where
-- the track sways (supports stand on the track's own line). A loop has no ramps.
local ring = helpers.shape_curve("circle", { { x = 0.5, y = 0.5 }, { x = 0.5, y = -40.5 } })
local wall1 = { idx = 1, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0 }
local under = helpers.plan_curve(ring, { [0] = rail_layer({ elevated = true }), [1] = wall1 })
local ground = helpers.plan_curve(ring, { [0] = rail_layer(), [1] = wall1 })
local function walls(p) local n = 0 for _, e in ipairs(p.entities) do if e.name == "wall" then n = n + 1 end end return n end
check(walls(under) >= walls(ground), "walls beside elevated track: " .. walls(under) .. " vs " .. walls(ground) .. " beside ground track")

-- Signals every N wagons (7 tiles each), forwards only / both ways
local function signals(spacing, travel)
    local p = helpers.plan(pts, { [0] = rail_layer({ signal_spacing = spacing, direction_of_travel = travel }) })
    local n = 0
    for _, e in ipairs(p.entities) do if e.name == "rail-signal" then n = n + 1 end end
    return n, p
end
local n3 = signals(3, 1)
local n6 = signals(6, 1)
check(n3 >= 6 and n6 >= 3 and n3 > n6 * 1.6, "signals every 3 wagons: " .. n3 .. ", every 6: " .. n6)
-- (a signal whose spot is taken moves on to the next joint)
check(signals(3, 0) >= 1.6 * n3, "both ways: about twice the signals")
check(signals(0, 1) == 0, "spacing 0: no signals")

-- A reported curve that ends pointing back across its own middle: the track used to
-- stop halfway (it looked past the end along the end's tangent), and elevated
-- track whose band bent until near the end got no ramp down.
local winding = { { x = -567, y = 596.05 }, { x = -464.22, y = 596.2 }, { x = -412.73, y = 554.5 }, { x = -284.73, y = 565.33 },
    { x = -190.8, y = 672.9 }, { x = -234.12, y = 716.93 }, { x = -330.24, y = 702.82 }, { x = -417.03, y = 705.27 }, { x = -415.22, y = 644.98 } }
local function reaches_end(plan, idx)
    local last
    for _, e in ipairs(plan.entities) do if e.track and e.layer == idx then last = e end end
    return last and math.abs(last.track.to.x - -415) < 12 and last.track.to.y < 660
end
local p0 = helpers.plan(winding, { [0] = rail_layer() })
check(reaches_end(p0, 0), "winding curve: the track runs to the end")
-- (its last corner, radius 11.6, is tighter than rails turn: warned there only)
local elsewhere = 0
for _, w in ipairs(p0.warnings) do if math.abs(w.x - -417) > 6 or math.abs(w.y - 705) > 6 then elsewhere = elsewhere + 1 end end
check(elsewhere == 0, "winding curve: warnings only at the corner too tight for rails")
for _, elevated in ipairs({ false, true }) do
    local p = helpers.plan(winding, {
        [-2] = rail_layer({ idx = -2, elevated = elevated, ramps = true, direction_of_travel = -1, signal_spacing = 6 }),
        [-1] = { idx = -1, type = "roboport", name = "roboport", quality = "normal", size = 4, offset = 0, priority = 20, spacing = 50 },
        [0] = { idx = 0, type = "electric-pole", name = "pole", quality = "normal", size = 2, offset = 0, priority = 10, spacing = 41, wire_distance = 30 },
        [1] = rail_layer({ idx = 1, elevated = elevated, ramps = true, signal_spacing = 6 }),
    })
    local ramps = 0
    for _, e in ipairs(p.entities) do if e.name == "rail-ramp" then ramps = ramps + 1 end end
    local what = elevated and "elevated" or "ground"
    check(reaches_end(p, -2) and reaches_end(p, 1), "winding curve, two " .. what .. " tracks: both run to the end")
    check(#p.warnings == 0, "winding curve, two " .. what .. " tracks: no warnings (" .. #p.warnings .. ")")
    if elevated then check(ramps == 4, "a ramp up and down on each track: " .. ramps) end
end

-- Progress only goes up, through every stage (rails included)
do
    local planner = require("scripts.build.planner")
    local curve = require("scripts.curve.curve")
    local c = curve.new()
    for _, p in ipairs({ { x = 0, y = 0 }, { x = 40, y = 10 }, { x = 70, y = 50 } }) do curve.append(c, p) end
    local job = planner.new_job(c, {
        [0] = rail_layer(),
        [1] = { idx = 1, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0 },
        [2] = { idx = 2, type = "lamp", name = "lamp", quality = "normal", size = 1, offset = 0, spacing = 5 },
    })
    local last, back, stages = 0, nil, {}
    repeat
        local done = planner.step(job, 20)
        stages[job.stage] = true
        local now = planner.progress(job)
        if now < last and not back then back = string.format("%s: %.3f after %.3f", job.stage, now, last) end
        last = now
    until done
    check(stages.rails and back == nil, "progress never goes back: " .. tostring(back))
end

print(string.format("%d/%d rail checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
