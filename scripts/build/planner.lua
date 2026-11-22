--- Turns a curve and a layer stack into a build plan, as a resumable job.
---
--- Layers become bands of grid distance from the curve (see geometry.lua): layer 0
--- is centred, layers 1, 2, ... stack outward on the right of the direction of
--- travel, -1, -2, ... on the left. Each band is a half-open range [lo, hi) of grid
--- distance, and every cell near the curve is assigned to at most one band (by its
--- centre), so layers never overlap. The exception are underlay tile layers
--- ("under entities"): they take no room, so the next layer out starts where they
--- start, and their tiles go under whatever the other bands place in the same cells.
---
--- The job is plain data (no closures, no coroutines), so it can live in `storage`
--- and continue after save/load. `step` does a bounded amount of work; call it
--- until it returns true. Placements are appended to `job.plan` as they are found,
--- so consumers (preview) can follow along.
local vect = require("scripts.vector_math")
local geometry = require("scripts.build.geometry")
local curve_lib = require("scripts.curve.curve")
local registry = require("scripts.layers.registry")
local smart_poles = require("scripts.build.smart_poles")

local lib = {}

--- Max distance between curve samples, in tiles.
lib.SAMPLE_STEP = 0.25

--- Spacing of the extra probes past the ends of an open curve, in tiles.
lib.END_PROBE_STEP = 0.2

--- Work units per operation, for budgeting.
lib.COST = {
    sample = 1,  -- one curve sample
    frame = 1,   -- one pass over one sample (tangent / fill / normal + index)
    sweep = 1,   -- one probe across the curve
    cell = 10,   -- classifying one cell (nearest-sample search)
    place = 4,   -- trying one spaced entity position
}

--- @class PlannedEntity
--- @field name string
--- @field quality string
--- @field position Vector
--- @field size integer
--- @field layer integer
--- @field frame integer|nil   # spaced entities: the curve sample they were placed at

--- @class PlannedTile
--- @field name string
--- @field x integer
--- @field y integer
--- @field layer integer

--- @class PlanChain
--- @field wires boolean        # connect consecutive members with red and green wire
--- @field members integer[]    # indices into plan.entities, in order along the curve

--- @class BuildPlan
--- @field entities PlannedEntity[]
--- @field tiles PlannedTile[]
--- @field unsupported integer[]   # layer indices whose type can't be built yet
--- @field skipped integer         # spaced entities that found no free spot
--- @field length number           # curve length in tiles
--- @field counts table<integer, integer>   # placements per layer index
--- @field chains table<integer, PlanChain> # pole layers: poles in order, for wiring
--- @field gaps integer           # consecutive poles out of wire reach (no room for a pole between)
--- @field unpowered integer      # powered entities no smart pole line could reach
--- @field warnings Vector[]       # where a bend is tighter than the layers on its inside
--- @field closed boolean        # the curve is a loop (pole chains close too)
--- @field done boolean

--- @class LayerBand
--- @field layer Layer
--- @field lo number
--- @field hi number
--- @field under boolean   # underlay tile band: shares its cells with the other bands

--- @alias PlannerStage "sample"|"tangents"|"fill"|"normals"|"bands"|"bends"|"rasterize"|"spaced"|"done"

