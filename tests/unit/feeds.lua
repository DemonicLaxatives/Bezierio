---@diagnostic disable: undefined-global
-- Turret feeds (scripts/build/feeds.lua): fluid connection targets in all facings,
-- inserters picking up from a belt and dropping into their turret, pipe stubs
-- reaching a pipe line.
--   lua5.4 tests/unit/feeds.lua
local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")
local feeds = require("scripts.build.feeds")

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

-- Flamethrower connections (from the game: facing north at (20, 20.5) they want
-- pipe at (18.5, 21.5) and (21.5, 21.5); north-east at (30.5, 20.5): (28.5, 20.5)
-- and (30.5, 22.5), as in the reference blueprint).
local PORTS = { { x = -0.5, y = 1, direction = 12 }, { x = 0.5, y = 1, direction = 4 } }
local t = feeds.fluid_targets({ position = { x = 20, y = 20.5 }, size = 3, direction = 0 }, PORTS)
check(t[1].x == 18 and t[1].y == 21 and t[2].x == 21 and t[2].y == 21, "facing north: as in the game")
t = feeds.fluid_targets({ position = { x = 30.5, y = 20.5 }, size = 3, direction = 2 }, PORTS)
check(t[1].x == 28 and t[1].y == 20 and t[2].x == 30 and t[2].y == 22, "facing north-east: as in the game")
-- Every facing: targets just outside the footprint, at its back, beside a footprint cell
for d = 0, 14, 2 do
    local straight = d % 4 == 0
    local pos = straight and ((d == 0 or d == 8) and { x = 0, y = 0.5 } or { x = 0.5, y = 0 }) or { x = 0.5, y = 0.5 }
    local cells = {}
    if straight then
        local w, h = (d == 4 or d == 12) and 3 or 2, (d == 4 or d == 12) and 2 or 3
        for x = math.floor(pos.x - w / 2 + 0.5), math.floor(pos.x - w / 2 + 0.5) + w - 1 do
            for y = math.floor(pos.y - h / 2 + 0.5), math.floor(pos.y - h / 2 + 0.5) + h - 1 do cells[x .. "," .. y] = true end
        end
    else
        for x = -1, 1 do for y = -1, 1 do cells[x .. "," .. y] = true end end
    end
    local targets = feeds.fluid_targets({ position = pos, size = 3, direction = d }, PORTS)
    local ok = #targets == 2
    local a = d / 16 * 2 * math.pi
    local facing = { x = math.sin(a), y = -math.cos(a) }
    for _, c in ipairs(targets) do
        local beside = cells[(c.x + 1) .. "," .. c.y] or cells[(c.x - 1) .. "," .. c.y] or cells[c.x .. "," .. (c.y + 1)] or cells[c.x .. "," .. (c.y - 1)]
        local behind = (c.x + 0.5 - pos.x) * facing.x + (c.y + 0.5 - pos.y) * facing.y <= 0.01
        if cells[c.x .. "," .. c.y] or not beside or not behind then ok = false end
    end
    check(ok, "facing " .. d .. ": targets outside, beside the turret, at its back")
end

-- Inserters: the turret sits one cell off a belt line; each gets an inserter whose
-- drop lands in it and pickup on the belt.
local wall0 = { idx = 0, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0 }
local function layers(inserter_reach)
    return {
        [0] = wall0,
        [1] = { idx = 1, type = "belt", name = "belt", quality = "normal", size = 1, offset = 0, lines = 1, line_gap = 0, flow = "forward" },
        [2] = { idx = 2, type = "turret", name = "gun", quality = "normal", size = 2, offset = inserter_reach, spacing = 4, ammo_inventory = "turret_ammo",
            inserter = "ins", inserter_name = "ins", inserter_pickup = { x = 0, y = -inserter_reach }, inserter_drop = { x = 0, y = 1.2 }, inserter_power = true },
        [-1] = { idx = -1, type = "pipe", name = "pipe", quality = "normal", size = 1, offset = 0, lines = 1, line_gap = 1 },
        [-2] = { idx = -2, type = "turret", name = "flamer", quality = "normal", size = 3, offset = 1, spacing = 6, turn_limited = true, directions = 8,
            tile_w = 2, tile_h = 3, facing = "outward", pipe_feed = true, fluid_ports = PORTS },
    }
