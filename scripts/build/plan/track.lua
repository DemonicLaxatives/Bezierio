--- Planner: the rails stage, rail track fitted along rail layers' bands
--- (build/rails.lua), with signals, supports and gates.
local vect = require("scripts.vector_math")
local geometry = require("scripts.build.geometry")
local registry = require("scripts.layers.registry")
local rails = require("scripts.build.rails")
local C = require("scripts.build.plan.common")
local cell_key, count_extra = C.cell_key, C.count_extra

local lib = {}

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
    local step = math.max(1, math.floor(1 / C.SAMPLE_STEP))
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
--- @param elevated boolean  # the track is elevated (signals up there too)
local function place_signals(job, layer, at, elevated)
    local plan = job.plan
    local placed = false
    local function put(facing)
        local loc = rails.signals(facing).out_signal_location
        if not loc then return end
        local x, y = at.x + loc.x, at.y + loc.y
        local key = cell_key(math.floor(x), math.floor(y))
        -- (Signals on elevated track are up there too: nothing on the ground.)
        -- (Signals stand beside rails, on tiles a rail piece clips.)
        if not elevated then
            if job.occupied[key] and job.occupied[key] ~= "rail" then return end
            job.occupied[key] = true
        end
        table.insert(plan.entities, {
            name = layer.signal_name, quality = "normal", position = { x = x, y = y }, size = 1,
            layer = layer.idx, direction = loc.direction, rail_layer = elevated and "elevated" or nil,
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
    -- Only ground-level pieces (and ramps) take up ground, claimed first so
    -- supports keep off ramps.
    for _, piece in ipairs(fit.pieces) do
        if not fit.elevated or piece.ground_name == "rail-ramp" then
            for _, c in ipairs(rails.cells(piece.ground_name or piece.name, piece.direction)) do
                local key = cell_key(math.floor(piece.x + c[1]), math.floor(piece.y + c[2]))
                job.occupied[key] = job.occupied[key] or "rail"
            end
        end
    end
    -- Elevated track stands on supports, built first. Each takes the tiles its
    -- turned collision box covers (wider than the track), where nothing else
    -- may be: another track, a ramp or an earlier support.
    if fit.elevated and layer.support_name then
        local function try(at)
            local cells = rails.support_cells(at.direction)
            for _, c in ipairs(cells) do
                if job.occupied[cell_key(at.x + c[1], at.y + c[2])] then return false end
            end
            for _, c in ipairs(cells) do job.occupied[cell_key(at.x + c[1], at.y + c[2])] = true end
            return true
        end
        local supports, missing = rails.supports(fit, try)
        for _, at in ipairs(supports) do
            table.insert(plan.entities, {
                name = layer.support_name, quality = "normal", position = { x = at.x, y = at.y }, size = 4,
                layer = layer.idx, direction = at.direction % 8, arrow = false,
            })
            count_extra(plan, layer.idx, layer.support_item)
        end
        for _, at in ipairs(missing) do table.insert(plan.warnings, { x = at.x, y = at.y }) end
    end
    for k, piece in ipairs(fit.pieces) do
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
        -- (No signal at either end of a ramp: the game doesn't let a player place
        -- one there, top or foot, even with track on both sides. Such a signal
        -- moves on to the next joint, like one whose spot is taken.)
        local next_piece = fit.pieces[k + 1]
        local at_ramp = piece.ground_name == "rail-ramp" or (next_piece and next_piece.ground_name == "rail-ramp")
        if next_signal > 0 and layer.signal_name and travelled >= next_signal and not at_ramp then
            if place_signals(job, layer, piece.goal, fit.elevated) then
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
            used = used + rails.round_line(job.rail_line)
            job.rail_fit = rails.new_fit(job.rail_line, {
                elevated = band.layer.elevated == true and band.layer.can_elevate == true,
                ramps = band.layer.ramps ~= false and not job.closed,
                smoothing = band.layer.smoothing,
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

lib.stage_rails = stage_rails

return lib
