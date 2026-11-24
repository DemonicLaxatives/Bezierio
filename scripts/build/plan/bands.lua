--- Planner: the band layout (lib.bands), the bands stage (unsupported and
--- unplaced layers, spaced order) and the tight-bend warnings.
local vect = require("scripts.vector_math")
local registry = require("scripts.layers.registry")
local C = require("scripts.build.plan.common")

local lib = {}

--- Lay the layers out side by side, outward from layer 0.
--- @param layers table<integer, Layer>
--- @return LayerBand[]
local function bands_of(layers)
    local bands = {}
    local base = layers[0]
    if not base then return bands end

    local half = registry.thickness(base) / 2
    local base_under = registry.is_underlay(base)
    table.insert(bands, { layer = base, lo = -half, hi = half, under = base_under })

    for _, side in ipairs({ 1, -1 }) do
        local outer = base_under and 0 or half -- distance from the curve on this side
        local k = side
        while layers[k] do
            local layer = layers[k]
            local under = registry.is_underlay(layer)
            local near = outer + (layer.offset or 0)
            local far = near + registry.thickness(layer)
            if side == 1 then
                table.insert(bands, { layer = layer, lo = near, hi = far, under = under })
            else
                table.insert(bands, { layer = layer, lo = -far, hi = -near, under = under })
            end
            if not under then outer = far end
            k = k + side
        end
    end
    return bands
end

--- Band layout, unsupported layers, and the order spaced layers are placed in.
--- @param job PlannerJob
local function stage_bands(job)
    local bands = bands_of(job.layers)
    -- Layers that aren't placed keep their room: an empty stand-in in their band.
    for _, band in ipairs(bands) do
        local layer = band.layer
        if layer.place == false then
            band.layer = { idx = layer.idx, type = "empty", size = registry.thickness(layer), offset = layer.offset, priority = 0 }
        end
    end
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
    for _, band in ipairs(bands) do
        if registry.type_of(band.layer).placement ~= "none" then
            if band.hi > 0 then job.outer_plus = math.max(job.outer_plus, band.hi) end
            if band.lo < 0 then job.outer_minus = math.max(job.outer_minus, -band.lo) end
        end
    end
    job.stage = #bands > 0 and "bends" or "spaced"
    job.cursor = 1
    return 1
end

--- Minimum spacing of tight-bend warnings along the curve, in tiles.
local WARNING_SPACING = 1

--- Find where the curve bends tighter than the layers on the inside of the bend:
--- there the layers fold over and split. Curvature at sample i is the turn of
--- the tangent between its neighbours over the distance between them.
--- @param job PlannerJob
--- @param budget number
local function stage_bends(job, budget)
    local used, frames = 0, job.frames
    local n = #frames
    while job.cursor <= n and used < budget do
        local i = job.cursor
        local prev = frames[i - 1] or (job.closed and frames[n - 1]) or frames[i]
        local next = frames[i + 1] or (job.closed and frames[2]) or frames[i]
        local ds = vect.distance(prev.p, next.p)
        if ds > 0 then
            local turn = prev.t.x * next.t.y - prev.t.y * next.t.x -- sin of the angle turned
            local curvature = turn / ds                         -- > 0: bends towards the + side
            local inside = curvature > 0 and job.outer_plus or job.outer_minus
            if inside > 0 and math.abs(curvature) * inside > 1 then
                local p = frames[i].p
                local last = job.last_warning
                if not last or vect.distance(last, p) >= WARNING_SPACING then
                    table.insert(job.plan.warnings, { x = p.x, y = p.y })
                    job.last_warning = p
                end
            end
        end
        job.cursor = i + 1
        used = used + C.COST.frame
    end
    if job.cursor > n then
        job.stage, job.cursor = "rails", 1
    end
    return used
end

lib.bands = bands_of
lib.stage_bands = stage_bands
lib.stage_bends = stage_bends

return lib