end
local STEP = { [0] = { 0, -1 }, [4] = { 1, 0 }, [8] = { 0, 1 }, [12] = { -1, 0 } }
local r = helpers.rng(1234)
local curves = { { { x = 0.5, y = 0.5 }, { x = 60.5, y = 0.5 } }, { { x = 0.5, y = 0.5 }, { x = 50.5, y = 15.5 }, { x = 80.5, y = 60.5 } } }
for _ = 1, 6 do
    local pts, x, y, ang = {}, 0, 0, r.range(0, 6.28)
    for i = 1, 3 do pts[i] = { x = x, y = y }; ang = ang + r.range(-0.8, 0.8); x, y = x + 40 * math.cos(ang), y + 40 * math.sin(ang) end
    curves[#curves + 1] = pts
end
local fed_total, turrets_total = 0, 0
for ci, pts in ipairs(curves) do
    for _, reach in ipairs({ 1, 2 }) do
        local plan = helpers.plan(pts, layers(reach))
        local at, belts, guns, inserters = {}, {}, {}, {}
        for _, e in ipairs(plan.entities) do
            local half = e.size / 2
            for dx = 0, e.size - 1 do for dy = 0, e.size - 1 do
                at[math.floor(e.position.x - half + 0.5 + dx) .. "," .. math.floor(e.position.y - half + 0.5 + dy)] = e
            end end
            if e.name == "belt" then belts[math.floor(e.position.x) .. "," .. math.floor(e.position.y)] = true end
            if e.name == "gun" then guns[#guns + 1] = e end
            if e.name == "ins" then inserters[#inserters + 1] = e end
        end
        local good = 0
        for _, ins in ipairs(inserters) do
            local s = STEP[ins.direction]
            local cx, cy = math.floor(ins.position.x), math.floor(ins.position.y)
            local pickup = (cx + s[1] * reach) .. "," .. (cy + s[2] * reach)
            local drop = at[(cx - s[1]) .. "," .. (cy - s[2])]
            if belts[pickup] and drop and drop.name == "gun" then good = good + 1 end
        end
        check(good == #inserters, string.format("curve %d reach %d: every inserter picks from a belt and drops into a turret (%d/%d)", ci, reach, good, #inserters))
        fed_total = fed_total + #inserters
        turrets_total = turrets_total + #guns
        check(#inserters + plan.unfed >= #guns, "curve " .. ci .. ": every turret fed or counted")
    end
end
check(fed_total >= turrets_total * 0.9, string.format("most turrets fed: %d of %d", fed_total, turrets_total))

-- Pipe stubs: every flamethrower's connection reaches the pipe line
local plan = helpers.plan(curves[2], layers(1))
local pipes = {}
for _, e in ipairs(plan.entities) do if e.name == "pipe" then pipes[math.floor(e.position.x) .. "," .. math.floor(e.position.y)] = true end end
local connected, flamers = 0, 0
for _, e in ipairs(plan.entities) do
    if e.name == "flamer" then
        flamers = flamers + 1
        for _, c in ipairs(feeds.fluid_targets(e, PORTS)) do
            if pipes[c.x .. "," .. c.y] then connected = connected + 1 break end
        end
    end
end
check(flamers > 5 and connected == flamers, "every flamethrower has pipe at a connection: " .. connected .. "/" .. flamers)
-- and the pipes are one network
local seen, stack, count = {}, {}, 0
for k in pairs(pipes) do stack[1] = k; seen[k] = true; break end
while #stack > 0 do
    local k = table.remove(stack)
    count = count + 1
    local x, y = k:match("(-?%d+),(-?%d+)")
    x, y = tonumber(x), tonumber(y)
    for _, s in pairs(STEP) do
        local n = (x + s[1]) .. "," .. (y + s[2])
        if pipes[n] and not seen[n] then seen[n] = true; stack[#stack + 1] = n end
    end
end
local total = 0
for _ in pairs(pipes) do total = total + 1 end
check(count == total, "pipe line and stubs are one network: " .. count .. "/" .. total)

-- With pipes-to-ground in the line: every stub joins a plain pipe of the line
-- (a pipe-to-ground connects only along its own direction, not to a stub beside it)
local with_ug = layers(1)
with_ug[-1] = { idx = -1, type = "pipe", name = "pipe", quality = "normal", size = 1, offset = 0, lines = 1, line_gap = 1,
    undergrounds = true, underground_name = "ptg", underground_distance = 10 }
for ci, pts in ipairs(curves) do
    local ug_plan = helpers.plan(pts, with_ug)
    local line, stubs = {}, {}
    for _, e in ipairs(ug_plan.entities) do
        local key = math.floor(e.position.x) .. "," .. math.floor(e.position.y)
        if e.name == "pipe" and e.layer == -1 then line[key] = true end
        if e.name == "pipe" and e.layer == -2 then stubs[key] = true end
    end
    local seen_stub, groups, cut = {}, 0, 0
    for start in pairs(stubs) do
        if not seen_stub[start] then
            groups = groups + 1
            local todo, joined = { start }, false
            seen_stub[start] = true
            while #todo > 0 do
                local x, y = table.remove(todo):match("(-?%d+),(-?%d+)")
                x, y = tonumber(x), tonumber(y)
                for _, s in pairs(STEP) do
                    local n = (x + s[1]) .. "," .. (y + s[2])
                    if line[n] then joined = true end
                    if stubs[n] and not seen_stub[n] then seen_stub[n] = true; todo[#todo + 1] = n end
                end
            end
            if not joined then cut = cut + 1 end
        end
    end
    check(cut == 0, "curve " .. ci .. ": every stub joins a plain pipe (" .. cut .. " of " .. groups .. " don't)")
end

-- Smart poles power inserters by the inserter's own footprint, not that of the
-- (non-square) turret they feed: every one out of reach is counted.
do
    local smart_r = helpers.rng(5)
    local uncovered, inserters, reported = 0, 0, 0
    for _ = 1, 30 do
        local feed_layers = {
            [0] = wall0,
            [-1] = { idx = -1, type = "turret", name = "long-gun", quality = "normal", size = 4, tile_w = 2, tile_h = 4, turn_limited = true, directions = 4,
                facing = "outward", offset = 0, spacing = 5, ammo_inventory = "turret_ammo", inserter = "ins", inserter_name = "ins",
                inserter_pickup = { x = 0, y = -1 }, inserter_drop = { x = 0, y = 1.2 }, inserter_power = true },
            [-2] = { idx = -2, type = "belt", name = "belt", quality = "normal", size = 1, offset = 0, lines = 1, line_gap = 0, flow = "forward" },
            [-3] = { idx = -3, type = "electric-pole", name = "pole", quality = "normal", size = 1, offset = 0, spacing = 6, wire_distance = 9, reach = 2.5, smart = true },
        }
        local smart_plan = helpers.plan(helpers.random_points(smart_r), feed_layers)
        local poles = {}
        for _, e in ipairs(smart_plan.entities) do if e.layer == -3 then poles[#poles + 1] = e.position end end
        for _, e in ipairs(smart_plan.entities) do
            if e.name == "ins" then
                inserters = inserters + 1
                local powered = false
                for _, p in ipairs(poles) do
                    -- (a 1x1 footprint less the 0.3 margin: 0.2 each side)
                    if math.abs(e.position.x - p.x) < 2.7 and math.abs(e.position.y - p.y) < 2.7 then powered = true break end
                end
                if not powered then uncovered = uncovered + 1 end
            end
        end
        reported = reported + smart_plan.unpowered
    end
    check(inserters > 100 and uncovered == reported,
        string.format("inserters of non-square turrets: %d of %d out of reach, %d reported", uncovered, inserters, reported))
end

-- A turret that doesn't fill its square (a 3x5 railgun, facing 8 ways): its
-- inserters drop on a tile its turned collision box covers, never beside it.
do
    local RAIL_BOX = { left = -1.40625, top = -1.8984375, right = 1.40625, bottom = 2.09765625 }
    -- (the game's box; at (0.5, 0.5) facing north it covers tiles x -1..1, y -2..2)
    local north = { position = { x = 0.5, y = 0.5 }, direction = 0 }
    check(feeds.box_over_tile(north, RAIL_BOX, -1, -2) and feeds.box_over_tile(north, RAIL_BOX, 1, 2)
        and not feeds.box_over_tile(north, RAIL_BOX, -2, 0) and not feeds.box_over_tile(north, RAIL_BOX, 2, 0),
        "railgun facing north covers 3x5 tiles")
    local east = { position = { x = 0.5, y = 0.5 }, direction = 4 }
    check(feeds.box_over_tile(east, RAIL_BOX, -2, -1) and not feeds.box_over_tile(east, RAIL_BOX, 0, -2),
        "railgun facing east covers 5x3 tiles")
    local ne = { position = { x = 0.5, y = 0.5 }, direction = 2 }
    check(feeds.box_over_tile(ne, RAIL_BOX, 0, 0) and not feeds.box_over_tile(ne, RAIL_BOX, -2, -2) and not feeds.box_over_tile(ne, RAIL_BOX, 2, 2),
        "railgun facing north-east leaves the square's other corners")
    local rail_layers = {
        [-2] = { idx = -2, type = "belt", name = "belt", quality = "normal", size = 1, offset = 0, lines = 1, line_gap = 0, flow = "forward" },
        [-1] = { idx = -1, type = "electric-pole", name = "pole", quality = "normal", size = 1, offset = 0, spacing = 8, wire_distance = 9, reach = 3.5, smart = true },
        [0] = { idx = 0, type = "turret", name = "rg", quality = "normal", size = 5, tile_w = 3, tile_h = 5, turn_limited = true, directions = 8,
            facing = "outward", offset = 0, spacing = 5, ammo_inventory = "turret_ammo", inserter = "ins", inserter_name = "ins",
            inserter_pickup = { x = 0, y = -1 }, inserter_drop = { x = 0, y = 1.2 }, inserter_power = true, turret_box = RAIL_BOX },
    }
    local rail_r = helpers.rng(31)
    local rail_curves = { { { x = 0.3, y = 0.5 }, { x = 80.5, y = 0.5 } }, { { x = 0.5, y = 0.3 }, { x = 0.5, y = 80.5 } } }
    for _ = 1, 6 do rail_curves[#rail_curves + 1] = helpers.random_points(rail_r) end
    for ci, pts in ipairs(rail_curves) do
        local rail_plan = helpers.plan(pts, rail_layers)
        local guns, ins = {}, {}
        for _, e in ipairs(rail_plan.entities) do
            if e.name == "rg" then guns[#guns + 1] = e end
            if e.name == "ins" then ins[#ins + 1] = e end
        end
        local into = 0
        for _, i in ipairs(ins) do
            local drop = feeds.rotate({ x = 0, y = 1.2 }, i.direction)
            local tx, ty = math.floor(i.position.x + drop.x), math.floor(i.position.y + drop.y)
            for _, g in ipairs(guns) do
                if feeds.box_over_tile(g, RAIL_BOX, tx, ty) then into = into + 1 break end
            end
        end
        check(into == #ins and #ins + rail_plan.unfed == #guns,
            string.format("railgun curve %d: %d of %d inserters drop into a railgun; %d fed + %d unfed of %d", ci, into, #ins, #ins, rail_plan.unfed, #guns))
        if ci <= 2 then check(#guns > 10 and rail_plan.unfed == 0, "railguns along a straight line all fed: " .. #ins .. " of " .. #guns) end
    end
end

print(string.format("%d/%d feed checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
