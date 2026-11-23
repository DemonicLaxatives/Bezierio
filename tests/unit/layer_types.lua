---@diagnostic disable: undefined-global
-- The spaced and scattered layer types: turret facing and footprints, ammo, lamp
-- colours, radar spacing, land mine density and wires.
--   lua5.4 tests/unit/layer_types.lua
local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")
local common = require("scripts.layers.common")
local registry = require("scripts.layers.registry")

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

-- Directions: north 0, east 4, south 8, west 12 (map y points down)
check(common.direction({ x = 0, y = -1 }, 4) == 0 and common.direction({ x = 1, y = 0 }, 4) == 4
    and common.direction({ x = 0, y = 1 }, 4) == 8 and common.direction({ x = -1, y = 0 }, 4) == 12, "4 directions")
check(common.direction({ x = 1, y = -1 }, 8) == 2 and common.direction({ x = -1, y = 1 }, 8) == 10, "8 directions: diagonals")
check(common.direction({ x = 1, y = -0.9 }, 4) == 4 and common.direction({ x = 0.9, y = -1 }, 4) == 0, "nearest of 4")

local wall0 = { idx = 0, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0 }
local line = { { x = 0.5, y = 0.5 }, { x = 60.5, y = 0.5 } } -- runs east: layer 1's side is south

local function turret(idx, extra)
    local t = { idx = idx, type = "turret", name = "flamer", quality = "normal", size = 3, offset = 0, spacing = 6,
        turn_limited = true, directions = 4, tile_w = 2, tile_h = 3, facing = "outward", ammo_inventory = nil }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

local function of_layer(plan, idx)
    local out = {}
    for _, e in ipairs(plan.entities) do if e.layer == idx then table.insert(out, e) end end
    return out
end

