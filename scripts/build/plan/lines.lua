--- Planner: the paths stage, belt and pipe lines routed and made into entities
--- (build/paths.lua), a budgeted amount per step.
local registry = require("scripts.layers.registry")
local paths = require("scripts.build.paths")
local C = require("scripts.build.plan.common")
local cell_key, count_extra = C.cell_key, C.count_extra

local lib = {}

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

--- Route one line, a budgeted amount at a time: its current cells ordered into
--- continuous segments (`paths.step_segments`), then their diagonal steps joined
--- through corner cells, a segment per step. Progress is kept in the queue item.
--- @param job PlannerJob
--- @param item {idx: integer, line: string, seg: Segmenter|nil, joined: PathCell[][]|nil, si: integer|nil}
--- @param budget number
--- @return number used, boolean done
local function route_path_line(job, item, budget)
    local layer = job.layers[item.idx]
    local line = item.line
    local pipes = registry.type_of(layer).name == "pipe"
    local used = 0
    if not item.seg then
        -- (in any order: the segmenter sorts them along the curve)
        local cells = {}
        for _, c in pairs(job.line_cells[line]) do cells[#cells + 1] = c end
        item.seg = paths.new_segmenter(cells, job.closed and #job.frames or nil)
        used = used + #cells * paths.COST.copy
    end
    if not item.joined then
        local u, done = paths.step_segments(item.seg, budget - used)
        used = used + u
        if not done then return used, false end
        item.joined, item.si = {}, 1
    end
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
    local function use(x, y, j)
        local key = cell_key(x, y)
        local owner = job.line_of[key]
        -- (its sample along the curve: a reroute orders the line's cells by it)
        local c = { x = x, y = y, j = j or 0 }
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
    local segments, joined = item.seg.segments, item.joined
    while item.si <= #segments and used < budget do
        local segment = segments[item.si]
        for _, piece in ipairs(paths.join_corners(segment, usable, use)) do joined[#joined + 1] = piece end
        item.si = item.si + 1
        used = used + #segment * paths.COST.join
    end
    if item.si <= #segments then return used, false end
    if job.closed then
        -- Close a loop whose ends meet only diagonally.
        for _, segment in ipairs(joined --[[@as PathCell[][] ]]) do
            local first, last = segment[1], segment[#segment]
            if #segment >= 3 and math.abs(first.x - last.x) == 1 and math.abs(first.y - last.y) == 1 then
                for _, corner in ipairs({ { x = first.x, y = last.y }, { x = last.x, y = first.y } }) do
                    if math.abs(segment[#segment].x - first.x) + math.abs(segment[#segment].y - first.y) == 2
                        and usable(corner.x, corner.y) then
                        use(corner.x, corner.y, last.j)
                        segment[#segment + 1] = { x = corner.x, y = corner.y, j = last.j }
                    end
                end
            end
        end
    end
    job.routes[line] = joined
    item.seg, item.joined, item.si = nil, nil, nil
    return used, true
end

--- The planned entity for one piece of a path line.
--- @param job PlannerJob
--- @param layer Layer
--- @param line string
--- @param piece table  # from paths.pieces
local function emit_piece(job, layer, line, piece)
    local plan = job.plan
    local pipes = registry.type_of(layer).name == "pipe"
    local entity = {
        name = layer.name, quality = layer.quality, position = { x = piece.x, y = piece.y },
        size = 1, layer = layer.idx,
    }
    -- Turrets placed later feed from these lines (build/feeds.lua): from
    -- plain pipes only (a pipe-to-ground or pump doesn't connect sideways).
    local cell = cell_key(math.floor(piece.x), math.floor(piece.y))
    if pipes and piece.kind == "line" then
        job.feed_pipes[cell] = line
        job.feed_pipe_names[line] = layer.name
    elseif not pipes and piece.kind == "line" then
        job.feed_belts[cell] = true
    end
    if piece.kind == "line" then
        if not pipes then entity.direction = piece.direction end
        plan.counts[layer.idx] = (plan.counts[layer.idx] or 0) + 1
    elseif piece.kind == "pump" then
        entity.name, entity.size, entity.w, entity.h = layer.pump_name, math.max(piece.w, piece.h), piece.w, piece.h
        entity.direction, entity.power = piece.direction, layer.pump_power ~= false
        count_extra(plan, layer.idx, layer.pump_item)
    else
        entity.name, entity.direction = layer.underground_name, piece.direction
        if not pipes then entity.belt_type = piece.kind == "underground_in" and "input" or "output" end
        count_extra(plan, layer.idx, layer.underground_item)
    end
    table.insert(plan.entities, entity)
end

--- The parts of a routed segment to build: cells taken by another line after the
--- route was made are left out, splitting it; scraps a few cells long beside a
--- long stretch of the line (left over where a loop's ends meet, or at a tight
--- corner) would be belts going nowhere.
--- @param job PlannerJob
--- @param item {line: string, longest: integer|nil}
--- @param segment PathCell[]
--- @return PathCell[][]
local function kept_parts(job, item, segment)
    local kept, current = {}, {}
    if #segment < lib.MIN_SCRAP and (item.longest or 0) >= 5 * lib.MIN_SCRAP then return kept end
    for _, c in ipairs(segment) do
        if job.line_of[cell_key(c.x, c.y)] == item.line then
            current[#current + 1] = c
        elseif #current > 0 then
            kept[#kept + 1] = current
            current = {}
        end
    end
    if #current > 0 then kept[#kept + 1] = current end
    return kept
end

--- Turn one routed line into belts or pipes (and undergrounds, pumps), a
--- budgeted amount at a time: segment by segment, part by part, the part's
--- entities in chunks. Progress is kept in the queue item.
--- @param job PlannerJob
--- @param item {idx: integer, line: string, longest: integer|nil, gi: integer|nil, parts: PathCell[][]|nil, pi: integer|nil, pieces: table[]|nil, qi: integer|nil}
--- @param budget number
--- @return number used, boolean done
local function emit_path_line(job, item, budget)
    local plan = job.plan
    local layer = job.layers[item.idx]
    local pipes = registry.type_of(layer).name == "pipe"
    local used = 0
    local route = job.routes[item.line] or {}
    if not item.gi then
        local longest = 0
        for _, segment in ipairs(route) do longest = math.max(longest, #segment) end
        item.longest, item.gi = longest, 1
        used = used + #route
    end
    while used < budget do
        if item.pieces then
            -- The current part's entities.
            local pieces = item.pieces
            while item.qi <= #pieces and used < budget do
                emit_piece(job, layer, item.line, pieces[item.qi])
                item.qi = item.qi + 1
                used = used + C.COST.place
            end
            if item.qi > #pieces then item.pieces, item.qi = nil, nil end
        elseif item.parts and item.pi <= #item.parts then
            local part = item.parts[item.pi]
            item.pi = item.pi + 1
            used = used + #part * paths.COST.piece
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
                    pump_length = layer.pump_length,
                    loop = loop,
                    taken = not pipes and function(x, y) return job.belt_cells[cell_key(x, y)] == true end or nil,
                })
                plan.skipped = plan.skipped + missing
                item.pieces, item.qi = pieces, 1
            end
        elseif item.gi <= #route then
            local segment = route[item.gi]
            item.gi = item.gi + 1
            item.parts, item.pi = kept_parts(job, item, segment), 1
            used = used + #segment * paths.COST.split
        else
            item.longest, item.gi, item.parts, item.pi = nil, nil, nil, nil
            return used, true
        end
    end
    return used, false
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
        -- The lines, in band order; their cells are filed in below, a budgeted
        -- number per step.
        local setup = { lines = {}, li = 1, ci = 1 }
        for _, band in ipairs(job.bands) do
            local lines = job.path_cells and job.path_cells[band.layer.idx]
            if lines then
                for k = 1, band.layer.lines or 1 do
                    if lines[k] then
                        local line = band.layer.idx .. ":" .. k
                        job.line_layer[line] = band.layer.idx
                        job.line_cells[line] = {}
                        table.insert(setup.lines, {
                            line = line, cells = lines[k], belts = registry.type_of(band.layer).name == "belt",
                        })
                        table.insert(job.path_queue, { idx = band.layer.idx, line = line, phase = "route" })
                    end
                end
            end
        end
        job.path_setup = setup
        job.path_cells = nil
    end
    local setup = job.path_setup
    while setup and used < budget do
        local entry = setup.lines[setup.li]
        if not entry then
            -- Every line filed: routing can start, then the entities.
            local emits = {}
            for _, e in ipairs(setup.lines) do
                table.insert(emits, { idx = job.line_layer[e.line], line = e.line, phase = "emit" })
            end
            job.path_emits, job.path_setup, setup = emits, nil, nil
        else
            local cells, line_cells = entry.cells, job.line_cells[entry.line]
            while setup.ci <= #cells and used < budget do
                local c = cells[setup.ci]
                local key = cell_key(c.x, c.y)
                line_cells[key] = c
                job.line_of[key] = entry.line
                if entry.belts then job.belt_cells[key] = true end
                setup.ci = setup.ci + 1
                used = used + C.COST.frame
            end
            if setup.ci > #cells then setup.li, setup.ci = setup.li + 1, 1 end
        end
    end
    if setup then return used end
    while used < budget do
        local item = job.path_queue[job.cursor]
        if not item then
            if not job.path_emits then break end
            -- Routing done (re-routes included): now the entities.
            for _, e in ipairs(job.path_emits) do table.insert(job.path_queue, e) end
            job.path_emits = nil
        elseif item.phase == "route" then
            local done = true
            if item.seg or not job.routes[item.line] then
                local u
                u, done = route_path_line(job, item, budget - used)
                used = used + u
            end
            if done then job.cursor = job.cursor + 1 end
        else
            local u, done = emit_path_line(job, item, budget - used)
            used = used + u + 1
            if done then job.cursor = job.cursor + 1 end
        end
    end
    if not job.path_queue[job.cursor] and not job.path_emits then
        job.path_queue, job.line_cells, job.line_of, job.line_layer = nil, nil, nil, nil
        job.belt_cells, job.locked, job.routes, job.reroutes = nil, nil, nil, nil
        job.stage, job.cursor = "joins", 1
    end
    return used
end

lib.stage_paths = stage_paths

return lib
