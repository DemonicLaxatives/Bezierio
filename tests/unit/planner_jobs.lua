---@diagnostic disable: undefined-global
-- The planner is a resumable job: running it in small slices must give exactly the
-- same plan as running it in one go.
--   lua5.4 tests/unit/planner_jobs.lua [cases]
local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")

local cases = tonumber(arg[1]) or 40
local r = helpers.rng(777)
local budgets = { 1, 7, 50, 1000 }
local failures = 0
for i = 1, cases do
    local points, layers = helpers.random_points(r), helpers.random_layers(r)
    local expected = helpers.canonical(helpers.plan(points, layers))
    for _, budget in ipairs(budgets) do
        local plan, steps = helpers.plan(points, layers, budget)
        if helpers.canonical(plan) ~= expected then
            failures = failures + 1
            print(string.format("FAIL case %d: budget %d (%d steps) gives a different plan", i, budget, steps))
        elseif budget == 1 and steps < 10 then
            failures = failures + 1
            print(string.format("FAIL case %d: budget 1 finished in only %d steps, so work isn't split", i, steps))
        end
    end
end
-- The newer placements too: smart poles (with refining), turrets, lamps, wired mines.
local special = {
    [0] = { idx = 0, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0 },
    [1] = { idx = 1, type = "electric-pole", name = "pole", quality = "normal", size = 1, offset = 0, spacing = 3, wire_distance = 9, reach = 2.5, smart = true },
    [2] = { idx = 2, type = "electric-turret", name = "turret", quality = "normal", size = 2, offset = 1, spacing = 7, needs_power = true },
    [-1] = { idx = -1, type = "land-mine", name = "mine", quality = "normal", size = 1, offset = 0, radius = 3, density = 20, red_wire = true, circuit_distance = 9 },
    [-2] = { idx = -2, type = "lamp", name = "lamp", quality = "normal", size = 1, offset = 0, spacing = 5, color = "rainbow", rainbow_length = 30 },
    [3] = { idx = 3, type = "belt", name = "belt", quality = "normal", size = 1, offset = 0, lines = 2, line_gap = 0, flow = "forward", undergrounds = true, underground_name = "ug", underground_distance = 5 },
    [-3] = { idx = -3, type = "pipe", name = "pipe", quality = "normal", size = 1, offset = 0, lines = 2, line_gap = 1, undergrounds = true, underground_name = "ptg", underground_distance = 10, pumps = true, pump_name = "pump", pump_spacing = 25 },
}
local extra = 0
for i = 1, 8 do
    local points = helpers.random_points(r)
    local expected = helpers.canonical(helpers.plan(points, special))
    for _, budget in ipairs(budgets) do
        extra = extra + 1
        if helpers.canonical(helpers.plan(points, special, budget)) ~= expected then
            failures = failures + 1
            print(string.format("FAIL special case %d: budget %d gives a different plan", i, budget))
        end
    end
end
cases = cases + extra / #budgets
print(string.format("%d/%d sliced plans match", cases * #budgets - failures, cases * #budgets))
os.exit(failures == 0 and 0 or 1)
