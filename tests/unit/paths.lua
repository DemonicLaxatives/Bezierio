---@diagnostic disable: undefined-global
-- Path layers (belts, pipes): continuous lines, belts fed only from behind,
-- undergrounds paired within reach, pipe lines connected and apart, pumps.
--   lua5.4 tests/unit/paths.lua [cases]
local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

local STEP = { [0] = { 0, -1 }, [4] = { 1, 0 }, [8] = { 0, 1 }, [12] = { -1, 0 } }
local function cell(e) return math.floor(e.position.x) .. "," .. math.floor(e.position.y) end
local function ahead(e, n)
    local d = STEP[e.direction]
    return (math.floor(e.position.x) + d[1] * n) .. "," .. (math.floor(e.position.y) + d[2] * n)
end

local wall0 = { idx = 0, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0 }
local function belts(lines, gap, ug) return { idx = 1, type = "belt", name = "belt", quality = "normal", size = 1, offset = 0, lines = lines, line_gap = gap, flow = "forward", undergrounds = ug, underground_name = "ug", underground_distance = 5 } end
local function pipes(lines, gap, ug, pumps) return { idx = -1, type = "pipe", name = "pipe", quality = "normal", size = 1, offset = 0, lines = lines, line_gap = gap, undergrounds = ug, underground_name = "ptg", underground_item = "ptg", underground_distance = 10, pumps = pumps, pump_name = "pump", pump_item = "pump", pump_spacing = 30 } end

--- Belt rules: each belt or entrance is fed by at most one belt (no side-loading
--- surprises); each points at the next part of its line or ends it; entrances have
--- their exit within reach, nothing of the line between.
local function check_belts(plan, label, lines)
    local at, feeders, ends = {}, {}, 0
    for _, e in ipairs(plan.entities) do if e.layer == 1 then at[cell(e)] = e end end
    for _, e in ipairs(plan.entities) do
        if e.layer == 1 and (e.name == "belt" or e.belt_type == "output") then
            local target = at[ahead(e, 1)]
            if target and (target.name == "belt" or target.belt_type == "input") then
                feeders[ahead(e, 1)] = (feeders[ahead(e, 1)] or 0) + 1
            else
                ends = ends + 1
            end
        elseif e.layer == 1 and e.belt_type == "input" then
            local found = false
            for n = 1, 5 do
                local other = at[ahead(e, n)]
                if other and other.belt_type == "output" and other.direction == e.direction then found = n >= 2 break end
                if other then break end
            end
            check(found, label .. ": underground entrance at " .. cell(e) .. " has its exit 2..5 ahead with nothing between")
        end
    end
    local many = 0
    for _, n in pairs(feeders) do if n > 1 then many = many + 1 end end
    check(many == 0, label .. ": no belt fed by two belts (" .. many .. ")")
    return ends
end