--- @class PlannerJob
--- @field stage PlannerStage
--- @field layers table<integer, Layer>   # copied at creation; later edits don't affect the job
--- @field closed boolean                 # the curve is a loop
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
--- @field walk {i: integer, travelled: number, next_at: number, last: Vector|nil}|SmartWalk|nil
--- @field outer_plus number              # outermost built distance on the + side (grid units)
--- @field outer_minus number             # ... on the - side
--- @field last_warning Vector|nil
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
        closed = curve_lib.is_closed(curve),
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
        outer_plus = 0,
        outer_minus = 0,
        last_warning = nil,
        plan = {
            entities = {}, tiles = {}, unsupported = {}, skipped = 0,
            length = 0, counts = {}, chains = {}, gaps = 0, unpowered = 0, warnings = {},
            closed = curve_lib.is_closed(curve),
            done = sampler == nil,
        },
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
        local t = geometry.raw_tangent(points, i, job.closed)
        if geometry.is_zero(t) then
            t = job.last_tangent -- may still be nil; fixed by the backward fill
        else
            job.last_tangent = t
        end
        frames[i] = { p = points[i], t = t } --[[@as CurveFrame]]
        if i > 1 then job.plan.length = job.plan.length + vect.distance(points[i - 1], points[i]) end
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
        used = used + lib.COST.frame
    end
    if job.cursor > n then
        job.stage, job.cursor = "rasterize", 1
    end
    return used
end

--- Place a band layer's tile or entity in a cell (if its checkerboard keeps it).
--- @param job PlannerJob
--- @param layer Layer
--- @param x integer
--- @param y integer
--- @param key string    # cell_key(x, y)
--- @return boolean  # whether a tile was placed
local function emit_cell(job, layer, x, y, key)
    local def = registry.type_of(layer)
    if def.placement ~= "band" or not checkerboard_keep(x, y, layer.checkerboard) then return false end
    local plan = job.plan
    plan.counts[layer.idx] = (plan.counts[layer.idx] or 0) + 1
    if def.output == "tile" then
        table.insert(plan.tiles, { name = layer.name, x = x, y = y, layer = layer.idx })
        return true
    end
    job.occupied[key] = true
    table.insert(plan.entities, {
        name = layer.name, quality = layer.quality,
        position = { x = x + 0.5, y = y + 0.5 }, size = 1, layer = layer.idx,
    })
    return false
end

--- Classify the cells around one frame and emit band placements: probe across
--- the curve along the frame's normal, `shift` tiles along its tangent.
--- @param job PlannerJob
--- @param f CurveFrame
--- @param shift number|nil
--- @return number used
local function rasterize_frame(job, f, shift)
    local used = 0
    local bands, seen = job.bands, job.seen
    local px, py = f.p.x, f.p.y
    if shift then px, py = px + f.t.x * shift, py + f.t.y * shift end
    local v = job.umin - 1
    while v <= job.umax + 1 do
        used = used + lib.COST.sweep
        local d = v * f.w
        local x = math.floor(px + f.n.x * d)
        local y = math.floor(py + f.n.y * d)
        local key = cell_key(x, y)
        if not seen[key] then
            seen[key] = true
            used = used + lib.COST.cell
            local u = geometry.grid_distance(job.frames, job.index, { x = x + 0.5, y = y + 0.5 })
            if u then
                -- The cell's own band first; then an underlay, unless that placed a tile.
                local placed_tile = false
                for _, band in ipairs(bands) do
                    if not band.under and u >= band.lo and u < band.hi then
                        placed_tile = emit_cell(job, band.layer, x, y, key)
                        break
                    end
                end
                if not placed_tile then
                    for _, band in ipairs(bands) do
                        if band.under and u >= band.lo and u < band.hi then
                            emit_cell(job, band.layer, x, y, key)
                            break
                        end
                    end
                end
            end
        end
        v = v + lib.SAMPLE_STEP
    end
    return used
end

--- Cells count as beside an open curve's end up to half a grid unit past it (see
--- geometry.frame_u), which no probe across the end frame may cross. Probe a little
--- past both ends too.
--- @param job PlannerJob
--- @param f CurveFrame
--- @param outward number  # -1 before the first frame, 1 after the last
--- @return number used
local function rasterize_end(job, f, outward)
    local used = 0
    local reach = 0.5 * (math.abs(f.t.x) + math.abs(f.t.y)) + 0.5
    local shift = lib.END_PROBE_STEP
    while shift < reach do
        used = used + rasterize_frame(job, f, outward * shift)
        shift = shift + lib.END_PROBE_STEP
    end
    return used
