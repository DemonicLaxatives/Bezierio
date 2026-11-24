--- Walking a plan's wires a budgeted amount at a time, for the build and the
--- blueprint alike: each pole chain's neighbours in order along the curve (the
--- last back to the first on a closed curve), then the other links (land mines).
local lib = {}

--- @class WireWalk
--- @field chain_keys integer[]   # layer indices of plan.chains, in order
--- @field chain_cursor integer
--- @field cursor integer         # pair within the current chain
--- @field link_cursor integer|nil

--- The pole layers in order (the job's chain_keys).
--- @param plan BuildPlan
--- @return integer[]
function lib.chain_keys(plan)
    local keys = {}
    for idx in pairs(plan.chains) do table.insert(keys, idx) end
    table.sort(keys)
    return keys
end

--- @param job WireWalk
--- @param plan BuildPlan
--- @param budget number
--- @param cost number  # work units per wire
--- @param on_pair fun(chain: PlanChain, a: integer, b: integer)  # plan entity indices
--- @param on_link fun(link: {a: integer, b: integer, red: boolean, green: boolean})
--- @return number used, boolean done
function lib.step(job, plan, budget, cost, on_pair, on_link)
    local used = 0
    while job.chain_cursor <= #job.chain_keys and used < budget do
        local chain = plan.chains[job.chain_keys[job.chain_cursor]]
        local members = chain.members
        local count = #members
        local pairs_total = (plan.closed and count > 2) and count or count - 1
        while job.cursor <= pairs_total and used < budget do
            on_pair(chain, members[job.cursor], members[job.cursor % count + 1])
            job.cursor = job.cursor + 1
            used = used + cost
        end
        if job.cursor > pairs_total then
            job.chain_cursor = job.chain_cursor + 1
            job.cursor = 1
        end
    end
    if job.chain_cursor <= #job.chain_keys then return used, false end
    local links = plan.links or {}
    job.link_cursor = job.link_cursor or 1
    while job.link_cursor <= #links and used < budget do
        on_link(links[job.link_cursor])
        job.link_cursor = job.link_cursor + 1
        used = used + cost
    end
    return used, job.link_cursor > #links
end

return lib
