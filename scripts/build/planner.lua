--- Turns a curve and a layer stack into a build plan, as a resumable job.
---
--- Layers become bands of grid distance from the curve (see geometry.lua): layer 0
--- is centred, layers 1, 2, ... stack outward on the right of the direction of
--- travel, -1, -2, ... on the left. Each band is a half-open range [lo, hi) of grid
--- distance, and every cell near the curve is assigned to at most one band (by its
--- centre), so layers never overlap.
---
--- The job is plain data (no closures, no coroutines), so it can live in `storage`
--- and continue after save/load. `step` does a bounded amount of work; call it
--- until it returns true. Placements are appended to `job.plan` as they are found,
--- so consumers (preview) can follow along.
local vect = require("scripts.vector_math")
local geometry = require("scripts.build.geometry")
local curve_lib = require("scripts.curve.curve")
local registry = require("scripts.layers.registry")

local lib = {}

--- Max distance between curve samples, in tiles.
lib.SAMPLE_STEP = 0.25

--- Work units per operation, for budgeting.
lib.COST = {
    sample = 1,  -- one curve sample
    frame = 1,   -- one pass over one sample (tangent / fill / normal + index)
    sweep = 1,   -- one probe across the curve
    cell = 8,    -- classifying one cell (nearest-sample search)
    place = 4,   -- trying one spaced entity position
}

--- @class PlannedEntity
--- @field name string
--- @field quality string
--- @field position Vector
--- @field size integer
--- @field layer integer

--- @class PlannedTile
--- @field name string
--- @field x integer
--- @field y integer
--- @field layer integer

--- @class BuildPlan
--- @field entities PlannedEntity[]
--- @field tiles PlannedTile[]
--- @field unsupported integer[]   # layer indices whose type can't be built yet
--- @field skipped integer         # spaced entities that found no free spot
--- @field done boolean

--- @class LayerBand
--- @field layer Layer
--- @field lo number
--- @field hi number

--- @alias PlannerStage "sample"|"tangents"|"fill"|"normals"|"bands"|"rasterize"|"spaced"|"done"

--- @class PlannerJob
--- @field stage PlannerStage
--- @field layers table<integer, Layer>   # copied at creation; later edits don't affect the job
--- @field sampler CurveSampler|nil
--- @field points Vector[]                # curve samples (world coordinates)
--- @field frames CurveFrame[]
--- @field index FrameIndex
--- @field cursor integer                 # position within the current stage
--- @field last_tangent Vector|nil
--- @field bands LayerBand[]
--- @field umin number
--- @field umax number
--- @field seen table<string, boolean>    # cells already classified
--- @field occupied table<string, boolean># cells taken by entities
--- @field spaced integer[]               # indices into bands, in placement order
--- @field spaced_cursor integer
--- @field walk {i: integer, travelled: number, next_at: number}|nil
--- @field plan BuildPlan

--- @param x integer
--- @param y integer
local function cell_key(x, y)
    return x .. "," .. y
end

--- @param curve Curve
--- @param layers table<integer, Layer>
--- @return PlannerJob
function lib.new_job(curve, layers)
    local copy = {}
    for k, layer in pairs(layers) do
        local c = {}
        for field, value in pairs(layer) do c[field] = value end
        copy[k] = c
    end
    local sampler = curve_lib.new_sampler(curve, lib.SAMPLE_STEP)
    return {
        stage = sampler and "sample" or "done",
        layers = copy,
        sampler = sampler,
        points = {},
        frames = {},
        index = {},
        cursor = 1,
        last_tangent = nil,
        bands = {},
        umin = 0,
        umax = 0,
        seen = {},
        occupied = {},
        spaced = {},
        spaced_cursor = 1,
        walk = nil,
        plan = { entities = {}, tiles = {}, unsupported = {}, skipped = 0, done = sampler == nil },
    }
end

--- Lay the layers out side by side, outward from layer 0.
--- @param layers table<integer, Layer>
--- @return LayerBand[]
function lib.bands(layers)
    local bands = {}
    local base = layers[0]
    if not base then return bands end

    local half = registry.thickness(base) / 2
    table.insert(bands, { layer = base, lo = -half, hi = half })

    local outer = half
    local k = 1
    while layers[k] do
        local layer = layers[k]
        local lo = outer + (layer.offset or 0)
        local hi = lo + registry.thickness(layer)
        table.insert(bands, { layer = layer, lo = lo, hi = hi })
        outer = hi
        k = k + 1
    end

    outer = half
    k = -1
    while layers[k] do
        local layer = layers[k]
        local hi = -(outer + (layer.offset or 0))
        local lo = hi - registry.thickness(layer)
        table.insert(bands, { layer = layer, lo = lo, hi = hi })
        outer = -lo
        k = k - 1
    end
    return bands