end

--- @param job PlannerJob
--- @param budget number
local function stage_rasterize(job, budget)
    local used, frames = 0, job.frames
    while job.cursor <= #frames and used < budget do
        local f = frames[job.cursor]
        used = used + rasterize_frame(job, f)
        if not job.plan.closed then
            if job.cursor == 1 then used = used + rasterize_end(job, f, -1) end
            if job.cursor == #frames then used = used + rasterize_end(job, f, 1) end
        end
        job.cursor = job.cursor + 1
    end
    if job.cursor > #frames then
        job.stage, job.cursor = "spaced", 1
    end
    return used
end

--- The free grid position nearest to `target` for an entity of `size`, if any.
--- @param job PlannerJob
--- @param size integer
--- @param target Vector
--- @return Vector|nil
local function find_spot(job, size, target)
    local occupied = job.occupied
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
        if free then return pos end
    end
    return nil
end

--- Shifts along the curve (tiles) tried when the spot itself is taken.
local SHIFTS = { 0, 0.5, -0.5, 1, -1, 1.5, -1.5, 2, -2 }

--- A free spot near `target`, also trying a little ahead of and behind it along
--- the curve.
--- @param job PlannerJob
--- @param size integer
--- @param target Vector
--- @param direction Vector  # unit vector along the curve
--- @return Vector|nil, number used
local function search_spot(job, size, target, direction)
    local used = 0
    for _, shift in ipairs(SHIFTS) do
        used = used + lib.COST.place
        local pos = find_spot(job, size, vect.add(target, vect.scale(shift, direction)))
        if pos then return pos, used end
    end
    return nil, used
end

