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
local paths = require("scripts.build.paths")
local rails = require("scripts.build.rails")

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
--- @field direction integer|nil  # defines.direction (0..15), if not north
--- @field color Color|nil        # lamps
--- @field ammo {name: string, quality: string, count: integer, inventory: string}|nil  # turrets: ammo to request
--- @field belt_type "input"|"output"|nil  # underground belts
--- @field w integer|nil          # footprint when not size x size (pumps)
--- @field h integer|nil
--- @field power boolean|nil      # needs power although its layer doesn't (pumps)
--- @field gate string|nil         # walls: the gate to build instead where a rail crosses
--- @field track {from: Vector, to: Vector}|nil  # rails: the piece's two ends (for the preview)
--- @field rail_layer "elevated"|nil  # signals on elevated track

--- @class PlannedTile
--- @field name string
--- @field x integer
--- @field y integer
--- @field layer integer

--- @class PlanChain
--- @field red boolean          # connect consecutive members with red wire too
--- @field green boolean        # ... and green
--- @field members integer[]    # indices into plan.entities, in order along the curve

--- @class BuildPlan
--- @field entities PlannedEntity[]
--- @field tiles PlannedTile[]
--- @field unsupported integer[]   # layer indices whose type can't be built yet
--- @field skipped integer         # spaced entities that found no free spot
--- @field length number           # curve length in tiles
--- @field counts table<integer, integer>   # placements per layer index (of the layer's own item)
--- @field extra_counts table<integer, table<string, integer>>  # other items per layer (undergrounds, pumps)
--- @field chains table<integer, PlanChain> # pole layers: poles in order, for wiring
--- @field links {a: integer, b: integer, red: boolean, green: boolean}[]  # other wires (indices into entities): land mines
--- @field gaps integer           # consecutive poles out of wire reach (no room for a pole between)
--- @field unpowered integer      # powered entities no smart pole line could reach
--- @field unfed integer          # turrets set to be fed that no belt or pipe line reaches
--- @field warnings Vector[]       # where a bend is tighter than the layers on its inside
--- @field closed boolean        # the curve is a loop (pole chains close too)
--- @field done boolean

--- @class LayerBand
--- @field layer Layer
--- @field lo number
--- @field hi number
--- @field under boolean   # underlay tile band: shares its cells with the other bands

--- @alias PlannerStage "sample"|"tangents"|"fill"|"normals"|"bands"|"bends"|"rails"|"rasterize"|"paths"|"spaced"|"done"

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
--- @field occupied table<string, boolean|"rail">  # cells taken by entities ("rail": by a rail piece)
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

--- Item counts beyond the layer's own item (undergrounds, pumps), for the totals.
--- @param plan BuildPlan
--- @param idx integer
--- @param item string|nil
local function count_extra(plan, idx, item)
    if not item then return end
    plan.extra_counts[idx] = plan.extra_counts[idx] or {}
    plan.extra_counts[idx][item] = (plan.extra_counts[idx][item] or 0) + 1
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
            length = 0, counts = {}, extra_counts = {}, chains = {}, links = {}, gaps = 0, unpowered = 0, unfed = 0, warnings = {},
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
        job.stage, job.cursor = "rails", 1
    end
    return used
end

-- Rails ------------------------------------------------------------------------

--- Wagon length (tiles) for signal spacing: 6 tiles and the 1 tile gap.
lib.WAGON = 7

--- The rail band's centre line, a sample per tile, for fitting.
--- @param job PlannerJob
--- @param band LayerBand
--- @return RailLine
local function rail_line(job, band)
    local u_mid = (band.lo + band.hi) / 2
    local line = { xs = {}, ys = {}, tx = {}, ty = {}, n = 0 }
    local frames = job.frames
    local step = math.max(1, math.floor(1 / lib.SAMPLE_STEP))
    local i = 1
    while i <= #frames do
        local f = frames[i]
        local p = geometry.offset_point(f, u_mid)
        line.n = line.n + 1
        line.xs[line.n], line.ys[line.n] = p.x, p.y
        line.tx[line.n], line.ty[line.n] = f.t.x, f.t.y
        if i < #frames and i + step > #frames then i = #frames else i = i + step end
    end
    return line
end

