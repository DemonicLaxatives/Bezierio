--- Planner: the rasterize stage, every cell near the curve assigned to a band
--- (walls, tiles, land mines, path layer cells).
local vect = require("scripts.vector_math")
local geometry = require("scripts.build.geometry")
local registry = require("scripts.layers.registry")
local C = require("scripts.build.plan.common")
local cell_key, checkerboard_keep = C.cell_key, C.checkerboard_keep

local lib = {}

local link_to_nearby
local collect_path_cell

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

--- A band layer's entity in a free cell.
--- @param job PlannerJob
--- @param layer Layer
--- @param x integer
--- @param y integer
--- @param key string
local function band_entity(job, layer, x, y, key)
    local plan = job.plan
    plan.counts[layer.idx] = (plan.counts[layer.idx] or 0) + 1
    job.occupied[key] = true
    table.insert(plan.entities, {
        name = layer.name, quality = layer.quality,
        position = { x = x + 0.5, y = y + 0.5 }, size = 1, layer = layer.idx,
        gate = (layer.gates ~= false and layer.gate_name) or nil,
    })
    if (layer.red_wire or layer.green_wire) and layer.circuit_distance then link_to_nearby(job, layer, #plan.entities) end
end

--- Place a band layer's tile or entity in a cell (if its checkerboard keeps it).
--- @param job PlannerJob
--- @param band LayerBand
--- @param x integer
--- @param y integer
--- @param key string    # cell_key(x, y)
--- @return boolean  # whether a tile was placed
local function emit_cell(job, band, x, y, key)
    local layer = band.layer
    local def = registry.type_of(layer)
    if def.placement ~= "band" then return false end
    if def.keep then
        if not def.keep(layer, x, y) then return false end
    elseif not checkerboard_keep(x, y, layer.checkerboard) then
        return false
    end
    local plan = job.plan
    if def.output ~= "tile" and job.occupied[key] then return false end -- (rails)
    if def.output == "tile" then
        plan.counts[layer.idx] = (plan.counts[layer.idx] or 0) + 1
        table.insert(plan.tiles, { name = layer.name, x = x, y = y, layer = layer.idx })
        if not band.under then
            job.tiled = job.tiled or {}
            job.tiled[key] = true
        end
        return true
    end
    band_entity(job, layer, x, y, key)
    if def.join_corners and (layer.checkerboard or 0) == 0 then
        job.join_cells = job.join_cells or {}
        job.join_at = job.join_at or {}
        job.join_cells[#job.join_cells + 1] = { x = x, y = y, band = band }
        job.join_at[key] = layer.idx
    end
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
        used = used + C.COST.sweep
        local d = v * f.w
        local x = math.floor(px + f.n.x * d)
        local y = math.floor(py + f.n.y * d)
        local key = cell_key(x, y)
        if not seen[key] then
            seen[key] = true
            used = used + C.COST.cell
            local u, j = geometry.grid_distance(job.frames, job.index, { x = x + 0.5, y = y + 0.5 })
            if u then
                -- The cell's own band first; then an underlay, unless that placed a tile.
                local placed_tile = false
                for _, band in ipairs(bands) do
                    if not band.under and u >= band.lo and u < band.hi then
                        if registry.type_of(band.layer).placement == "path" then
                            collect_path_cell(job, band, x, y, key, u, j)
                        else
                            placed_tile = emit_cell(job, band, x, y, key)
                        end
                        break
                    end
                end
                if not placed_tile then
                    for _, band in ipairs(bands) do
                        if band.under and u >= band.lo and u < band.hi then
                            emit_cell(job, band, x, y, key)
                            break
                        end
                    end
                end
            end
        end
        v = v + C.SAMPLE_STEP
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
    local shift = C.END_PROBE_STEP
    while shift < reach do
        used = used + rasterize_frame(job, f, outward * shift)
        shift = shift + C.END_PROBE_STEP
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

lib.stage_rasterize = stage_rasterize
lib.band_entity = band_entity

return lib