end

--- @param x integer
--- @param y integer
--- @param checkerboard integer|nil
--- @return boolean
local function checkerboard_keep(x, y, checkerboard)
    if not checkerboard or checkerboard == 0 then return true end
    local size = math.abs(checkerboard)
    local parity = (math.floor(x / size) + math.floor(y / size)) % 2
    return (parity == 0) == (checkerboard > 0)
end

--- Two nearest grid-aligned centres for an entity of `size` along one axis.
local function snap_candidates(x, size)
    local a
    if size % 2 == 1 then
        a = math.floor(x) + 0.5
    else
        a = math.floor(x + 0.5)
    end
    local b = a + ((x >= a) and 1 or -1)
    return a, b
end

--- @param center Vector
--- @param size integer
--- @return integer, integer  # left-top cell
local function footprint_origin(center, size)
    return math.floor(center.x - size / 2 + 0.5), math.floor(center.y - size / 2 + 0.5)
end

-- Stages ----------------------------------------------------------------------
-- Each stage function does work until the budget runs out or the stage is
-- finished, moves the job on to the next stage when finished, and returns the
-- units used.

--- @param job PlannerJob
--- @param budget number
local function stage_sample(job, budget)
    local used = curve_lib.step(job.sampler, job.points, budget) * lib.COST.sample
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
        local t = geometry.raw_tangent(points, i)
        if geometry.is_zero(t) then
            t = job.last_tangent -- may still be nil; fixed by the backward fill
        else
            job.last_tangent = t
        end
        frames[i] = { p = points[i], t = t } --[[@as CurveFrame]]
        job.cursor = i + 1
        used = used + lib.COST.frame
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
        used = used + lib.COST.frame
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
        used = used + lib.COST.frame
    end
    if job.cursor > #frames then
        job.stage, job.cursor = "bands", 1
    end
    return used
end

--- Band layout, unsupported layers, and the order spaced layers are placed in.
--- @param job PlannerJob
local function stage_bands(job)
    local bands = lib.bands(job.layers)
    job.bands = bands
    job.umin, job.umax = math.huge, -math.huge
    for _, band in ipairs(bands) do
        job.umin = math.min(job.umin, band.lo)
        job.umax = math.max(job.umax, band.hi)
    end
    for b, band in ipairs(bands) do
        local placement = registry.type_of(band.layer).placement
        if placement == "spaced" then
            table.insert(job.spaced, b)
        elseif placement == "unsupported" then
            table.insert(job.plan.unsupported, band.layer.idx)
        end
    end
    table.sort(job.spaced, function(a, b)
        local la, lb = bands[a].layer, bands[b].layer
        local pa, pb = registry.type_of(la).priority, registry.type_of(lb).priority
        if pa ~= pb then return pa > pb end
        return la.idx < lb.idx
    end)
    job.stage = #bands > 0 and "rasterize" or "spaced"
    job.cursor = 1
    return 1
end

--- Classify the cells around one frame and emit band placements.
--- @param job PlannerJob
--- @param f CurveFrame
--- @return number used
local function rasterize_frame(job, f)
    local used = 0
    local plan, bands, seen = job.plan, job.bands, job.seen
    local v = job.umin - 1
    while v <= job.umax + 1 do
        used = used + lib.COST.sweep
        local d = v * f.w
        local x = math.floor(f.p.x + f.n.x * d)
        local y = math.floor(f.p.y + f.n.y * d)
        local key = cell_key(x, y)
        if not seen[key] then
            seen[key] = true
            used = used + lib.COST.cell
            local u = geometry.grid_distance(job.frames, job.index, { x = x + 0.5, y = y + 0.5 })
            if u then
                for _, band in ipairs(bands) do
                    if u >= band.lo and u < band.hi then
                        local layer = band.layer
                        local def = registry.type_of(layer)
                        if def.placement == "band" and checkerboard_keep(x, y, layer.checkerboard) then
                            if def.output == "tile" then
                                table.insert(plan.tiles, { name = layer.name, x = x, y = y, layer = layer.idx })
                            else
                                job.occupied[key] = true
                                table.insert(plan.entities, {
                                    name = layer.name, quality = layer.quality,
                                    position = { x = x + 0.5, y = y + 0.5 }, size = 1, layer = layer.idx,
                                })
                            end
                        end
                        break
                    end
                end
            end
        end
        v = v + lib.SAMPLE_STEP
    end
    return used