--- Signals at a joint: on the side for the direction of travel (both ways for
--- tracks used both ways), from the rail end's own signal locations.
--- @param job PlannerJob
--- @param layer Layer
--- @param at TrackEnd  # the joint, facing along the track
local function place_signals(job, layer, at)
    local plan = job.plan
    local placed = false
    local function put(facing)
        local loc = rails.signals(facing).out_signal_location
        if not loc then return end
        local x, y = at.x + loc.x, at.y + loc.y
        local key = cell_key(math.floor(x), math.floor(y))
        -- (Signals on elevated track are up there too: nothing on the ground.)
        -- (Signals stand beside rails, on tiles a rail piece clips.)
        if not layer.elevated then
            if job.occupied[key] and job.occupied[key] ~= "rail" then return end
            job.occupied[key] = true
        end
        table.insert(plan.entities, {
            name = layer.signal_name, quality = "normal", position = { x = x, y = y }, size = 1,
            layer = layer.idx, direction = loc.direction, rail_layer = layer.elevated and "elevated" or nil,
        })
        count_extra(plan, layer.idx, layer.signal_item)
        placed = true
    end
    local travel = layer.direction_of_travel or 1
    if travel >= 0 then put(at.direction) end
    if travel <= 0 then put((at.direction + 8) % 16) end
    return placed
end

--- Lay the fitted track: entities, the tiles they cover, signals, warnings.
--- @param job PlannerJob
--- @param band LayerBand
--- @param fit RailFit
local function lay_track(job, band, fit)
    local plan, layer = job.plan, band.layer
    local travelled, next_signal = 0, (layer.signal_spacing or 0) * lib.WAGON
    -- Elevated track stands on supports, built first.
    if fit.elevated and layer.support_name then
        for _, at in ipairs(rails.supports(fit)) do
            for dx = -1, 0 do for dy = -1, 0 do job.occupied[cell_key(math.floor(at.x) + dx, math.floor(at.y) + dy)] = true end end
            table.insert(plan.entities, {
                name = layer.support_name, quality = "normal", position = { x = at.x, y = at.y }, size = 2,
                layer = layer.idx, direction = at.direction,
            })
            count_extra(plan, layer.idx, layer.support_item)
        end
    end
    for _, piece in ipairs(fit.pieces) do
        -- Only ground-level pieces (and ramps) take up ground.
        if not fit.elevated or piece.ground_name == "rail-ramp" then
            for _, c in ipairs(rails.cells(piece.ground_name or piece.name, piece.direction)) do
                local key = cell_key(math.floor(piece.x + c[1]), math.floor(piece.y + c[2]))
                job.occupied[key] = job.occupied[key] or "rail"
            end
        end
        table.insert(plan.entities, {
            name = piece.name, quality = layer.quality, position = { x = piece.x, y = piece.y }, size = 2,
            layer = layer.idx, direction = piece.direction,
            track = { from = { x = piece.from.x, y = piece.from.y }, to = { x = piece.goal.x, y = piece.goal.y } },
            -- straight ground track across walls already there: gates (build/executor.lua)
            gate = (piece.name == "straight-rail" and piece.direction % 4 == 0 and layer.wall_gates ~= false and layer.gate_name) or nil,
        })
        if piece.ground_name == "rail-ramp" then
            count_extra(plan, layer.idx, layer.ramp_item)
        else
            plan.counts[layer.idx] = (plan.counts[layer.idx] or 0) + ((layer.rail_costs or {})[piece.ground_name or piece.name] or 1)
        end
        travelled = travelled + vect.distance(piece.from, piece.goal)
        if next_signal > 0 and layer.signal_name and travelled >= next_signal then
            if place_signals(job, layer, piece.goal) then
                next_signal = travelled + layer.signal_spacing * lib.WAGON
            end
        end
    end
    for _, off in ipairs(fit.off) do table.insert(plan.warnings, { x = off.x, y = off.y }) end
    if (fit.stalled or (job.closed and not fit.closed)) and fit.loc then table.insert(plan.warnings, { x = fit.loc.x, y = fit.loc.y }) end
    if fit.ramps and not fit.ramped_down and not job.closed and fit.loc then table.insert(plan.warnings, { x = fit.loc.x, y = fit.loc.y }) end
end

