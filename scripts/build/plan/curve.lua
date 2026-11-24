--- Planner stages: curve samples, tangents (carried over repeated points, then
--- filled backwards), normals and the spatial index.
local vect = require("scripts.vector_math")
local geometry = require("scripts.build.geometry")
local curve_lib = require("scripts.curve.curve")
local C = require("scripts.build.plan.common")

local lib = {}

-- Stages ----------------------------------------------------------------------
-- Each stage function does work until the budget runs out or the stage is
-- finished, moves the job on to the next stage when finished, and returns the
-- units used.

--- @param job PlannerJob
--- @param budget number
local function stage_sample(job, budget)
    local used = curve_lib.step(job.sampler, job.points, budget) * C.COST.sample
    if job.sampler.done then
        job.sampler = nil
        job.stage = #job.points >= 2 and "tangents" or "done"
        job.cursor = 1
    end
    return used
end

--- Tangents, carrying the last valid tangent forward over repeated points.
--- @param job PlannerJob
--- @param budget number
local function stage_tangents(job, budget)
    local used, points, frames = 0, job.points, job.frames
    while job.cursor <= #points and used < budget do
        local i = job.cursor
        local t = geometry.raw_tangent(points, i, job.closed)
        if geometry.is_zero(t) then
            t = job.last_tangent -- may still be nil; fixed by the backward fill
        else
            job.last_tangent = t
        end
        -- (t may still be nil, filled backwards; n and w come with finish_frame)
        ---@diagnostic disable-next-line: missing-fields, assign-type-mismatch
        frames[i] = { p = points[i], t = t } --[[@as CurveFrame]]
        if i > 1 then job.plan.length = job.plan.length + vect.distance(points[i - 1], points[i]) end
        job.cursor = i + 1
        used = used + C.COST.frame
    end
    if job.cursor > #points then
        job.stage, job.cursor, job.last_tangent = "fill", #points, nil
    end
    return used
end

--- Backward pass: leading repeated points borrow the first valid tangent.
--- @param job PlannerJob
--- @param budget number
local function stage_fill(job, budget)
    local used, frames = 0, job.frames
    while job.cursor >= 1 and used < budget do
        local f = frames[job.cursor]
        if f.t then job.last_tangent = f.t else f.t = job.last_tangent end
        job.cursor = job.cursor - 1
        used = used + C.COST.frame
    end
    if job.cursor < 1 then
        job.stage, job.cursor = "normals", 1
    end
    return used
end

--- Normals and the spatial index.
--- @param job PlannerJob
--- @param budget number
local function stage_normals(job, budget)
    local used, frames = 0, job.frames
    while job.cursor <= #frames and used < budget do
        local f = frames[job.cursor]
        if not f.t then -- every sample is the same point: nothing to build
            job.stage = "done"
            return used
        end
        geometry.finish_frame(f)
        geometry.index_add(job.index, frames, job.cursor)
        job.cursor = job.cursor + 1
        used = used + C.COST.frame
    end
    if job.cursor > #frames then
        job.stage, job.cursor = "bands", 1
    end
    return used
end

lib.stage_sample = stage_sample
lib.stage_tangents = stage_tangents
lib.stage_fill = stage_fill
lib.stage_normals = stage_normals

return lib
