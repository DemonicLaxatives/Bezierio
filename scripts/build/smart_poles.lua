--- Smart pole placement, like dragging poles in the game: each pole goes as far
--- from the previous one as the wire reach allows, but earlier where that's needed
--- so that every powered entity in the plan (layer.needs_power) is inside some
--- pole's supply area.
---
--- Runs as part of the planner's spaced stage, a budgeted amount per call, in
--- phases kept in `walk`:
---   line       the band's centre line as a polyline with arc lengths
---   consumers  the powered entities, each projected onto the line (arc length)
---   poles      the greedy walk: one pole per iteration
---   refine     tidy up what greed left: drop poles nothing needs, then slide each
---              pole towards the middle between its neighbours (the greedy walk puts
---              a pole at full reach and then, when a powered entity can only be
---              reached from a short stretch just past it, another one close by)
local vect = require("scripts.vector_math")
local geometry = require("scripts.build.geometry")

local lib = {}

local refine

--- Distance (tiles) between the positions tried for one pole.
lib.STEP = 0.5

--- A consumer counts as powered when its footprint, shrunk by this much on each
--- side (collision boxes are smaller than the footprint), overlaps the pole's
--- supply area.
lib.MARGIN = 0.3

--- @class SmartConsumer
--- @field x number
--- @field y number
--- @field half number     # half the footprint, minus the margin
--- @field s number        # arc length of its projection onto the centre line
--- @field done boolean    # powered, or given up on
--- @field powered boolean

--- @class SmartWalk
--- @field smart true
--- @field phase "line"|"consumers"|"poles"|"done"
--- @field i integer
--- @field xs number[]
--- @field ys number[]
--- @field arc number[]
--- @field consumers SmartConsumer[]
--- @field k integer              # first consumer that may still need power
--- @field reach_window number    # how far (arc length) a pole can reach a consumer
--- @field last Vector|nil        # the previous pole
--- @field last_s number          # ... and where along the line it was aimed

--- @return SmartWalk
function lib.new_walk()
    return { smart = true, phase = "line", i = 1, xs = {}, ys = {}, arc = {}, consumers = {}, k = 1, reach_window = 0, last = nil, last_s = 0 }
end

--- Point on the centre line at arc length s, and the direction there.
--- @param walk SmartWalk
--- @param s number
--- @return Vector, Vector
local function point_at(walk, s)
    local arc, xs, ys = walk.arc, walk.xs, walk.ys
    local n = #arc
    if s <= 0 or n < 2 then
        local d = n >= 2 and vect.normalize({ x = xs[2] - xs[1], y = ys[2] - ys[1] }) or { x = 1, y = 0 }
        return { x = xs[1], y = ys[1] }, d
    end
    if s >= arc[n] then
        return { x = xs[n], y = ys[n] }, vect.normalize({ x = xs[n] - xs[n - 1], y = ys[n] - ys[n - 1] })
    end
    local lo, hi = 1, n
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) / 2)
        if arc[mid] <= s then lo = mid else hi = mid end
    end
    local span = arc[hi] - arc[lo]
    local k = span > 0 and (s - arc[lo]) / span or 0
    local d = { x = xs[hi] - xs[lo], y = ys[hi] - ys[lo] }
    return { x = xs[lo] + k * d.x, y = ys[lo] + k * d.y }, vect.normalize(d)
end

--- @param pos Vector
--- @param c SmartConsumer
--- @param r number  # supply area distance
local function covers(pos, c, r)
    local reach = r + c.half
    return math.abs(c.x - pos.x) < reach and math.abs(c.y - pos.y) < reach
end

--- Whether a pole at `pos`, aimed at arc length `s`, powers what it must: `first`
--- (if given) and every consumer in `behind` that lies before `s` (the poles after
--- it will be further along).
local function covers_needed(pos, s, first, behind, r)
    if first and not covers(pos, first, r) then return false end
    for _, c in ipairs(behind) do
        if c.s >= s then break end
        if not covers(pos, c, r) then return false end
    end
    return true
end

--- The farthest free spot in (from, to] (arc length) within wire reach of the
--- previous pole that powers what it must (see covers_needed).
--- @return Vector|nil pos, number s, number used
local function farthest_spot(job, walk, layer, h, from, to, first, behind)
    local used, r = 0, layer.reach or 0
    local s = to
    while s > from + 1e-9 do
        local target = point_at(walk, s)
        local pos = h.find_spot(job, layer.size, target)
        used = used + h.COST.place
        if pos and (not walk.last or vect.distance(walk.last, pos) <= layer.wire_distance)
            and covers_needed(pos, s, first, behind, r) then
            return pos, s, used
        end
        s = s - lib.STEP
    end
    return nil, from, used