--- Fit track to every rail layer, a piece per step.
--- @param job PlannerJob
--- @param budget number
local function stage_rails(job, budget)
    local used = 0
    if not job.rail_queue then
        job.rail_queue = {}
        for b, band in ipairs(job.bands) do
            if registry.type_of(band.layer).placement == "rail" then table.insert(job.rail_queue, b) end
        end
    end
    while used < budget do
        local b = job.rail_queue[job.cursor]
        if not b then break end
        local band = job.bands[b]
        if not job.rail_fit then
            job.rail_line = rail_line(job, band)
            job.rail_fit = rails.new_fit(job.rail_line, {
                elevated = band.layer.elevated == true and band.layer.can_elevate == true,
                ramps = band.layer.ramps ~= false and not job.closed,
            })
        end
        used = used + rails.step(job.rail_fit, job.rail_line, job.closed)
        if job.rail_fit.done then
            lay_track(job, band, job.rail_fit)
            job.rail_fit, job.rail_line = nil, nil
            job.cursor = job.cursor + 1
        end
    end
    if not job.rail_queue[job.cursor] then
        job.rail_queue = nil
        job.stage, job.cursor = "rasterize", 1
    end
    return used
end

local link_to_nearby
local collect_path_cell
local feed_context
local make_entity
local feed_spot

--- How many of a layer's latest band entities a new one looks at for a wire partner.
lib.LINK_WINDOW = 40