--- Claim a spot and add the entity to the plan.
--- @param job PlannerJob
--- @param layer Layer
--- @param pos Vector
--- @param frame integer|nil  # the curve sample it was placed at
local function commit(job, layer, pos, frame)
    local size = layer.size
    local x0, y0 = footprint_origin(pos, size)
    for dx = 0, size - 1 do
        for dy = 0, size - 1 do
            job.occupied[cell_key(x0 + dx, y0 + dy)] = true
        end
    end
    local plan = job.plan
    table.insert(plan.entities, {
        name = layer.name, quality = layer.quality, position = pos, size = size, layer = layer.idx, frame = frame,
    })
    plan.counts[layer.idx] = (plan.counts[layer.idx] or 0) + 1
    local chain = plan.chains[layer.idx]
    if chain then
        local previous = chain.members[#chain.members]
        if previous and vect.distance(plan.entities[previous].position, pos) > layer.wire_distance then
            plan.gaps = plan.gaps + 1
        end
        table.insert(chain.members, #plan.entities)
    end
end

--- Pole layers: fill gaps longer than the wire reach with extra poles, halving
--- the gap each time (at most a few levels deep).
--- @param job PlannerJob
--- @param layer Layer
--- @param a Vector
--- @param b Vector
--- @param depth integer
--- @return number used
local function bridge(job, layer, a, b, depth)
    local reach = layer.wire_distance
    if not reach or vect.distance(a, b) <= reach or depth > 4 then return 0 end
    local mid = vect.scale(0.5, vect.add(a, b))
    local direction = vect.normalize(vect.sub(b, a))
    local pos, used = search_spot(job, layer.size, mid, direction)
    if not pos then return used end
    used = used + bridge(job, layer, a, pos, depth + 1)
    -- The poles just added between a and pos may have taken pos.
    if not find_spot(job, layer.size, pos) or find_spot(job, layer.size, pos).x ~= pos.x
        or find_spot(job, layer.size, pos).y ~= pos.y then
        local more
        pos, more = search_spot(job, layer.size, mid, direction)
        used = used + more
        if not pos then return used end
    end
    commit(job, layer, pos)
    return used + bridge(job, layer, pos, b, depth + 1)
end

--- Place one spaced entity near `target`, keeping pole chains within reach.
--- @param job PlannerJob
--- @param layer Layer
--- @param walk {last: Vector|nil}
--- @param target Vector
--- @param direction Vector
--- @return number used
local function place(job, layer, walk, target, direction)
    local pos, used = search_spot(job, layer.size, target, direction)
    if not pos then
        job.plan.skipped = job.plan.skipped + 1
        return used
    end
    if walk.last and layer.wire_distance and vect.distance(walk.last, pos) > layer.wire_distance then
        used = used + bridge(job, layer, walk.last, pos, 0)
        local again, more = search_spot(job, layer.size, target, direction)
        used = used + more
        pos = again
        if not pos then
            job.plan.skipped = job.plan.skipped + 1
            return used
        end
    end
    commit(job, layer, pos, walk.i and math.min(walk.i, #job.frames) or nil)
    walk.last = pos
    return used
end

--- What smart pole placement needs from here.
local SMART_HELPERS = { find_spot = find_spot, search_spot = search_spot, commit = commit, COST = lib.COST }

--- Walk each spaced layer's centre line, placing an entity every `spacing` tiles
--- (or, for poles with smart placement, see smart_poles.lua).
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
            if layer.wire_distance then
                job.plan.chains[layer.idx] = { wires = layer.connect_with_circuit_wires == true, members = {} }
            end
            if layer.smart and layer.wire_distance then
                walk = smart_poles.new_walk()
                job.walk = walk
            else
                walk = { i = 2, travelled = 0, next_at = spacing, last = nil }
                job.walk = walk
                used = used + place(job, layer, walk, geometry.offset_point(frames[1], u_mid), frames[1].t)
            end
        end
        local walked = false
        if walk.smart then
            local u
            u, walked = smart_poles.step(job, walk, band, budget - used, SMART_HELPERS)
            used = used + u
        end
        while not walk.smart and walk.i <= #frames and used < budget do
            local a = geometry.offset_point(frames[walk.i - 1], u_mid)
            local b = geometry.offset_point(frames[walk.i], u_mid)
            local seg = vect.distance(a, b)
            while seg > 0 and walk.travelled + seg >= walk.next_at do
                local k = (walk.next_at - walk.travelled) / seg
                local direction = vect.scale(1 / seg, vect.sub(b, a))
                used = used + place(job, layer, walk, vect.add(a, vect.scale(k, vect.sub(b, a))), direction)
                walk.next_at = walk.next_at + spacing
            end
            walk.travelled = walk.travelled + seg
            walk.i = walk.i + 1
            used = used + lib.COST.frame
        end
        if walked or (not walk.smart and walk.i > #frames) then
            -- Close a pole loop: the last pole must reach the first.
            local chain = job.plan.chains[layer.idx]
            if job.closed and chain and #chain.members > 1 and walk.last then
                local first = job.plan.entities[chain.members[1]].position
                used = used + bridge(job, layer, walk.last, first, 0)
                local last = job.plan.entities[chain.members[#chain.members]].position
                if vect.distance(last, first) > layer.wire_distance then job.plan.gaps = job.plan.gaps + 1 end
            end
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
    bends = stage_bends,
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

--- Rough share of the work done, 0..1, for progress display.
--- @param job PlannerJob
--- @return number
function lib.progress(job)
    local stage = job.stage
    if stage == "done" then return 1 end
    if stage == "sample" then return 0.02 end
    local n = math.max(1, #job.frames)
    if stage == "tangents" or stage == "fill" or stage == "normals" or stage == "bands" then return 0.05 end
    if stage == "bends" then return 0.05 + 0.05 * job.cursor / n end
    if stage == "rasterize" then return 0.1 + 0.7 * job.cursor / n end
    local spaced = math.max(1, #job.spaced)
    local within = job.walk and job.walk.i / n or 0
    return 0.8 + 0.2 * ((job.spaced_cursor - 1) + within) / spaced
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