local plan = helpers.plan(line, { [0] = wall0, [1] = turret(1), [-1] = turret(-1), [2] = turret(2, { facing = "inward" }) })
local south, north = of_layer(plan, 1), of_layer(plan, -1)
check(#south > 5 and #north > 5, "turrets on both sides")
local ok = true
for _, e in ipairs(south) do if e.direction ~= 8 then ok = false end end
check(ok, "layer 1 (south side) faces south")
ok = true
for _, e in ipairs(north) do if e.direction ~= 0 then ok = false end end
check(ok, "layer -1 faces north")
ok = true
for _, e in ipairs(of_layer(plan, 2)) do if e.direction ~= 0 then ok = false end end
check(ok, "inward faces the curve")
-- 2x3 facing south: 2 wide (whole-number x centre), 3 tall (half y centre)
ok = true
for _, e in ipairs(south) do
    if e.position.x ~= math.floor(e.position.x) or e.position.y == math.floor(e.position.y) then ok = false end
end
check(ok, "2x3 turret on its own grid")
-- facing east on a north-south line: 3 wide, 2 tall
local vplan = helpers.plan({ { x = 0.5, y = 0.5 }, { x = 0.5, y = 60.5 } }, { [0] = wall0, [-1] = turret(-1) })
ok = #of_layer(vplan, -1) > 5
for _, e in ipairs(of_layer(vplan, -1)) do
    if e.direction ~= 4 or e.position.x == math.floor(e.position.x) or e.position.y ~= math.floor(e.position.y) then ok = false end
end
check(ok, "rotated: 3 wide, 2 tall, facing east")
-- 8 directions: on a diagonal line, a 2x3 turret faces diagonally and stays on
-- the 3x3 square's grid (its diagonal footprint is that square minus corners)
local dplan = helpers.plan({ { x = 0.5, y = 0.5 }, { x = 60.5, y = 60.5 } }, { [0] = wall0, [1] = turret(1, { directions = 8 }) })
ok = #of_layer(dplan, 1) > 5
for _, e in ipairs(of_layer(dplan, 1)) do
    -- running south-east, layer 1's side is south-west
    if e.direction ~= 10 or e.position.x == math.floor(e.position.x) or e.position.y == math.floor(e.position.y) then ok = false end
end
check(ok, "diagonal: facing south-west, centred on the 3x3 grid")

-- turrets that turn all the way have no direction
local free = helpers.plan(line, { [0] = wall0, [1] = turret(1, { turn_limited = false, tile_w = 3, tile_h = 3 }) })
check(of_layer(free, 1)[1] and of_layer(free, 1)[1].direction == nil, "no direction for full-turn turrets")
-- the planner's own cells never overlap, even with the footprint shifted
local cells, overlap = {}, false
for _, e in ipairs(plan.entities) do
    local w, h = e.size, e.size
    if e.layer ~= 0 then w, h = (e.direction == 4 or e.direction == 12) and 3 or 2, (e.direction == 4 or e.direction == 12) and 2 or 3 end
    local x0, y0 = math.floor(e.position.x - w / 2 + 0.5), math.floor(e.position.y - h / 2 + 0.5)
    for dx = 0, w - 1 do for dy = 0, h - 1 do
        local k = (x0 + dx) .. "," .. (y0 + dy)
        if cells[k] then overlap = true end
        cells[k] = true
    end end
end
check(not overlap, "real footprints don't overlap")

-- Ammo
local gun = { idx = 1, type = "turret", name = "gun", quality = "normal", size = 2, offset = 0, spacing = 4,
    ammo_inventory = "turret_ammo", ammo = "magazine", ammo_count = 25 }
local ammo_plan = helpers.plan(line, { [0] = wall0, [1] = gun })
local first = of_layer(ammo_plan, 1)[1]
check(first and first.ammo and first.ammo.name == "magazine" and first.ammo.count == 25 and first.ammo.inventory == "turret_ammo", "ammo requested")

-- Lamps
local function lamps(color, length)
    return helpers.plan(line, { [0] = wall0, [1] = { idx = 1, type = "lamp", name = "lamp", quality = "normal", size = 1, offset = 0, spacing = 4, color = color, rainbow_length = length } })
end
check(of_layer(lamps("default"), 1)[1].color == nil, "the lamp's own colour")
local red = of_layer(lamps("red"), 1)[1].color
check(red and red.r == 1 and red.g < 0.2, "one colour")
local rainbow = of_layer(lamps("rainbow", 24), 1)
local distinct = {}
for _, e in ipairs(rainbow) do distinct[string.format("%.2f,%.2f,%.2f", e.color.r, e.color.g, e.color.b)] = true end
local n = 0
for _ in pairs(distinct) do n = n + 1 end
check(n >= 6, "rainbow: colours change along the curve (" .. n .. ")")
check(rainbow[1].color.r == 1 and rainbow[1].color.g == 0 and rainbow[7].color.r == 1 and rainbow[7].color.g == 0, "rainbow repeats every 24 tiles (6 lamps)")

-- Pump spacing stops at the pipeline extent, less the pump
local pipe_def = registry.types["pipe"]
local spacing_field
for _, f in ipairs(pipe_def.fields) do if f.name == "pump_spacing" then spacing_field = f end end
check(spacing_field.max({ pipeline_extent = 320 }) == 318 and spacing_field.max({ pipeline_extent = 100 }) == 98
    and spacing_field.default({ pipeline_extent = 100 }) == 98, "pump spacing from the pipeline extent")

-- Radar spacing follows the reveal range
local radar_def = registry.types["radar"]
local radar = { size = 3, reveal_chunks = 3 }
check(radar_def.fields[1].max(radar) == 224 and radar_def.fields[1].default(radar) == 192, "radar spacing from its range")

-- Land mines: about `density` percent of the band, the same cells every time,
-- wired into trees within reach
local mine = { idx = 1, type = "land-mine", name = "mine", quality = "normal", size = 1, offset = 0, radius = 6, density = 15,
    red_wire = true, circuit_distance = 9 }
local long = { { x = 0.5, y = 0.5 }, { x = 300.5, y = 0.5 } }
local mines = helpers.plan(long, { [0] = wall0, [1] = mine })
local placed = of_layer(mines, 1)
local fraction = #placed / (6 * 300)
check(fraction > 0.12 and fraction < 0.18, string.format("density about 15%% (%.3f)", fraction))
check(helpers.canonical(helpers.plan(long, { [0] = wall0, [1] = mine })) == helpers.canonical(mines), "the same cells every time")
local too_far = 0
for _, link in ipairs(mines.links) do
    local a, b = mines.entities[link.a].position, mines.entities[link.b].position
    if math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) > 9 then too_far = too_far + 1 end
