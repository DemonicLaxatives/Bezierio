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
print(string.format("%d/%d sliced plans match", cases * #budgets - failures, cases * #budgets))
os.exit(failures == 0 and 0 or 1)
