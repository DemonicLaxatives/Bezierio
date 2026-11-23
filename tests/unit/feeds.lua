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

print(string.format("%d/%d feed checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
