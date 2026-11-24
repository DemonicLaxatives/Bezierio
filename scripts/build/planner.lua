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
---
--- The stages live in build/plan/ (curve, bands, track, raster, lines, joins,
--- spaced; shared pieces in plan/common.lua); this module makes the job and runs
--- them in order.
local curve_lib = require("scripts.curve.curve")
local C = require("scripts.build.plan.common")
local curve_stages = require("scripts.build.plan.curve")
local bands = require("scripts.build.plan.bands")
local track = require("scripts.build.plan.track")
local raster = require("scripts.build.plan.raster")
local lines = require("scripts.build.plan.lines")
local joins = require("scripts.build.plan.joins")
local spaced = require("scripts.build.plan.spaced")

local lib = {}

-- (the stages' settings, here for callers and tests)
lib.SAMPLE_STEP = C.SAMPLE_STEP
lib.END_PROBE_STEP = C.END_PROBE_STEP
lib.COST = C.COST
lib.WAGON = track.WAGON
lib.LINK_WINDOW = raster.LINK_WINDOW
lib.MAX_REROUTES = lines.MAX_REROUTES
lib.MIN_SCRAP = lines.MIN_SCRAP
lib.bands = bands.bands

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
--- @field priority_targets string[]|nil  # turrets: what to shoot first, in order
--- @field ignore_unprioritised boolean|nil  # turrets: shoot nothing else

--- @class PlannedTile
--- @field name string
--- @field x integer
--- @field y integer
--- @field layer integer

--- @class PlanMark
--- @field x number      # entity centre
--- @field y number
--- @field size number
--- @field w number|nil     # footprint, when not size x size
--- @field h number|nil
--- @field icon string|nil  # "ammo" or "fluid" (unfed)

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
--- @field unpowered_at PlanMark[]  # where the unpowered ones are
--- @field unfed_at PlanMark[]      # ... and the unfed ones
--- @field warnings Vector[]       # where a bend is tighter than the layers on its inside
--- @field closed boolean        # the curve is a loop (pole chains close too)
--- @field done boolean

--- @class LayerBand
--- @field layer Layer
--- @field lo number
--- @field hi number
--- @field under boolean   # underlay tile band: shares its cells with the other bands

--- @alias PlannerStage "sample"|"tangents"|"fill"|"normals"|"bands"|"bends"|"rails"|"rasterize"|"paths"|"joins"|"spaced"|"done"

--- @class SpacedWalk
--- @field i integer              # next frame
--- @field travelled number       # along the layer's line so far
--- @field next_at number         # where the next entity goes
--- @field aim number             # where the current one was aimed
--- @field last Vector|nil        # the previous entity
--- @field first Vector|nil       # where the first one was aimed (closed loops: the seam)
--- @field centre number|nil      # along the centre line so far

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
--- @field walk SpacedWalk|SmartWalk|nil
--- @field outer_plus number              # outermost built distance on the + side (grid units)
--- @field outer_minus number             # ... on the - side
--- @field last_warning Vector|nil
--- @field join_cells {x: integer, y: integer, band: LayerBand}[]|nil  # cells of layers that join corners, in order
--- @field join_at table<string, integer>|nil  # cell -> layer index, for those layers
--- @field tiled table<string, true>|nil       # cells with a (non-underlay) tile
--- @field plan BuildPlan

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
            unpowered_at = {}, unfed_at = {},
            closed = curve_lib.is_closed(curve),
            done = sampler == nil,
        },
    }
end

local STAGES = {
    sample = curve_stages.stage_sample,
    tangents = curve_stages.stage_tangents,
    fill = curve_stages.stage_fill,
    normals = curve_stages.stage_normals,
    bands = bands.stage_bands,
    bends = bands.stage_bends,
    rails = track.stage_rails,
    rasterize = raster.stage_rasterize,
    paths = lines.stage_paths,
    joins = joins.stage_joins,
    spaced = spaced.stage_spaced,
}

--- What a finished job keeps: the rest is working data.
lib.KEEP_WHEN_DONE = { stage = true, layers = true, closed = true, points = true, plan = true }

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
        -- Working data is no longer needed (it would stay in the save); keep
        -- `points` for drawing the curve.
        for field in pairs(job) do
            if not lib.KEEP_WHEN_DONE[field] then job[field] = nil end
        end
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
    if stage == "rails" then return 0.1 end
    if stage == "rasterize" then return 0.1 + 0.7 * job.cursor / n end
    if stage == "paths" or stage == "joins" then return 0.8 end
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