--- Band layers with wires (land mines): connect a new entity to the nearest of the
--- layer's recent ones within wire reach. Cells come in order along the curve, so
--- the recent ones are the near ones; the wires form one tree per stretch that is
--- dense enough to reach across.
--- @param job PlannerJob
--- @param layer Layer
--- @param index integer  # in plan.entities
link_to_nearby = function(job, layer, index)
    local plan = job.plan
    job.recent = job.recent or {}
    local recent = job.recent[layer.idx]
    if not recent then
        recent = {}
        job.recent[layer.idx] = recent
    end
    local pos = plan.entities[index].position
    local best, best_d = nil, layer.circuit_distance
    for _, other in ipairs(recent) do
        local d = vect.distance(plan.entities[other].position, pos)
        if d <= best_d then best, best_d = other, d end
    end
    if best then table.insert(plan.links, { a = best, b = index, red = layer.red_wire == true, green = layer.green_wire == true }) end
    table.insert(recent, index)
    if #recent > lib.LINK_WINDOW then table.remove(recent, 1) end
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
    if def.placement ~= "band" then return false end
    if def.keep then
        if not def.keep(layer, x, y) then return false end
    elseif not checkerboard_keep(x, y, layer.checkerboard) then
        return false
    end
    local plan = job.plan
    if def.output ~= "tile" and job.occupied[key] then return false end -- (rails)
    plan.counts[layer.idx] = (plan.counts[layer.idx] or 0) + 1
    if def.output == "tile" then
        table.insert(plan.tiles, { name = layer.name, x = x, y = y, layer = layer.idx })
        return true
    end
    job.occupied[key] = true
    table.insert(plan.entities, {
        name = layer.name, quality = layer.quality,
        position = { x = x + 0.5, y = y + 0.5 }, size = 1, layer = layer.idx,
        gate = (layer.gates ~= false and layer.gate_name) or nil,
    })
    if (layer.red_wire or layer.green_wire) and layer.circuit_distance then link_to_nearby(job, layer, #plan.entities) end
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
            local u, j = geometry.grid_distance(job.frames, job.index, { x = x + 0.5, y = y + 0.5 })
            if u then
                -- The cell's own band first; then an underlay, unless that placed a tile.
                local placed_tile = false
                for _, band in ipairs(bands) do
                    if not band.under and u >= band.lo and u < band.hi then
                        if registry.type_of(band.layer).placement == "path" then
                            collect_path_cell(job, band, x, y, key, u, j)
                        else
                            placed_tile = emit_cell(job, band.layer, x, y, key)
                        end
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
        job.stage, job.cursor = "paths", 1
    end
    return used
end

--- Path layers (belts, pipes): a cell of the band belongs to line k when it lies in
--- that line's one-cell sub-band; cells in the gaps between lines stay empty.
--- @param job PlannerJob
--- @param band LayerBand
--- @param x integer
--- @param y integer
--- @param key string
--- @param u number
--- @param j integer
collect_path_cell = function(job, band, x, y, key, u, j)
    local layer = band.layer
    local step = 1 + (layer.line_gap or 0)
    local rel = u - band.lo
    local k = math.floor(rel / step)
    if rel - k * step >= 1 or k >= (layer.lines or 1) then return end
    if job.occupied[key] then return end -- (rails)
    job.occupied[key] = true
    job.path_cells = job.path_cells or {}
    local by_line = job.path_cells[layer.idx]
    if not by_line then
        by_line = {}
        job.path_cells[layer.idx] = by_line
    end
    local cells = by_line[k + 1]
    if not cells then
        cells = {}
        by_line[k + 1] = cells
    end
    cells[#cells + 1] = { x = x, y = y, j = j }
end


-- Path layers are built in two phases, a line per step: first every line is
-- routed (ordered into segments, diagonal steps joined through corner cells),
-- then the routes become entities. A belt line may take a corner cell from
-- another line of its layer (on the inside of a bend the bands get squeezed, and
-- which side is inside changes along the curve); the taken cell is locked to it,
-- and the other line is routed again (a few times at most).

lib.MAX_REROUTES = 4

--- Pieces of a line shorter than this are dropped when the line has a stretch at
--- least five times as long.
lib.MIN_SCRAP = 4

--- Route one line: its current cells as continuous segments.
--- @param job PlannerJob
--- @param item {idx: integer, k: integer, line: string}
--- @return number used
local function route_path_line(job, item)
    local layer = job.layers[item.idx]
    local line = item.line
    local pipes = registry.type_of(layer).name == "pipe"
    local cells = {}
    for key, c in pairs(job.line_cells[line]) do cells[#cells + 1] = c end
    table.sort(cells, function(a, b)
        if a.j ~= b.j then return a.j < b.j end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    -- A corner cell may be free (and, for pipes, not touch another pipe line), or
    -- (belts) belong to another line of this layer, unless it was taken already.
    local function usable(x, y)
        local key = cell_key(x, y)
        local owner = job.line_of[key]
        local rank = 1
        if job.occupied[key] then
            if pipes or not owner or owner == line or job.locked[key]
                or job.line_layer[owner] ~= item.idx then
                return false
            end
            rank = 2
        end
        if pipes then
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local other = job.line_of[cell_key(x + d[1], y + d[2])]
                if other and other ~= line then return false end
            end
        end
        return rank
    end
    local function use(x, y)
        local key = cell_key(x, y)
        local owner = job.line_of[key]
        local c = { x = x, y = y, j = 0 }
        if owner and owner ~= line then
            c.j = job.line_cells[owner][key].j
            job.line_cells[owner][key] = nil
            job.locked[key] = true
            -- That line has to go round the cell now.
            if job.routes[owner] and (job.reroutes[owner] or 0) < lib.MAX_REROUTES then
                job.reroutes[owner] = (job.reroutes[owner] or 0) + 1
                job.routes[owner] = nil
                table.insert(job.path_queue, { idx = job.line_layer[owner], line = owner, phase = "route" })
            end
        end
        job.occupied[key] = true
        job.line_of[key] = line
        job.line_cells[line][key] = c
        if not pipes then job.belt_cells[key] = true end
    end
    local joined = {}
    for _, segment in ipairs(paths.segments(cells, job.closed and #job.frames or nil)) do
        for _, piece in ipairs(paths.join_corners(segment, usable, use)) do joined[#joined + 1] = piece end
    end
    if job.closed then
        -- Close a loop whose ends meet only diagonally.
        for _, segment in ipairs(joined) do
            local first, last = segment[1], segment[#segment]
            if #segment >= 3 and math.abs(first.x - last.x) == 1 and math.abs(first.y - last.y) == 1 then
                for _, corner in ipairs({ { x = first.x, y = last.y }, { x = last.x, y = first.y } }) do
                    if math.abs(segment[#segment].x - first.x) + math.abs(segment[#segment].y - first.y) == 2
                        and usable(corner.x, corner.y) then
                        use(corner.x, corner.y)
                        segment[#segment + 1] = { x = corner.x, y = corner.y, j = last.j }
                    end
                end
            end
        end
    end
    job.routes[line] = joined
    return #cells * lib.COST.place
end

--- Turn one routed line into belts or pipes (and undergrounds, pumps).
--- @param job PlannerJob
--- @param item {idx: integer, line: string}
--- @return number used
local function emit_path_line(job, item)
    local plan = job.plan
    local layer = job.layers[item.idx]
    local pipes = registry.type_of(layer).name == "pipe"
    local used = 0
    local route = job.routes[item.line] or {}
    -- Scraps a few cells long beside a long stretch of the line (left over where a
    -- loop's ends meet, or at a tight corner) would be belts going nowhere.
    local longest = 0
    for _, segment in ipairs(route) do longest = math.max(longest, #segment) end
    for _, segment in ipairs(route) do
      if #segment >= lib.MIN_SCRAP or longest < 5 * lib.MIN_SCRAP then
        -- Cells taken by another line after this route was made are left out.
        local kept, current = {}, {}
        for _, c in ipairs(segment) do
            if job.line_of[cell_key(c.x, c.y)] == item.line then
                current[#current + 1] = c
            elseif #current > 0 then
                kept[#kept + 1] = current
                current = {}
            end
        end
        if #current > 0 then kept[#kept + 1] = current end
        for _, part in ipairs(kept) do
            used = used + #part * lib.COST.place
            if #part >= 2 then
                if layer.flow == "backward" then
                    local reversed = {}
                    for i = #part, 1, -1 do reversed[#reversed + 1] = part[i] end
                    part = reversed
                end
                local first, last = part[1], part[#part]
                local loop = job.closed and math.abs(first.x - last.x) + math.abs(first.y - last.y) == 1
                local pieces, missing = paths.pieces(part, {
                    undergrounds = layer.undergrounds and layer.underground_name and layer.underground_distance or nil,
                    pipes = pipes,
                    pump_spacing = pipes and layer.pumps and layer.pump_name and layer.pump_spacing or nil,
                    loop = loop,
                    taken = not pipes and function(x, y) return job.belt_cells[cell_key(x, y)] == true end or nil,
                })
                plan.skipped = plan.skipped + missing
                for _, piece in ipairs(pieces) do
                    local entity = {
                        name = layer.name, quality = layer.quality, position = { x = piece.x, y = piece.y },
                        size = 1, layer = layer.idx,
                    }
                    -- Turrets placed later feed from these lines (build/feeds.lua).
                    local cell = cell_key(math.floor(piece.x), math.floor(piece.y))
                    if pipes and piece.kind ~= "pump" then
                        job.feed_pipes[cell] = item.line
                        job.feed_pipe_names[item.line] = layer.name
                    elseif not pipes and piece.kind == "line" then
                        job.feed_belts[cell] = true
                    end
                    if piece.kind == "line" then
                        if not pipes then entity.direction = piece.direction end
                        plan.counts[layer.idx] = (plan.counts[layer.idx] or 0) + 1
                    elseif piece.kind == "pump" then
                        entity.name, entity.size, entity.w, entity.h = layer.pump_name, 2, piece.w, piece.h
                        entity.direction, entity.power = piece.direction, true
                        count_extra(plan, layer.idx, layer.pump_item)
                    else
                        entity.name, entity.direction = layer.underground_name, piece.direction
                        if not pipes then entity.belt_type = piece.kind == "underground_in" and "input" or "output" end
                        count_extra(plan, layer.idx, layer.underground_item)
                    end
                    table.insert(plan.entities, entity)
                end
            end
        end
      end
    end
    return used
end

--- Path layers: route every line, then make the entities, a line per step.
--- @param job PlannerJob
--- @param budget number
local function stage_paths(job, budget)
    local used = 0
    if not job.path_queue then
        job.path_queue, job.line_cells, job.line_of, job.line_layer = {}, {}, {}, {}
        job.feed_pipes, job.feed_pipe_names, job.feed_belts = {}, {}, {}
        job.belt_cells, job.locked, job.routes, job.reroutes = {}, {}, {}, {}
        local emits = {}
        for _, band in ipairs(job.bands) do
            local lines = job.path_cells and job.path_cells[band.layer.idx]
            if lines then
                local belts = registry.type_of(band.layer).name == "belt"
                for k = 1, band.layer.lines or 1 do
                    if lines[k] then
                        local line = band.layer.idx .. ":" .. k
                        job.line_layer[line] = band.layer.idx
                        job.line_cells[line] = {}
                        for _, c in ipairs(lines[k]) do
                            local key = cell_key(c.x, c.y)
                            job.line_cells[line][key] = c
                            job.line_of[key] = line
                            if belts then job.belt_cells[key] = true end
                        end
                        table.insert(job.path_queue, { idx = band.layer.idx, line = line, phase = "route" })
                        table.insert(emits, { idx = band.layer.idx, line = line, phase = "emit" })
                    end
                end
            end
        end
        job.path_emits = emits
        job.path_cells = nil
    end
    while used < budget do
        local item = job.path_queue[job.cursor]
        if not item then
            if not job.path_emits then break end
            -- Routing done (re-routes included): now the entities.
            for _, e in ipairs(job.path_emits) do table.insert(job.path_queue, e) end
            job.path_emits = nil
        elseif item.phase == "route" then
            if not job.routes[item.line] then used = used + route_path_line(job, item) end
            job.cursor = job.cursor + 1
        else
            used = used + emit_path_line(job, item) + 1
            job.cursor = job.cursor + 1
        end
    end
    if not job.path_queue[job.cursor] and not job.path_emits then
        job.path_queue, job.line_cells, job.line_of, job.line_layer = nil, nil, nil, nil
        job.belt_cells, job.locked, job.routes, job.reroutes = nil, nil, nil, nil
        job.stage, job.cursor = "spaced", 1
    end
    return used
end

--- The free grid position nearest to `target` for an entity of `size`, if any.
--- @param job PlannerJob
--- @param size integer
--- @param target Vector
--- @return Vector|nil
local function free_spots(job, size, target)
    local occupied = job.occupied
    local xa, xb = snap_candidates(target.x, size)
    local ya, yb = snap_candidates(target.y, size)
    local candidates = { { x = xa, y = ya }, { x = xb, y = ya }, { x = xa, y = yb }, { x = xb, y = yb } }
    table.sort(candidates, function(p, q) return geometry.dist2(p, target) < geometry.dist2(q, target) end)
    local out = {}
    for _, pos in ipairs(candidates) do
        local x0, y0 = footprint_origin(pos, size)
        local free = true
        for dx = 0, size - 1 do
            for dy = 0, size - 1 do
                if occupied[cell_key(x0 + dx, y0 + dy)] then free = false end
            end
        end
        if free then out[#out + 1] = pos end
    end
    return out
end

--- The free grid position nearest to `target` for an entity of `size`, if any.
--- @param job PlannerJob
--- @param size integer
--- @param target Vector
--- @return Vector|nil
local function find_spot(job, size, target)
    return free_spots(job, size, target)[1]
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

--- @class FeedContext
--- @field occupied fun(x: integer, y: integer): boolean
--- @field belt fun(x: integer, y: integer): boolean         # a belt of a belt layer
--- @field pipe_line fun(x: integer, y: integer): string|nil # the pipe line there, if any
--- @field add fun(spec: {name: string, x: integer, y: integer, direction: integer|nil, power: boolean|nil, item: string|nil})
--- @field add_pipe fun(x: integer, y: integer)             # a stub joining the line it touches
--- @field unfed fun()

--- What a turret layer's attach hook may look at and add (its feed).
--- @param job PlannerJob
--- @param layer Layer
--- @return FeedContext
feed_context = function(job, layer)
    local plan = job.plan
    local stub_line
    local function add(spec)
        local key = cell_key(spec.x, spec.y)
        job.occupied[key] = true
        table.insert(plan.entities, {
            name = spec.name, quality = "normal", position = { x = spec.x + 0.5, y = spec.y + 0.5 }, size = 1,
            layer = layer.idx, direction = spec.direction, power = spec.power,
        })
        count_extra(plan, layer.idx, spec.item)
    end
    return {
        occupied = function(x, y) return job.occupied[cell_key(x, y)] ~= nil end,
        belt = function(x, y) return (job.feed_belts or {})[cell_key(x, y)] == true end,
        pipe_line = function(x, y) return (job.feed_pipes or {})[cell_key(x, y)] end,
        add = add,
        add_pipe = function(x, y)
            -- The stub's pipe is the pipe of the line it ends at.
            local line
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                line = line or (job.feed_pipes or {})[cell_key(x + d[1], y + d[2])]
            end
            stub_line = line or stub_line
            local name = stub_line and job.feed_pipe_names[stub_line] or "pipe"
            add({ name = name, x = x, y = y, item = name })
            if job.feed_pipes and stub_line then job.feed_pipes[cell_key(x, y)] = stub_line end
        end,
        unfed = function() plan.unfed = plan.unfed + 1 end,
    }
end

--- A planned entity for a spaced layer at `pos`, decorated (direction, colour, ...).
--- @param job PlannerJob
--- @param layer Layer
--- @param pos Vector
--- @param frame integer|nil
--- @param arc number|nil
--- @return PlannedEntity
make_entity = function(job, layer, pos, frame, arc)
    local entity = {
        name = layer.name, quality = layer.quality, position = pos, size = layer.size, layer = layer.idx, frame = frame,
    }
    local def = registry.type_of(layer)
    if def.decorate then
        local n = frame and job.frames[frame] and job.frames[frame].n or { x = 0, y = -1 }
        local side = layer.idx < 0 and -1 or 1
        def.decorate(layer, entity, { outward = { x = side * n.x, y = side * n.y }, arc = arc })
    end
    return entity
end

--- For turrets with a feed: the nearest spot (also shifted along the curve, as
--- search_spot) where the feed fits.
--- @return Vector|nil, number used
feed_spot = function(job, layer, target, direction, frame, arc)
    local def = registry.type_of(layer)
    local size = layer.size
    local used = 0
    local function cells(pos, taken)
        local x0, y0 = footprint_origin(pos, size)
        for dx = 0, size - 1 do
            for dy = 0, size - 1 do job.occupied[cell_key(x0 + dx, y0 + dy)] = taken or nil end
        end
    end
    for _, shift in ipairs(SHIFTS) do
        for _, pos in ipairs(free_spots(job, size, vect.add(target, vect.scale(shift, direction)))) do
            used = used + lib.COST.place * 4
            cells(pos, true)
            local ok = def.can_attach(layer, make_entity(job, layer, pos, frame, arc), feed_context(job, layer))
            cells(pos, false)
            if ok then return pos, used end
        end
    end
    return nil, used
end

--- Claim a spot and add the entity to the plan.
--- @param job PlannerJob
--- @param layer Layer
--- @param pos Vector
--- @param frame integer|nil  # the curve sample it was placed at
--- @param arc number|nil      # distance along the curve it was aimed at
local function commit(job, layer, pos, frame, arc)
    local size = layer.size
    local x0, y0 = footprint_origin(pos, size)
    for dx = 0, size - 1 do
        for dy = 0, size - 1 do
            job.occupied[cell_key(x0 + dx, y0 + dy)] = true
        end
    end
    local plan = job.plan
    local def = registry.type_of(layer)
    local entity = make_entity(job, layer, pos, frame, arc)
    table.insert(plan.entities, entity)
    plan.counts[layer.idx] = (plan.counts[layer.idx] or 0) + 1
    if def.attach then def.attach(layer, entity, feed_context(job, layer)) end
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
    local def = registry.type_of(layer)
    local pos, used
    if def.wants_feed and def.wants_feed(layer) then
        -- Turrets with a feed: a spot where the inserter or pipe stub fits, if any.
        pos, used = feed_spot(job, layer, target, direction, walk.i and math.min(walk.i, #job.frames) or nil, walk.aim)
        if not pos then
            local more
            pos, more = search_spot(job, layer.size, target, direction)
            used = used + more
        end
    else
        pos, used = search_spot(job, layer.size, target, direction)
    end
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
    commit(job, layer, pos, walk.i and math.min(walk.i, #job.frames) or nil, walk.aim)
    walk.last = pos
    return used
end

--- What smart pole placement needs from here.
--- Free or take the cells of an entity of `size` at `pos`.
--- @param job PlannerJob
--- @param size integer
--- @param pos Vector
--- @param taken boolean
local function set_cells(job, size, pos, taken)
    local x0, y0 = footprint_origin(pos, size)
    for dx = 0, size - 1 do
        for dy = 0, size - 1 do
            job.occupied[cell_key(x0 + dx, y0 + dy)] = taken or nil
        end
    end
end

local SMART_HELPERS = { find_spot = find_spot, search_spot = search_spot, commit = commit, set_cells = set_cells, COST = lib.COST }

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
                job.plan.chains[layer.idx] = { red = layer.red_wire == true, green = layer.green_wire == true, members = {} }
            end
            if layer.smart and layer.wire_distance then
                walk = smart_poles.new_walk()
                job.walk = walk
            else
                walk = { i = 2, travelled = 0, next_at = spacing, last = nil }
                job.walk = walk
                walk.aim = 0
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
                walk.aim = walk.next_at
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
    rails = stage_rails,
    rasterize = stage_rasterize,
    paths = stage_paths,
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
    if stage == "paths" then return 0.8 end
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
