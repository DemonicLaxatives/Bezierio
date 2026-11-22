---@diagnostic disable: undefined-global
--- Shared setup for unit tests that run mod code outside Factorio (plain Lua 5.2+).
---
---   local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")
---
--- Only modules that don't touch the game at load time can be loaded this way.
local helpers = {}

helpers.repo = (arg and arg[0] and arg[0]:match("^(.*)/tests/unit/")) or "."
package.path = helpers.repo .. "/?.lua;" .. package.path

local function deepcopy(o)
    if type(o) ~= "table" then return o end
    local r = {}
    for k, v in pairs(o) do r[k] = deepcopy(v) end
    return r
end
helpers.deepcopy = deepcopy

-- Factorio's lualib, as far as mod code uses it.
package.preload["__core__.lualib.util"] = function() return { table = { deepcopy = deepcopy } } end

-- Factorio accepts both "a.b" and "a/b" module paths.
local orig_require = require
require = function(name) return orig_require((name:gsub("/", "."))) end

--- Small deterministic PRNG (LCG), identical on every Lua version, so generated
--- cases don't depend on the interpreter's math.random.
--- @param seed integer
function helpers.rng(seed)
    local state = seed % 2147483647
    if state <= 0 then state = state + 2147483646 end
    local r = {}
    --- @return number in [0, 1)
    function r.float()
        state = (state * 48271) % 2147483647
        return (state - 1) / 2147483646
    end
    function r.int(a, b) return a + math.floor(r.float() * (b - a + 1)) end
    function r.range(a, b) return a + r.float() * (b - a) end
    return r
end

--- Random control points (2..6 of them) with 2-decimal coordinates.
function helpers.random_points(r, span)
    span = span or 60
    local points = {}
    for i = 1, r.int(2, 6) do
        points[i] = {
            x = math.floor(r.range(-span, span) * 100) / 100,
            y = math.floor(r.range(-span, span) * 100) / 100,
        }
    end
    return points
end

--- Layer data as the mod stores it (see scripts/layers/), without prototypes.
helpers.layer_makers = {
    function(r, i) return { idx = i, type = "wall", name = "wall", quality = "normal", radius = r.int(1, 3), checkerboard = 0, size = 1, offset = r.int(0, 2), priority = 100 } end,
    function(r, i) return { idx = i, type = "tile", name = "tile", quality = "normal", radius = r.int(1, 3), checkerboard = r.int(-2, 2), size = 1, offset = r.int(0, 2), priority = 100 } end,
    function(r, i)
        local reach = r.int(5, 12)
        return { idx = i, type = "electric-pole", name = "pole", quality = "normal", size = r.int(1, 2), offset = r.int(0, 2), priority = 10, spacing = r.int(3, reach), wire_distance = reach }
    end,
    function(r, i) return { idx = i, type = "electric-turret", name = "turret", quality = "normal", size = 2, offset = r.int(0, 2), priority = 50, spacing = r.int(2, 6) } end,
    function(r, i) return { idx = i, type = "roboport", name = "roboport", quality = "normal", size = 4, offset = r.int(0, 2), priority = 20, spacing = r.int(4, 12) } end,
    function(r, i) return { idx = i, type = "straight-rail", name = "rail", quality = "normal", size = 2, offset = r.int(0, 2), priority = 1, direction_of_travel = 1, signal_spacing = 1 } end,
    function(r, i) return { idx = i, type = "empty", size = 1, offset = r.int(0, 2), priority = 0 } end,
}

--- A random layer stack: a wall on layer 0, up to 3 layers on each side.
function helpers.random_layers(r)
    local layers = { [0] = { idx = 0, type = "wall", name = "wall", quality = "normal", radius = r.int(1, 3), checkerboard = 0, size = 1, offset = 0, priority = 100 } }
    local makers = helpers.layer_makers
    for i = 1, r.int(0, 3) do layers[i] = makers[r.int(1, #makers)](r, i) end
    for i = -1, -r.int(0, 3), -1 do layers[i] = makers[r.int(1, #makers)](r, i) end
    return layers
end

--- Plan a build for control points + layers through the mod's current API.
--- Keeping this adapter the only place that knows the API keeps the tests stable
--- while the code is restructured.
--- @param points {x: number, y: number}[]
--- @param layers table<integer, table>
--- @param budget integer|nil  # work units per step; nil = run in one go
--- @param closed boolean|nil
--- @return table plan, integer steps
function helpers.plan(points, layers, budget, closed)
    local curve = require("scripts.curve.curve")
    local planner = require("scripts.build.planner")
    local c = curve.new()
    for _, p in ipairs(points) do curve.append(c, p) end
    c.closed = closed or false
    local job = planner.new_job(c, deepcopy(layers))
    local steps = 0
    while not planner.step(job, budget or math.huge) do
        steps = steps + 1
        if steps > 1e7 then error("planner did not finish") end
    end
    return job.plan, steps
end

--- Canonical text form of a plan: order-independent, so it can be compared
--- across implementations that emit placements in a different order.
--- @param plan table
--- @return string
function helpers.canonical(plan)
    local entities, tiles = {}, {}
    for _, e in ipairs(plan.entities) do
        entities[#entities + 1] = string.format("%s/%s@%g,%g:%d:L%d", e.name, e.quality or "-", e.position.x, e.position.y, e.size, e.layer)
    end
    for _, t in ipairs(plan.tiles) do
        tiles[#tiles + 1] = string.format("%s@%d,%d:L%d", t.name, t.x, t.y, t.layer)
    end
    table.sort(entities)
    table.sort(tiles)
    local unsupported = {}
    for i, v in ipairs(plan.unsupported) do unsupported[i] = tostring(v) end
    table.sort(unsupported)
    return "entities " .. #entities .. ": " .. table.concat(entities, " ") .. "\n"
        .. "tiles " .. #tiles .. ": " .. table.concat(tiles, " ") .. "\n"
        .. "skipped " .. plan.skipped .. " unsupported " .. table.concat(unsupported, ",")
        .. " warnings " .. #plan.warnings .. string.format(" length %.2f", plan.length)
end

return helpers
