--- Planner: the spaced stage, entities every `spacing` along a band's centre
--- line (poles, turrets, lamps, ...; smart poles in build/smart_poles.lua),
--- with their feeds.
local vect = require("scripts.vector_math")
local geometry = require("scripts.build.geometry")
local registry = require("scripts.layers.registry")
local common = require("scripts.layers.common")
local smart_poles = require("scripts.build.smart_poles")
local C = require("scripts.build.plan.common")
local cell_key, count_extra, snap_candidates, footprint_origin = C.cell_key, C.count_extra, C.snap_candidates, C.footprint_origin

local lib = {}

local feed_context
local make_entity
local feed_spot

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
        used = used + C.COST.place
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
--- @field unfed fun(entity: PlannedEntity, icon: "ammo"|"fluid")  # the turret gets no feed

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
        unfed = function(entity, icon)
            plan.unfed = plan.unfed + 1
            table.insert(plan.unfed_at, { x = entity.position.x, y = entity.position.y, size = entity.size, icon = icon })
        end,
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
    common.fit_footprint(layer, entity)
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
            used = used + C.COST.place * 4
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

local SMART_HELPERS = { find_spot = find_spot, search_spot = search_spot, commit = commit, set_cells = set_cells, COST = C.COST }

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
                walk = { i = 2, travelled = 0, next_at = spacing, last = nil, centre = 0 }
                job.walk = walk
                walk.aim = 0
                walk.first = geometry.offset_point(frames[1], u_mid)
                used = used + place(job, layer, walk, walk.first, frames[1].t)
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
            -- A loop ends where it started: in its second half, a spot within half a
            -- spacing of the first entity is left out (the seam gets 0.5 to 1.5
            -- spacings, not an entity a tile from the first one).
            local seam = job.closed and walk.first and walk.centre > job.plan.length / 2
            while seg > 0 and walk.travelled + seg >= walk.next_at do
                local k = (walk.next_at - walk.travelled) / seg
                local direction = vect.scale(1 / seg, vect.sub(b, a))
                local target = vect.add(a, vect.scale(k, vect.sub(b, a)))
                walk.aim = walk.next_at
                if not (seam and vect.distance(target, walk.first) < spacing / 2) then
                    used = used + place(job, layer, walk, target, direction)
                end
                walk.next_at = walk.next_at + spacing
            end
            walk.travelled = walk.travelled + seg
            walk.centre = (walk.centre or 0) + vect.distance(frames[walk.i - 1].p, frames[walk.i].p)
            walk.i = walk.i + 1
            used = used + C.COST.frame
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

lib.stage_spaced = stage_spaced

return lib