end

--- @param job PlannerJob
--- @param budget number
local function stage_rasterize(job, budget)
    local used, frames = 0, job.frames
    while job.cursor <= #frames and used < budget do
        used = used + rasterize_frame(job, frames[job.cursor])
        job.cursor = job.cursor + 1
    end
    if job.cursor > #frames then
        job.stage, job.cursor = "spaced", 1
    end
    return used
end

--- Place a spaced entity at the free grid position nearest to `target`.
--- @param job PlannerJob
--- @param layer Layer
--- @param target Vector
local function try_place(job, layer, target)
    local size, occupied = layer.size, job.occupied
    local xa, xb = snap_candidates(target.x, size)
    local ya, yb = snap_candidates(target.y, size)
    local candidates = { { x = xa, y = ya }, { x = xb, y = ya }, { x = xa, y = yb }, { x = xb, y = yb } }
    table.sort(candidates, function(p, q) return geometry.dist2(p, target) < geometry.dist2(q, target) end)
    for _, pos in ipairs(candidates) do
        local x0, y0 = footprint_origin(pos, size)
        local free = true
        for dx = 0, size - 1 do
            for dy = 0, size - 1 do
                if occupied[cell_key(x0 + dx, y0 + dy)] then free = false end
            end
        end
        if free then
            for dx = 0, size - 1 do
                for dy = 0, size - 1 do
                    occupied[cell_key(x0 + dx, y0 + dy)] = true
                end
            end
            table.insert(job.plan.entities, {
                name = layer.name, quality = layer.quality, position = pos, size = size, layer = layer.idx,
            })
            return
        end
    end
    job.plan.skipped = job.plan.skipped + 1
end

--- Walk each spaced layer's centre line, placing an entity every `spacing` tiles.
--- @param job PlannerJob
--- @param budget number
local function stage_spaced(job, budget)
    local used, frames = 0, job.frames
    while job.spaced_cursor <= #job.spaced and used < budget do
        local band = job.bands[job.spaced[job.spaced_cursor]]
        local layer = band.layer
        local spacing = math.max(1, layer.spacing or layer.size)
        local u_mid = (band.lo + band.hi) / 2

        local walk = job.walk
        if not walk then
            try_place(job, layer, geometry.offset_point(frames[1], u_mid))
            used = used + lib.COST.place
            walk = { i = 2, travelled = 0, next_at = spacing }
            job.walk = walk
        end
        while walk.i <= #frames and used < budget do
            local a = geometry.offset_point(frames[walk.i - 1], u_mid)
            local b = geometry.offset_point(frames[walk.i], u_mid)
            local seg = vect.distance(a, b)
            while seg > 0 and walk.travelled + seg >= walk.next_at do
                local k = (walk.next_at - walk.travelled) / seg
                try_place(job, layer, vect.add(a, vect.scale(k, vect.sub(b, a))))
                used = used + lib.COST.place
                walk.next_at = walk.next_at + spacing
            end
            walk.travelled = walk.travelled + seg
            walk.i = walk.i + 1
            used = used + lib.COST.frame
        end
        if walk.i > #frames then
            job.walk = nil
            job.spaced_cursor = job.spaced_cursor + 1
        end
    end
    if job.spaced_cursor > #job.spaced then
        job.stage = "done"
    end
    return used
end

local STAGES = {
    sample = stage_sample,
    tangents = stage_tangents,
    fill = stage_fill,
    normals = stage_normals,
    bands = stage_bands,
    rasterize = stage_rasterize,
    spaced = stage_spaced,
}

--- Do up to about `budget` units of work.
--- @param job PlannerJob
--- @param budget number
--- @param until_stage PlannerStage|nil  # stop once this stage is reached (e.g. "tangents" = samples only)
--- @return boolean done, number used
function lib.step(job, budget, until_stage)
    local used = 0
    while job.stage ~= "done" and job.stage ~= until_stage and used < budget do
        used = used + STAGES[job.stage](job, budget - used)
    end
    if job.stage == "done" and not job.plan.done then
        job.plan.done = true
        -- Working data is no longer needed; keep `points` for drawing the curve.
        job.frames, job.index, job.seen, job.occupied = {}, {}, {}, {}
    end
    return job.stage == "done", used
end

--- Plan in one go (tests, debugging).
--- @param curve Curve
--- @param layers table<integer, Layer>
--- @return BuildPlan
function lib.plan(curve, layers)
    local job = lib.new_job(curve, layers)
    lib.step(job, math.huge)
    return job.plan
end

return lib
