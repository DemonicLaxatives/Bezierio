--- Planner: the joins stage, wall layers that meet only at a corner joined side
--- by side.
local geometry = require("scripts.build.geometry")
local C = require("scripts.build.plan.common")
local cell_key = C.cell_key
local band_entity = require("scripts.build.plan.raster").band_entity

local lib = {}

local DIAGONALS = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

--- Walls join only side by side. Off to the side of a bend, a band's cells can
--- meet only at a corner: a 1-wide band is an unbroken staircase where the curve
--- runs straight, but away from it the grid distance also changes along the
--- curve. Where two cells of a layer meet only at a corner, fill one of the two
--- corner cells with the layer: the free one nearest its band (belts, pipes and
--- rails have theirs already; spaced layers come after).
--- @param job PlannerJob
--- @param budget number
local function stage_joins(job, budget)
    local used = 0
    local cells, at = job.join_cells or {}, job.join_at or {}
    while used < budget and cells[job.cursor] do
        local c = cells[job.cursor]
        local idx = c.band.layer.idx
        used = used + 4
        for _, d in ipairs(DIAGONALS) do
            local ox, oy = c.x + d[1], c.y + d[2]
            if at[cell_key(ox, oy)] == idx and at[cell_key(ox, c.y)] ~= idx and at[cell_key(c.x, oy)] ~= idx then
                local best, best_off
                for _, corner in ipairs({ { ox, c.y }, { c.x, oy } }) do
                    local key = cell_key(corner[1], corner[2])
                    if not job.occupied[key] and not (job.tiled and job.tiled[key]) then
                        used = used + C.COST.cell
                        local u = geometry.grid_distance(job.frames, job.index, { x = corner[1] + 0.5, y = corner[2] + 0.5 })
                        local off = u and math.max(c.band.lo - u, u - c.band.hi, 0) or math.huge
                        if not best_off or off < best_off then best, best_off = corner, off end
                    end
                end
                if best then
                    local key = cell_key(best[1], best[2])
                    band_entity(job, c.band.layer, best[1], best[2], key)
                    at[key] = idx
                    -- (the new cell can meet another only at a corner in turn)
                    cells[#cells + 1] = { x = best[1], y = best[2], band = c.band }
                end
            end
        end
        job.cursor = job.cursor + 1
    end
    if not cells[job.cursor] then
        job.join_cells, job.join_at, job.tiled = nil, nil, nil
        job.stage, job.cursor = "spaced", 1
    end
    return used
end

lib.stage_joins = stage_joins

return lib