end
check(too_far == 0 and #mines.links >= #placed - 5, "wires within reach, almost one tree (" .. #mines.links .. " links, " .. #placed .. " mines)")
mine.red_wire = false
check(#helpers.plan(long, { [0] = wall0, [1] = mine }).links == 0, "no wires unless asked")
-- grid pattern: every 4 tiles in both directions, wider band
local grid = { idx = 1, type = "land-mine", name = "mine", quality = "normal", size = 1, offset = 0, radius = 20, pattern = "grid", mine_spacing = 4 }
local gplaced = of_layer(helpers.plan(long, { [0] = wall0, [1] = grid }), 1)
local on_grid = #gplaced > 0
for _, e in ipairs(gplaced) do
    if math.floor(e.position.x) % 4 ~= 0 or math.floor(e.position.y) % 4 ~= 0 then on_grid = false end
end
check(on_grid and #gplaced >= 20 * 300 / 16 * 0.9, "grid: every 4 tiles over a 20-wide band (" .. #gplaced .. ")")
-- density 100 fills the band
mine.density = 100
check(#of_layer(helpers.plan(long, { [0] = wall0, [1] = mine }), 1) >= 6 * 299, "density 100 fills the band")

-- Side wall layers join side by side, also off to the side of a bend (where a
-- band's cells used to meet only at a corner): a circle, two wall layers each side.
local function wall(idx, offset) return { idx = idx, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = offset } end
local circle = helpers.shape_curve("circle", { { x = 0.5, y = 0.5 }, { x = 0.5, y = -29.5 } })
local walled = helpers.plan_curve(circle, { [0] = wall(0, 0), [1] = wall(1, 2), [2] = wall(2, 2), [-1] = wall(-1, 2), [-2] = wall(-2, 2) })
local corner_only = 0
local by_layer = {}
for _, e in ipairs(walled.entities) do
    by_layer[e.layer] = by_layer[e.layer] or {}
    by_layer[e.layer][math.floor(e.position.x) .. "," .. math.floor(e.position.y)] = { math.floor(e.position.x), math.floor(e.position.y) }
end
for _, cells in pairs(by_layer) do
    for _, c in pairs(cells) do
        for _, d in ipairs({ { 1, 1 }, { 1, -1 } }) do
            if cells[(c[1] + d[1]) .. "," .. (c[2] + d[2])] and not cells[(c[1] + d[1]) .. "," .. c[2]] and not cells[c[1] .. "," .. (c[2] + d[2])] then
                corner_only = corner_only + 1
            end
        end
    end
end
check(corner_only == 0, "side wall layers around a circle join side by side: " .. corner_only .. " corner-only joins")

-- A layer that isn't placed builds nothing, and the layers outside it stay put.
local function walls(place)
    local l1 = wall(1, 1); l1.place = place
    return { [0] = wall(0, 0), [1] = l1, [2] = wall(2, 1) }
end
local placed, unplaced = helpers.plan(line, walls(nil)), helpers.plan(line, walls(false))
local function cells(plan, idx)
    local out = {}
    for _, e in ipairs(of_layer(plan, idx)) do out[#out + 1] = e.position.x .. "," .. e.position.y end
    table.sort(out)
    return table.concat(out, " ")
end
check(#of_layer(placed, 1) > 50 and #of_layer(unplaced, 1) == 0, "not placed: nothing on layer 1")
check(cells(unplaced, 2) == cells(placed, 2) and cells(unplaced, 0) == cells(placed, 0), "layers 0 and 2 where they were")
check((unplaced.counts[1] or 0) == 0, "and nothing counted for it")

-- Turrets carry their targeting priorities (not artillery: can_prioritise unset)
local prio = turret(1, { can_prioritise = true, priority_targets = { "small-biter", "big-worm-turret" }, ignore_unprioritised = true })
local pplan = helpers.plan(line, { [0] = wall0, [1] = prio })
local all = #of_layer(pplan, 1) > 3
for _, e in ipairs(of_layer(pplan, 1)) do
    if not (e.priority_targets and e.priority_targets[2] == "big-worm-turret" and e.ignore_unprioritised) then all = false end
end
check(all, "turrets carry the priority list")
local art = helpers.plan(line, { [0] = wall0, [1] = turret(1, { priority_targets = { "small-biter" } }) })
check(of_layer(art, 1)[1] and of_layer(art, 1)[1].priority_targets == nil, "no list where the turret can't have one")

print(string.format("%d/%d layer type checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
