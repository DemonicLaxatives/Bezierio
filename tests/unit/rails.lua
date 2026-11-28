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

-- Smoothing: longer straights and steadier bends, the track straying further.
-- On calm random curves, each level changes its turning less often, level 6
-- under half as often as level 0, and the track stays within the half tile per
-- level it may stray (plus what a tight fit strays), with no more warnings.
do
    local function turns_of(plan)
        -- a piece's turn from its ends' directions isn't kept: from its shape
        local changes, len, prev = 0, 0, nil
        for _, e in ipairs(plan.entities) do
            if e.track then
                local kind = e.name:find("curved") and ("c" .. e.direction) or "s"
                -- (two curved pieces in a row bend the same way: one bend)
                local bend = kind ~= "s" and "c" or "s"
                if prev and bend ~= prev then changes = changes + 1 end
                prev = bend
                len = len + math.sqrt((e.track.to.x - e.track.from.x) ^ 2 + (e.track.to.y - e.track.from.y) ^ 2)
            end
        end
        return changes / len * 100
    end
    local rs = helpers.rng(97531)
    local curves = {}
    for it = 1, 12 do
        local pts, x, y, ang = {}, 0, 0, rs.range(0, 6.28)
        for i = 1, 5 do pts[i] = { x = x, y = y }; ang = ang + rs.range(-0.6, 0.6); x, y = x + 60 * math.cos(ang), y + 60 * math.sin(ang) end
        curves[it] = pts
    end
    local by_level, ok_stray, warnings = {}, true, {}
    for _, level in ipairs({ 0, 2, 4, 6 }) do
        local sum, worst, warned = 0, 0, 0
        for _, pts in ipairs(curves) do
            local plan = helpers.plan(pts, { [0] = rail_layer({ smoothing = level }) })
            local pieces, joined = track(plan)
            if not joined then ok_stray = false end
            sum = sum + turns_of(plan)
            worst = math.max(worst, stray(pieces, samples_of(pts)))
            warned = warned + #plan.warnings
        end
        by_level[level], warnings[level] = sum / #curves, warned
        if worst > 2.5 + level * 0.5 then ok_stray = false end
        print(string.format("(smoothing %d: %.1f changes between bending and straight per 100 tiles, worst stray %.2f, %d warnings)",
            level, sum / #curves, worst, warned))
    end
    check(ok_stray, "smoothing: continuous track within its allowance of the curve")
    check(by_level[2] < by_level[0] and by_level[4] < by_level[2] and by_level[6] < by_level[4], "smoothing: each level turns back and forth less")
    check(by_level[6] < by_level[0] * 0.5, string.format("smoothing 6: under half the changes of 0 (%.1f vs %.1f)", by_level[6], by_level[0]))
    check(warnings[2] <= warnings[0] and warnings[4] <= warnings[0] and warnings[6] <= warnings[0], "smoothing: no more warnings")
    -- a layer from before the setting gets the default, 2 (registry.check_fields,
    -- run on every layer before a plan)
    local registry = require("scripts.layers.registry")
    local old = rail_layer()
    old.smoothing = nil
    registry.check_fields(old)
    check(old.smoothing == 2, "no smoothing setting: the default, 2 (" .. tostring(old.smoothing) .. ")")
end

-- A reported railway (example-bps/rail-regression.txt): two tracks with roboports
-- and poles between them. At P5 the curve turns sharply, so the band of the
-- track on the inside has nearly a corner there. The track used to overshoot
-- it, straight on for 70 tiles, and only then swing back (the lookahead saw no
-- way back within reach). Now the line is rounded before the fit, so the track
-- turns early and cuts inside the corner, away from the other track.
do
    local pts = { { x = -150.75, y = -403.25 }, { x = -140.95, y = -467.82 }, { x = -89.83, y = -489.15 }, { x = -21.83, y = -477.17 },
        { x = 31.88, y = -460.71 }, { x = 43.42, y = -491.84 }, { x = 87.74, y = -547.43 } }
    local p = helpers.plan(pts, {
        [-2] = rail_layer({ idx = -2, direction_of_travel = -1, signal_spacing = 4 }),
        [-1] = { idx = -1, type = "roboport", name = "roboport", quality = "normal", size = 4, offset = 0, priority = 20, spacing = 33 },
        [0] = { idx = 0, type = "electric-pole", name = "pole", quality = "normal", size = 2, offset = 0, priority = 10, spacing = 31, wire_distance = 30 },
        [1] = rail_layer({ idx = 1, signal_spacing = 4 }),
    })
    check(#p.warnings == 0, "railway with a sharp bend: no warnings (" .. #p.warnings .. ")")
    local tracks = { [-2] = {}, [1] = {} }
    for _, e in ipairs(p.entities) do if e.track then table.insert(tracks[e.layer], e) end end
    local ends = 0
    for _, idx in ipairs({ -2, 1 }) do
        local last = tracks[idx][#tracks[idx]]
        if last and math.abs(last.track.to.x - 87.74) < 12 and math.abs(last.track.to.y - -547.43) < 12 then ends = ends + 1 end
    end
    check(ends == 2, "railway with a sharp bend: both tracks run to the end")
    local samples = samples_of(pts)
    -- (the band is about 8 tiles out; the bend, about 110°, rounded to the
    -- rails' 13 tiles of radius, puts the track about 10 more inside its corner)
    check(stray(tracks[-2], samples) < 22, string.format("the inner track stays near the curve (%.1f tiles at most; it ran 70 off)", stray(tracks[-2], samples)))
    local closest = math.huge
    for _, a in ipairs(tracks[-2]) do
        for _, b in ipairs(tracks[1]) do
            closest = math.min(closest, math.sqrt((a.track.to.x - b.track.to.x) ^ 2 + (a.track.to.y - b.track.to.y) ^ 2))
        end
    end
    check(closest >= 4, string.format("the two tracks keep apart (%.1f tiles at closest)", closest))
end
-- rails.round_line: a right-angle corner rounded until rails can follow it, the
-- line away from it untouched
do
    local line = { xs = {}, ys = {}, tx = {}, ty = {}, n = 0 }
    local function add(x, y, tx, ty) line.n = line.n + 1; line.xs[line.n], line.ys[line.n], line.tx[line.n], line.ty[line.n] = x, y, tx, ty end
    for x = -60, 0 do add(x, 0, 1, 0) end
    for y = -1, -60, -1 do add(0, y, 0, -1) end
    local before = { xs = {}, ys = {} }
    for i = 1, line.n do before.xs[i], before.ys[i] = line.xs[i], line.ys[i] end
    rails.round_line(line)
    local worst, far_moved = 0, false
    for i = 1, line.n do
        -- (the bend over BEND_SPAN tiles each way, as round_line measures it)
        local a, b = math.max(1, i - rails.BEND_SPAN), math.min(line.n, i + rails.BEND_SPAN)
        if a < i and b > i then
            local ux, uy = line.xs[i] - line.xs[a], line.ys[i] - line.ys[a]
            local vx, vy = line.xs[b] - line.xs[i], line.ys[b] - line.ys[i]
            local lu, lv = math.sqrt(ux * ux + uy * uy), math.sqrt(vx * vx + vy * vy)
            local turn = math.acos(math.max(-1, math.min(1, (ux * vx + uy * vy) / (lu * lv))))
            worst = math.max(worst, turn / ((lu + lv) / 2))
        end
        local away = math.max(math.abs(before.xs[i]), math.abs(before.ys[i]))
        if away > 45 and (line.xs[i] ~= before.xs[i] or line.ys[i] ~= before.ys[i]) then far_moved = true end
    end
    check(worst <= rails.MAX_CURVATURE * 1.1, string.format("a corner rounded to a bend rails can follow (radius %.1f, rails %.1f)", 1 / worst, 1 / rails.MAX_CURVATURE))
    check(not far_moved, "the line away from the corner untouched")
    local calm = { xs = {}, ys = {}, tx = {}, ty = {}, n = 0 }
    for k = 0, 90 do
        local a = k / 90 * math.pi / 2
        calm.n = calm.n + 1
        calm.xs[calm.n], calm.ys[calm.n], calm.tx[calm.n], calm.ty[calm.n] = 40 * math.cos(a), 40 * math.sin(a), -math.sin(a), math.cos(a)
    end
    local copy = {}
    for i = 1, calm.n do copy[i] = calm.xs[i] end
    rails.round_line(calm)
    local same = true
    for i = 1, calm.n do if calm.xs[i] ~= copy[i] then same = false end end
    check(same, "a bend rails can follow (radius 40) left as it is")
end

-- No signal at either end of a ramp: the game doesn't let a player place one
-- there (example-bps/signal-wrong-side.txt: one at a ramp's foot, given as
-- elevated, hung in the air beyond the ramp; on the ground it can't be placed
-- either). The rest of the signals on elevated track are elevated.
do
    local pts = { { x = -248.53, y = -698.52 }, { x = -225.98, y = -764.84 }, { x = -193.04, y = -793.18 }, { x = -149.35, y = -808.25 },
        { x = -94.42, y = -811.95 } }
    local function railway(spacing)
        return helpers.plan(pts, {
            [-2] = rail_layer({ idx = -2, elevated = true, ramps = true, direction_of_travel = -1, signal_spacing = spacing, smoothing = 2 }),
            [-1] = { idx = -1, type = "roboport", name = "roboport", quality = "normal", size = 4, offset = 0, priority = 20, spacing = 33 },
            [0] = { idx = 0, type = "electric-pole", name = "pole", quality = "normal", size = 2, offset = 0, priority = 10, spacing = 31, wire_distance = 30 },
            [1] = rail_layer({ idx = 1, elevated = true, ramps = true, signal_spacing = spacing, smoothing = 2 }),
        })
    end
    local worst_wrong, worst_at_ramp, ramp_ends, signals = 0, 0, 0, 0
    for spacing = 1, 6 do
        local p = railway(spacing)
        local ends = {}
        for _, e in ipairs(p.entities) do
            if e.name == "rail-ramp" then
                ends[#ends + 1] = e.track.from
                ends[#ends + 1] = e.track.to
            end
        end
        ramp_ends = math.max(ramp_ends, #ends)
        for _, e in ipairs(p.entities) do
            if e.name == "rail-signal" then
                signals = signals + 1
                if e.rail_layer ~= "elevated" then worst_wrong = worst_wrong + 1 end
                for _, j in ipairs(ends) do
                    if math.abs(e.position.x - j.x) <= 2 and math.abs(e.position.y - j.y) <= 2 then worst_at_ramp = worst_at_ramp + 1 end
                end
            end
        end
    end
    check(ramp_ends == 8 and signals > 60, "elevated railway, signals every 1 to 6 wagons: " .. signals .. " signals")
    check(worst_at_ramp == 0, "no signal at a ramp's end: " .. worst_at_ramp)
    check(worst_wrong == 0, "signals on elevated track elevated: " .. worst_wrong .. " not")
end

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
local range, ramp_range = data.support.range - 1, data.support.ramp_range - 1
--- Elevated pieces no support carries (the game's rule, measured: both ends
--- within reach of one support, or of a ramp's top).
local function uncarried(pieces, supports)
    local tops = {}
    for _, p in ipairs(pieces) do
        if p.name == "rail-ramp" then
            -- (the top is the end shared with an elevated piece)
            for _, q in ipairs(pieces) do
                if q.name ~= "rail-ramp" then
                    for _, e in ipairs({ p.track.from, p.track.to }) do
                        for _, f in ipairs({ q.track.from, q.track.to }) do
                            if e.x == f.x and e.y == f.y then tops[#tops + 1] = e end
                        end
                    end
                end
            end
        end
    end
    local function near(a, b, r) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) <= r end
    local n = 0
    for _, p in ipairs(pieces) do
        if p.name ~= "rail-ramp" then
            local carried = false
            for _, s in ipairs(supports) do
                if near(s, p.track.from, range) and near(s, p.track.to, range) then carried = true end
            end
            for _, t in ipairs(tops) do
                if near(t, p.track.from, ramp_range) and near(t, p.track.to, ramp_range) then carried = true end
            end
            if not carried then n = n + 1 end
        end
    end
    return n
end
check(uncarried(pieces, supports) == 0, "every piece carried by a support or a ramp: " .. uncarried(pieces, supports) .. " not")
-- (about one per 20 tiles: 167 tiles of track, carried 8 tiles past each ramp top, curves' pieces longer)
check(#supports >= 7 and #supports <= 9, "supports: " .. #supports)
-- A straight stretch: supports 20 tiles apart, each carrying 10 tiles either
-- way (no ramps: the first and last carry the ends); a diagonal one, as far
-- apart as its pieces allow
do
    local straight = helpers.plan({ { x = 0.5, y = 0.5 }, { x = 200.5, y = 0.5 } }, { [0] = rail_layer({ elevated = true, ramps = false }) })
    local at, apart = {}, true
    for _, e in ipairs(straight.entities) do if e.name == "rail-support" then at[#at + 1] = e.position end end
    for k = 2, #at do if at[k].x - at[k - 1].x ~= 20 then apart = false end end
    local sp = track(straight)
    check(#at == 10 and apart and uncarried(sp, at) == 0, "straight, 200 tiles: " .. #at .. " supports, 20 apart: " .. tostring(apart))
    local diagonal = helpers.plan({ { x = 0.5, y = 0.5 }, { x = 140.5, y = 140.5 } }, { [0] = rail_layer({ elevated = true, ramps = false }) })
    at = {}
    for _, e in ipairs(diagonal.entities) do if e.name == "rail-support" then at[#at + 1] = e.position end end
    local dp = track(diagonal)
    check(#at <= 12 and uncarried(dp, at) == 0, "diagonal, 198 tiles: " .. #at .. " supports")
end
check(#plan.warnings == 0, "elevated track stays on the curve, ramps included (" .. #plan.warnings .. " warnings)")
-- Supports and ramps are wider than the track (4 tiles across, measured in the
-- game): what they stand on is theirs alone. Ramps and supports of every track,
-- and everything else in the plan, never share a tile with a support.
--- The tiles each entity stands on: supports by their measured footprint, ground
--- track and ramps by theirs, elevated track and its signals none.
local function ground_cells(e)
    if e.name == "rail-support" then return rails.support_cells(e.direction or 0) end
    if e.track then
        if e.name:find("^elevated%-") then return {} end
        local out = {}
        for _, c in ipairs(rails.cells(e.name, e.direction or 0)) do out[#out + 1] = { c[1] + e.position.x, c[2] + e.position.y, rail = true } end
        return out, true
    end
    if e.rail_layer == "elevated" then return {} end
    local w, h = e.w or e.size, e.h or e.size
    local out = {}
    for dx = 0, w - 1 do for dy = 0, h - 1 do out[#out + 1] = { math.floor(e.position.x - w / 2 + dx), math.floor(e.position.y - h / 2 + dy) } end end
    return out, true
end
--- Tiles where a support meets anything else: (count, a description of the first).
local function support_clashes(p)
    local support_at, clashes, first = {}, 0, nil
    for i, e in ipairs(p.entities) do
        if e.name == "rail-support" then
            for _, c in ipairs(rails.support_cells(e.direction or 0)) do
                local key = (e.position.x + c[1]) .. "," .. (e.position.y + c[2])
                if support_at[key] then
                    clashes = clashes + 1
                    first = first or ("two supports at " .. key)
                end
                support_at[key] = i
            end
        end
    end
    for _, e in ipairs(p.entities) do
        if e.name ~= "rail-support" then
            local cells, absolute = ground_cells(e)
            for _, c in ipairs(cells) do
                local key = absolute and (math.floor(c[1]) .. "," .. math.floor(c[2])) or nil
                if key and support_at[key] then
                    clashes = clashes + 1
                    first = first or (e.name .. " on a support at " .. key)
                end
            end
        end
    end
    return clashes, first
end
check(support_clashes(plan) == 0, "a lone elevated track: " .. tostring(select(2, support_clashes(plan))))
check(plan.entities[1].name == "rail-support" and plan.entities[1].arrow == false, "supports first, drawn without an arrow")
-- The band an elevated track takes makes room for them: two tracks side by side
-- and walls on either side
do
    local wall = function(idx) return { idx = idx, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0 } end
    local p = helpers.plan(pts, {
        [-2] = wall(-2),
        [-1] = rail_layer({ idx = -1, elevated = true, ramps = true }),
        [0] = rail_layer({ idx = 0, elevated = true, ramps = true }),
        [1] = wall(1),
    })
    local n, first = support_clashes(p)
    check(n == 0, "two elevated tracks side by side, walls beside: " .. tostring(first))
    local s = 0
    for _, e in ipairs(p.entities) do if e.name == "rail-support" then s = s + 1 end end
    check(s >= 14, "two elevated tracks side by side: supports for both (" .. s .. ")")
    local walls = 0
    for _, e in ipairs(p.entities) do if e.name == "wall" then walls = walls + 1 end end
    local alone = helpers.plan(pts, { [-2] = wall(-2), [1] = wall(1), [-1] = { idx = -1, type = "empty", size = 8, offset = 0 } })
    local walls_alone = 0
    for _, e in ipairs(alone.entities) do if e.name == "wall" then walls_alone = walls_alone + 1 end end
    check(walls >= walls_alone - 4, "the walls beside them unbroken: " .. walls .. " vs " .. walls_alone .. " beside an empty band")
end
-- Track crossing itself: a figure eight, the second stretch's supports kept off
-- the first's (moved to another joint in reach)
do
    local eight = { { x = 0.5, y = 0.5 }, { x = 40.5, y = 0.5 }, { x = 70.5, y = 30.5 }, { x = 70.5, y = 60.5 }, { x = 40.5, y = 60.5 },
        { x = 20.5, y = 30.5 }, { x = 20.5, y = -30.5 }, { x = 60.5, y = -30.5 } }
    local p = helpers.plan(eight, { [0] = rail_layer({ elevated = true, ramps = true }) })
    local n, first = support_clashes(p)
    check(n == 0, "figure eight: no support on another: " .. tostring(first))
end
-- rails.supports on its own: a joint where no support fits is given up on (and
-- reported), the track carried on as if it had one
do
    local line = { xs = {}, ys = {}, tx = {}, ty = {}, n = 0 }
    for x = 0, 100 do line.n = line.n + 1; line.xs[line.n], line.ys[line.n], line.tx[line.n], line.ty[line.n] = x, 0, 1, 0 end
    local fit = rails.new_fit(line, { elevated = true })
    while not fit.done do rails.step(fit, line, false) end
    local all = rails.supports(fit)
    local blocked = all[2]
    local some, missing = rails.supports(fit, function(at) return not (at.x == blocked.x and at.y == blocked.y) end)
    local moved = true
    for _, s in ipairs(some) do if s.x == blocked.x and s.y == blocked.y then moved = false end end
    check(moved and #missing == 0 and #some >= #all, "a blocked joint: the support moves to another (" .. #all .. " -> " .. #some .. ")")
    local none, gone = rails.supports(fit, function() return false end)
    check(#none == 0 and #gone >= #all - 1 and #gone > 0, "no room anywhere: every gap reported (" .. #gone .. ")")
end

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