--- Pipe rules: lines never touch each other; each line is one network.
local function check_pipes(plan, label, lines)
    local line_of, at = {}, {}
    for _, e in ipairs(plan.entities) do
        if e.layer == -1 then
            if e.name == "pump" then
                -- a pump covers two cells
                local d = STEP[e.direction]
                local a = math.floor(e.position.x - d[1] * 0.5) .. "," .. math.floor(e.position.y - d[2] * 0.5)
                local b = math.floor(e.position.x + d[1] * 0.5) .. "," .. math.floor(e.position.y + d[2] * 0.5)
                at[a], at[b] = e, e
            else
                at[cell(e)] = e
            end
        end
    end
    -- Networks: pipes connect to every neighbour; pipe-to-ground only to its
    -- facing side and its partner; pumps along their direction.
    local function connections(key, e)
        local x, y = key:match("(-?%d+),(-?%d+)")
        x, y = tonumber(x), tonumber(y)
        local out = {}
        if e.name == "pipe" then
            for _, d in pairs(STEP) do out[#out + 1] = (x + d[1]) .. "," .. (y + d[2]) end
        elseif e.name == "ptg" then
            local d = STEP[e.direction]
            out[#out + 1] = (x + d[1]) .. "," .. (y + d[2])
            for n = 1, 11 do
                local k = (x - d[1] * n) .. "," .. (y - d[2] * n)
                if at[k] and at[k].name == "ptg" then out[#out + 1] = k break end
            end
        else -- pump: both ends along its direction
            local d = STEP[e.direction]
            for n = -2, 2 do out[#out + 1] = (x + d[1] * n) .. "," .. (y + d[2] * n) end
        end
        return out
    end
    local seen, networks = {}, 0
    for key, e in pairs(at) do
        if not seen[key] then
            networks = networks + 1
            local stack = { key }
            seen[key] = true
            while #stack > 0 do
                local k = table.remove(stack)
                for _, n in ipairs(connections(k, at[k])) do
                    if at[n] and not seen[n] then seen[n] = true; stack[#stack + 1] = n end
                end
            end
        end
    end
    return networks
end

-- A gentle curve: one segment per line, everything continuous
local gentle = { { x = 0.5, y = 0.5 }, { x = 60.5, y = 10.5 }, { x = 90.5, y = 60.5 } }
for _, ug in ipairs({ false, true }) do
    local plan = helpers.plan(gentle, { [0] = wall0, [1] = belts(3, 0, ug), [-1] = pipes(2, 1, ug, true) })
    local label = ug and "undergrounds" or "plain"
    local ends = check_belts(plan, label, 3)
    check(ends == 3, label .. ": three belt lines, each one continuous (" .. ends .. " ends)")
    local nets = check_pipes(plan, label, 2)
    check(nets == 2, label .. ": two separate pipe networks (" .. nets .. ")")
    local n = {}
    for _, e in ipairs(plan.entities) do n[e.name] = (n[e.name] or 0) + 1 end
    if ug then check((n.ug or 0) > 10 and (n.ptg or 0) > 10, label .. ": undergrounds used") end
    check((n.pump or 0) >= 4, label .. ": pumps every 30 cells (" .. (n.pump or 0) .. ")")
    check(plan.extra_counts[-1] and plan.extra_counts[-1].pump == n.pump, label .. ": pumps counted for the totals")
end

-- A longer pump (a modded 1x3): on a straight run, its cells free of anything else,
-- with pipe of its line right behind and ahead of it
do
    local long = pipes(1, 1, false, true)
    long.pump_name, long.pump_item, long.pump_length = "long-pump", "long-pump", 3
    -- (mostly straight: on a staircase a 1x3 pump needs four moves the same way)
    local plan = helpers.plan({ { x = 0.5, y = 0.5 }, { x = 150.5, y = 12.5 } }, { [0] = wall0, [-1] = long })
    local taken, pumps, overlaps = {}, {}, 0
    for _, e in ipairs(plan.entities) do
        local w, h = e.w or e.size, e.h or e.size
        for dx = 0, w - 1 do for dy = 0, h - 1 do
            local k = math.floor(e.position.x - w / 2 + 0.5 + dx) .. "," .. math.floor(e.position.y - h / 2 + 0.5 + dy)
            if taken[k] then overlaps = overlaps + 1 end
            taken[k] = e
        end end
        if e.name == "long-pump" then pumps[#pumps + 1] = e end
    end
    local in_line = 0
    for _, p in ipairs(pumps) do
        local d = STEP[p.direction]
        local along = (p.w or 1) > 1 and p.w or p.h
        local behind = taken[math.floor(p.position.x - d[1] * 2) .. "," .. math.floor(p.position.y - d[2] * 2)]
        local ahead = taken[math.floor(p.position.x + d[1] * 2) .. "," .. math.floor(p.position.y + d[2] * 2)]
        if along == 3 and p.size == 3 and behind and behind.name == "pipe" and ahead and ahead.name == "pipe" then in_line = in_line + 1 end
    end
    check(#pumps >= 4 and in_line == #pumps and overlaps == 0,
        string.format("1x3 pumps: %d, %d with pipe in line on both sides, %d overlapping cells", #pumps, in_line, overlaps))
    check(plan.extra_counts[-1].pump == nil and plan.extra_counts[-1]["long-pump"] == #pumps, "the chosen pump counted for the totals")
end

-- Backward flow reverses the belts
local back = belts(1, 0, false)
back.flow = "backward"
local fwd_plan = helpers.plan({ { x = 0.5, y = 0.5 }, { x = 40.5, y = 0.5 } }, { [0] = wall0, [1] = belts(1, 0, false) })
local back_plan = helpers.plan({ { x = 0.5, y = 0.5 }, { x = 40.5, y = 0.5 } }, { [0] = wall0, [1] = back })
local fd, bd
for _, e in ipairs(fwd_plan.entities) do if e.layer == 1 then fd = e.direction end end
for _, e in ipairs(back_plan.entities) do if e.layer == 1 then bd = e.direction end end
check(fd == 4 and bd == 12, "forward east, backward west")

-- Closed loop: belts go round with no end
local loop = helpers.plan({ { x = 0, y = 0 }, { x = 40, y = -30 }, { x = 70, y = 10 }, { x = 30, y = 40 } }, { [0] = wall0, [1] = belts(1, 0, false) }, nil, true)
check(check_belts(loop, "loop") == 0, "a closed loop of belts has no end")

-- Reported: a closed loop with 8 lines at layer 0 lost its inner lines (line ends
-- on a loop looked hemmed in, and trimming them ate the line).
local reported = helpers.plan({ { x = -444.4, y = 150.07 }, { x = -366.38, y = 80.9 }, { x = -309.07, y = 160.34 }, { x = -315.53, y = 221.75 } },
    { [0] = { idx = 0, type = "belt", name = "belt", quality = "normal", size = 1, offset = 0, lines = 8, line_gap = 0, flow = "forward" } }, nil, true)
check(#reported.entities >= 4400, "the reported loop keeps its lines: " .. #reported.entities .. " belts")
for _, e in ipairs(reported.entities) do e.layer = 1 end
check_belts(reported, "reported loop", 8)

-- Random curves: the rules hold (lines may split where a curve folds back on itself)
local r = helpers.rng(31337)
local cases = tonumber(arg[1]) or 60
local split = 0
for it = 1, cases do
    local raw = helpers.random_points(r)
    local closed = #raw >= 3 and it % 3 == 0
    local nb, np = r.int(1, 3), r.int(1, 3)
    local plan = helpers.plan(raw, { [0] = wall0, [1] = belts(nb, r.int(0, 1), it % 2 == 0), [-1] = pipes(np, r.int(1, 2), it % 2 == 1, it % 4 == 1) }, nil, closed)
    local ends = check_belts(plan, "random #" .. it, nb)
    local nets = check_pipes(plan, "random #" .. it, np)
    if ends > nb or nets > np then split = split + 1 end
end
print(string.format("(%d of %d random curves split a line somewhere)", split, cases))

-- A corner cell keeps its place along the curve (a line routed again later orders
-- its cells by it; with j = 0 the corner was cut off and the line split there).
do
    local used = {}
    local pieces = require("scripts.build.paths").join_corners({ { x = 0, y = 0, j = 40 }, { x = 1, y = 1, j = 44 } },
        function() return 1 end, function(x, y, j) used[#used + 1] = { x = x, y = y, j = j } end)
    check(#pieces == 1 and #pieces[1] == 3 and used[1] and used[1].j == 40, "corner cell used with its curve sample")
end

print(string.format("%d/%d path checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