end

--- Commit a pole and mark the consumers it powers.
local function put(job, walk, layer, h, pos, s)
    h.commit(job, layer, pos)
    walk.pole_s = walk.pole_s or {}
    table.insert(walk.pole_s, s)
    walk.last, walk.last_s = pos, s
    local r, consumers = layer.reach or 0, walk.consumers
    for idx = walk.k, #consumers do
        local c = consumers[idx]
        if c.s > s + walk.reach_window then break end
        if not c.powered and c.s >= s - walk.reach_window and covers(pos, c, r) then
            c.done, c.powered = true, true
        end
    end
    while consumers[walk.k] and consumers[walk.k].done do walk.k = walk.k + 1 end
end

--- One greedy step: place the next pole (or give up on a consumer no pole can power).
--- @return number used, boolean finished
local function next_pole(job, walk, layer, h)
    local total = walk.arc[#walk.arc]
    local consumers, r = walk.consumers, layer.reach or 0
    local from = walk.last_s
    local to = math.min(from + layer.wire_distance, total)
    local first = consumers[walk.k]

    if from >= total - lib.STEP and not first then return 0, true end

    -- Consumers this pole has to power: the first unpowered one if it comes before
    -- (or just after) the farthest reach, and every other unpowered one before the pole.
    local due = first and first.s <= to + r + first.half
    if due then
        local behind = {}
        for idx = walk.k + 1, #consumers do
            local c = consumers[idx]
            if c.s >= to then break end
            if not c.done then table.insert(behind, c) end
        end
        local pos, s, used = farthest_spot(job, walk, layer, h, from, to, first, behind)
        if pos then
            put(job, walk, layer, h, pos, s)
            return used, false
        end
        if #behind > 0 then
            local more
            pos, s, more = farthest_spot(job, walk, layer, h, from, to, first, {})
            used = used + more
            if pos then
                put(job, walk, layer, h, pos, s)
                return used, false
            end
        end
        if first.s <= to then
            -- No pole within reach of the previous one can power it. (A later pole
            -- may still happen to; counted at the end.)
            first.done = true
            while consumers[walk.k] and consumers[walk.k].done do walk.k = walk.k + 1 end
            return used, false
        end
    end

    if not due and to >= total - 1e-9 and job.closed then return 0, true end
    local pos, s, used = farthest_spot(job, walk, layer, h, from, to, nil, {})
    if pos then
        put(job, walk, layer, h, pos, s)
        return used, false
    end
    -- Nothing free within wire reach: place the farthest free spot anyway (a gap,
    -- counted by commit), or skip ahead.
    local target, direction = point_at(walk, to)
    local spot, more = h.search_spot(job, layer.size, target, direction)
    used = used + more
    if spot then
        put(job, walk, layer, h, spot, to)
    else
        job.plan.skipped = job.plan.skipped + 1
        walk.last_s = to
    end
    return used, false
end

-- Refine ------------------------------------------------------------------------

--- Index of the first consumer with s >= `s` (consumers are sorted by s).
local function lower_bound(consumers, s)
    local lo, hi = 1, #consumers + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if consumers[mid].s < s then lo = mid + 1 else hi = mid end
    end
    return lo
end

--- Call fn(c) for every consumer a pole aimed between s1 and s2 could power.
local function near(walk, s1, s2, fn)
    local consumers, w = walk.consumers, walk.reach_window
    for idx = lower_bound(consumers, math.min(s1, s2) - w), #consumers do
        local c = consumers[idx]
        if c.s > math.max(s1, s2) + w then break end
        fn(c)
    end
end

--- Neighbours of pole i that are still there.
local function neighbours(walk, i, n)
    local j, k = i - 1, i + 1
    while j >= 1 and walk.removed[j] do j = j - 1 end
    while k <= n and walk.removed[k] do k = k + 1 end
    return j >= 1 and j or nil, k <= n and k or nil
end

--- Whether every consumer that only pole i powers is powered from `pos` too.
local function keeps_sole(walk, s_old, s_new, old, pos, r)
    local ok = true
    near(walk, s_old, s_new, function(c)
        if ok and c.cover == 1 and covers(old, c, r) and not covers(pos, c, r) then ok = false end
    end)
    return ok
end

--- Drop pole i if nothing needs it.
local function try_remove(job, walk, layer, h, i, n, positions)
    local r, wire = layer.reach or 0, layer.wire_distance
    local j, k = neighbours(walk, i, n)
    local p = positions[i]
    if j and k then
        if vect.distance(positions[j], positions[k]) > wire then return end
    elseif job.closed or not (j or k) then
        return
    else
        -- The first or last pole of an open line, with the next one close by.
        if vect.distance(p, positions[j or k]) > wire / 3 then return end
    end
    local needed = false
    near(walk, walk.pole_s[i], walk.pole_s[i], function(c)
        if not needed and c.cover == 1 and covers(p, c, r) then needed = true end
    end)
    if needed then return end
    near(walk, walk.pole_s[i], walk.pole_s[i], function(c)
        if covers(p, c, r) then c.cover = c.cover - 1 end
    end)
    walk.removed[i] = true
    h.set_cells(job, layer.size, p, false)
end

--- Slide pole i towards the middle between its neighbours, as far as reach and
--- the consumers only it powers allow.
--- @return number used
local function try_slide(job, walk, layer, h, i, n, positions)
    local j, k = neighbours(walk, i, n)
    if not (j and k) then return 0 end
    local r, wire = layer.reach or 0, layer.wire_distance
    local s_old, old = walk.pole_s[i], positions[i]
    local s_mid = (walk.pole_s[j] + walk.pole_s[k]) / 2
    if math.abs(s_mid - s_old) < 1 then return 0 end
    h.set_cells(job, layer.size, old, false)
    local used, step = 0, (s_old > s_mid) and lib.STEP or -lib.STEP
    local s = s_mid
    while math.abs(s - s_old) >= 1 do
        local pos = h.find_spot(job, layer.size, point_at(walk, s))
        used = used + h.COST.place
        if pos and vect.distance(positions[j], pos) <= wire and vect.distance(pos, positions[k]) <= wire
            and keeps_sole(walk, s_old, s, old, pos, r) then
            near(walk, s_old, s, function(c)
                if covers(old, c, r) then c.cover = c.cover - 1 end
                if covers(pos, c, r) then c.cover = c.cover + 1 end
            end)
            positions[i] = pos
            walk.pole_s[i] = s
            h.set_cells(job, layer.size, pos, true)
            return used
        end
        s = s + step
    end
    h.set_cells(job, layer.size, old, true)
    return used
end

--- Number of consecutive pairs out of wire reach.
local function count_gaps(list, wire)
    local gaps = 0
    for i = 2, #list do
        if vect.distance(list[i - 1], list[i]) > wire then gaps = gaps + 1 end
    end
    return gaps
end

--- The refine phase: removals, then slides, then the plan is rewritten.
--- @return number used
refine = function(job, walk, layer, h, budget)
    local plan = job.plan
    local chain = plan.chains[layer.idx]
    local members = chain.members
    local n = #members
    if not walk.refine then
        -- The line's poles are the last entities in the plan, in order; only then
        -- can removed ones be taken out again.
        local tail = n > 0 and members[n] == #plan.entities and members[1] == #plan.entities - n + 1
        if not tail or #(walk.pole_s or {}) ~= n then
            walk.phase = "count"
            return 0
        end
        local positions = {}
        for i, m in ipairs(members) do positions[i] = plan.entities[m].position end
        for _, c in ipairs(walk.consumers) do c.cover = 0 end
        for i = 1, n do
            near(walk, walk.pole_s[i], walk.pole_s[i], function(c)
                if covers(positions[i], c, layer.reach or 0) then c.cover = c.cover + 1 end
            end)
        end
        walk.refine = { pass = "remove", i = 1, positions = positions, gaps = count_gaps(positions, layer.wire_distance) }
        walk.removed = {}
    end
    local state, used = walk.refine, 0
    while used < budget and state.pass ~= "write" do
        if state.i > n then
            state.pass, state.i = state.pass == "remove" and "slide" or "write", 1
        elseif walk.removed[state.i] then
            state.i = state.i + 1
        elseif state.pass == "remove" then
            try_remove(job, walk, layer, h, state.i, n, state.positions)
            state.i = state.i + 1
            used = used + 2
        else
            used = used + try_slide(job, walk, layer, h, state.i, n, state.positions) + 1
            state.i = state.i + 1
        end
    end
    if state.pass == "write" then
        -- Put the kept poles back as the plan's last entities, in order.
        local first = members[1]
        local kept, kept_positions = {}, {}
        for i, m in ipairs(members) do
            if not walk.removed[i] then
                local e = plan.entities[m]
                e.position = state.positions[i]
                table.insert(kept, e)
                table.insert(kept_positions, e.position)
            end
        end
        for idx = #plan.entities, first, -1 do plan.entities[idx] = nil end
        chain.members = {}
        for _, e in ipairs(kept) do
            table.insert(plan.entities, e)
            table.insert(chain.members, #plan.entities)
        end
        plan.counts[layer.idx] = (plan.counts[layer.idx] or 0) - (n - #kept)
        plan.gaps = plan.gaps - state.gaps + count_gaps(kept_positions, layer.wire_distance)
        walk.last = kept_positions[#kept_positions]
        walk.phase = "count"
    end
    return used
end

--- Advance smart placement for one pole layer.
--- @param job PlannerJob
--- @param walk SmartWalk
--- @param band LayerBand
--- @param budget number
--- @param h {find_spot: function, search_spot: function, commit: function, COST: table}
--- @return number used, boolean done
function lib.step(job, walk, band, budget, h)
    local layer, frames, used = band.layer, job.frames, 0
    local u_mid = (band.lo + band.hi) / 2

    if walk.phase == "line" then
        while walk.i <= #frames and used < budget do
            local p = geometry.offset_point(frames[walk.i], u_mid)
            local n = #walk.xs
            walk.xs[n + 1], walk.ys[n + 1] = p.x, p.y
            walk.arc[n + 1] = n == 0 and 0 or walk.arc[n] + math.sqrt((p.x - walk.xs[n]) ^ 2 + (p.y - walk.ys[n]) ^ 2)
            walk.i = walk.i + 1
            used = used + h.COST.frame
        end
        if walk.i > #frames then walk.phase, walk.i = "consumers", 1 end
    end

    if walk.phase == "consumers" then
        local entities, layers = job.plan.entities, job.layers
        while walk.i <= #entities and used < budget do
            local e = entities[walk.i]
            local owner = layers[e.layer]
            if owner and (owner.needs_power or e.power) then
                -- Where along the curve it was placed (spaced layers record it); the
                -- nearest sample could be on another stretch where the curve crosses itself.
                local j = e.frame or geometry.nearest_frame(frames, job.index, e.position)
                local lateral = math.sqrt((e.position.x - walk.xs[j]) ^ 2 + (e.position.y - walk.ys[j]) ^ 2)
                walk.reach_window = math.max(walk.reach_window, lateral + e.size + (layer.reach or 0) + 1)
                table.insert(walk.consumers, {
                    x = e.position.x, y = e.position.y, half = e.size / 2 - lib.MARGIN, s = walk.arc[j],
                    done = false, powered = false, order = walk.i,
                })
                used = used + h.COST.cell
            end
            walk.i = walk.i + 1
            used = used + 1
        end
        if walk.i > #entities then
            table.sort(walk.consumers, function(a, b)
                if a.s ~= b.s then return a.s < b.s end
                return a.order < b.order
            end)
            walk.phase = "poles"
        end
    end

    if walk.phase == "poles" then
        if not walk.last then
            local target, direction = point_at(walk, 0)
            local spot, more = h.search_spot(job, layer.size, target, direction)
            used = used + more
            if spot then put(job, walk, layer, h, spot, 0) else job.plan.skipped = job.plan.skipped + 1 end
            if not walk.last then
                walk.phase = "done"
                return used, true
            end
        end
        while used < budget do
            local u, finished = next_pole(job, walk, layer, h)
            used = used + u + 1
            if finished then
                walk.phase = "refine"
                break
            end
        end
    end

    if walk.phase == "refine" then
        if lib.NO_REFINE then walk.phase = "count" else used = used + refine(job, walk, layer, h, budget - used) end
    end

    if walk.phase == "count" then
        walk.phase = "done"
        -- Count what no pole powers (checking every pole: few are left over).
        local poles = job.plan.chains[layer.idx].members
        local r = layer.reach or 0
        for _, c in ipairs(walk.consumers) do
            local powered = false
            for _, m in ipairs(poles) do
                if covers(job.plan.entities[m].position, c, r) then
                    powered = true
                    break
                end
            end
            if not powered then job.plan.unpowered = job.plan.unpowered + 1 end
        end
    end
    return used, walk.phase == "done"
end

return lib
