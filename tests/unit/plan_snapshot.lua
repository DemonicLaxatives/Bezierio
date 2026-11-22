---@diagnostic disable: undefined-global
-- Snapshot test: the planner's output for fixed cases must not change unless intended.
--   lua5.4 tests/unit/plan_snapshot.lua            compare with tests/unit/snapshots/plans.txt
--   lua5.4 tests/unit/plan_snapshot.lua --update   rewrite the snapshot (review the diff!)
local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")
local snapshot_path = helpers.repo .. "/tests/unit/snapshots/plans.txt"

local cases = {
    -- the curve used by the headless gui-flow test, with its layer stack
    {
        name = "gui-flow",
        points = { { x = -30.3, y = 5 }, { x = 0, y = -40 }, { x = 30, y = 5 } },
        layers = {
            [0] = { idx = 0, type = "wall", name = "stone-wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0, priority = 100 },
            [1] = { idx = 1, type = "electric-pole", name = "small-electric-pole", quality = "normal", size = 1, offset = 0, priority = 10, spacing = 6 },
            [-1] = { idx = -1, type = "tile", name = "stone-path", quality = "normal", radius = 3, checkerboard = -2, size = 1, offset = 0, priority = 100 },
            [2] = { idx = 2, type = "electric-turret", name = "laser-turret", quality = "normal", size = 2, offset = 1, priority = 50, spacing = 6 },
        },
    },
    {
        name = "straight 45 degrees",
        points = { { x = 0.5, y = 0.5 }, { x = 30.5, y = 30.5 } },
        layers = { [0] = { idx = 0, type = "wall", name = "wall", quality = "normal", radius = 2, checkerboard = 0, size = 1, offset = 0, priority = 100 } },
    },
    {
        name = "closed loop",
        points = { { x = 0, y = 0 }, { x = 40, y = -40 }, { x = 40, y = 40 }, { x = 0, y = 0 } },
        layers = {
            [0] = { idx = 0, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0, priority = 100 },
            [-1] = { idx = -1, type = "empty", size = 1, offset = 0, priority = 0 },
            [-2] = { idx = -2, type = "roboport", name = "roboport", quality = "normal", size = 4, offset = 1, priority = 20, spacing = 25 },
        },
    },
}

local r = helpers.rng(20261122)
for i = 1, 24 do
    cases[#cases + 1] = { name = "random " .. i, points = helpers.random_points(r), layers = helpers.random_layers(r) }
end

local lines = {}
for _, case in ipairs(cases) do
    lines[#lines + 1] = "## " .. case.name
    lines[#lines + 1] = helpers.canonical(helpers.plan(case.points, case.layers))
end
local actual = table.concat(lines, "\n") .. "\n"

if arg[1] == "--update" then
    local f = assert(io.open(snapshot_path, "w"))
    f:write(actual)
    f:close()
    print("snapshot written: " .. #cases .. " cases")
    return
end

local f = io.open(snapshot_path, "r")
if not f then
    print("no snapshot yet; run with --update")
    os.exit(1)
end
local expected = f:read("a")
f:close()

if expected == actual then
    print(#cases .. "/" .. #cases .. " plan snapshots match")
    return
end
local exp_lines, act_lines = {}, {}
for l in expected:gmatch("[^\n]*") do exp_lines[#exp_lines + 1] = l end
for l in actual:gmatch("[^\n]*") do act_lines[#act_lines + 1] = l end
local case_name = "?"
for i = 1, math.max(#exp_lines, #act_lines) do
    if (exp_lines[i] or ""):sub(1, 3) == "## " then case_name = exp_lines[i]:sub(4) end
    if exp_lines[i] ~= act_lines[i] then
        print("MISMATCH in case '" .. case_name .. "' (line " .. i .. ")")
        print("  expected: " .. (exp_lines[i] or "<none>"):sub(1, 300))
        print("  actual:   " .. (act_lines[i] or "<none>"):sub(1, 300))
        break
    end
end
os.exit(1)
