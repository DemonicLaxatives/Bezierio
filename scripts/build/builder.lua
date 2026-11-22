--- Turns a curve + layer stack into a build plan, and a plan into ghosts.
---
--- Geometry
---   The curve is sampled densely; every sample gets a unit tangent `t` and normal `n`
---   (n points to the right of the direction of travel P1 -> Pn, in Factorio's y-down world).
---   Distances across the curve are measured in "grid units": u = d / (|n.x| + |n.y|).
---   That is the width of one grid cell projected onto the normal, so a band one unit
---   wide is a 4-connected staircase on diagonals (no corner-only joins between walls).
---
--- Layers
---   Layer 0 is centred on the curve, layers 1, 2, ... stack outward on the +n side,
---   -1, -2, ... on the -n side. Each layer occupies a half-open band [lo, hi) of u.
---   Every grid cell near the curve is assigned to exactly one band (by its centre),
---   so layers never overlap.
local vect = require("scripts.vector_math")
local curve_control = require("scripts.curve_math.control")

local lib = {}

lib.SAMPLE_STEP = 0.25
local U_QUANTUM = 1024

local BAND_TYPES = { ["wall"] = true, ["tile"] = true }
local SPACED_TYPES = { ["electric-pole"] = true, ["electric-turret"] = true, ["roboport"] = true }

--- @class CurveFrame
--- @field p Vector  # position
--- @field t Vector  # unit tangent
--- @field n Vector  # unit normal
--- @field w number  # |n.x| + |n.y|

--- @param points Vector[]
--- @return CurveFrame[]
function lib.frames(points)
    local frames = {}
    local count = #points
    for i = 1, count do
        local a = points[math.max(1, i - 1)]
        local b = points[math.min(count, i + 1)]
        local t = vect.normalize(vect.sub(b, a))
        frames[i] = { p = points[i], t = t }
    end
    -- Repeated points give zero tangents; borrow the nearest valid one.
    local last_valid = nil
    for i = 1, count do
        local t = frames[i].t
        if t.x == 0 and t.y == 0 then
            frames[i].t = last_valid
        else
            last_valid = t
        end
    end
    last_valid = nil
    for i = count, 1, -1 do
        if frames[i].t then last_valid = frames[i].t else frames[i].t = last_valid end
    end
    for i = 1, count do
        local f = frames[i]
        if not f.t then return {} end -- all points identical
        f.n = vect.perpendicular(f.t)
        f.w = math.abs(f.n.x) + math.abs(f.n.y)
    end
    return frames
end

--- Thickness of a layer's band, in grid units.
--- @param layer Buildable
--- @return number
function lib.thickness(layer)
    if BAND_TYPES[layer.type] then
        if layer.idx == 0 then
            return 2 * layer.radius - 1
        end
        return layer.radius
    end
    return layer.size or 1
end

--- @class LayerBand
--- @field layer Buildable
--- @field lo number
--- @field hi number

--- Lay the layers out side by side, outward from layer 0.
--- @param layers table<integer, Buildable>
--- @return LayerBand[]
function lib.bands(layers)
    local bands = {}
    local base = layers[0]
    if not base then return bands end

    local half = lib.thickness(base) / 2
    table.insert(bands, { layer = base, lo = -half, hi = half })

    local outer = half
    local k = 1
    while layers[k] do
        local layer = layers[k]
        local lo = outer + (layer.offset or 0)
        local hi = lo + lib.thickness(layer)
        table.insert(bands, { layer = layer, lo = lo, hi = hi })
        outer = hi
        k = k + 1
    end

    outer = half
    k = -1
    while layers[k] do
        local layer = layers[k]
        local hi = -(outer + (layer.offset or 0))
        local lo = hi - lib.thickness(layer)
        table.insert(bands, { layer = layer, lo = lo, hi = hi })
        outer = -lo
        k = k - 1
    end
    return bands
end

local function dist2(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
end

local BUCKET = 4

--- Spatial hash of frame indices, bucketed by position.
--- @param frames CurveFrame[]
--- @return table<integer, table<integer, integer[]>>
local function build_index(frames)
    local buckets = {}
    for j, f in ipairs(frames) do
        local bx, by = math.floor(f.p.x / BUCKET), math.floor(f.p.y / BUCKET)
        local column = buckets[bx]
        if not column then
            column = {}; buckets[bx] = column
        end
        local list = column[by]
        if not list then
            list = {}; column[by] = list
        end
        list[#list + 1] = j
    end
    return buckets
end

--- Index of the frame nearest to `c` (exact): search rings of buckets outward
--- until no unsearched bucket can hold anything closer.
--- @param frames CurveFrame[]
--- @param index table<integer, table<integer, integer[]>>
--- @param c Vector
--- @return integer index, number squared_distance
local function nearest_frame(frames, index, c)
    local cx, cy = math.floor(c.x / BUCKET), math.floor(c.y / BUCKET)
    local best, best_d = 1, math.huge
    local r = 0
    while true do
        for bx = cx - r, cx + r do
            local column = index[bx]
            if column then
                local edge = (bx == cx - r) or (bx == cx + r)
                local step = edge and 1 or 2 * r
                for by = cy - r, cy + r, step do
                    local list = column[by]
                    if list then
                        for _, j in ipairs(list) do
                            local d = dist2(c, frames[j].p)
                            if d < best_d or (d == best_d and j < best) then best, best_d = j, d end
                        end
                    end
                end
            end
        end
        -- Everything in rings beyond r is at least r * BUCKET away.
        if best_d <= (r * BUCKET) ^ 2 or r > 4096 then return best, best_d end
        r = r + 1
    end
end

--- Signed grid-unit distance of `c` measured from frame `j`, or nil when `c`
--- lies beyond that end of the curve.
--- @param frames CurveFrame[]
--- @param j integer
--- @param c Vector
--- @return number|nil u, number along
local function frame_u(frames, j, c)
    local f = frames[j]
    local rel = vect.sub(c, f.p)
    local along = vect.dot(rel, f.t)
    if j == 1 or j == #frames then
        local along_u = along / (math.abs(f.t.x) + math.abs(f.t.y))
        if j == 1 and along_u < -0.5 then return nil, along end
        if j == #frames and along_u >= 0.5 then return nil, along end
    end
    return vect.dot(rel, f.n) / f.w, along
end

--- Max |along-tangent offset| for a frame to count as a foot point of `c`
--- (samples are at most SAMPLE_STEP apart).
local FOOT_TOLERANCE = 0.3

--- Signed grid-unit distance of a cell centre from the curve, or nil when the
--- cell lies beyond the ends of the curve.
---
--- Normally this is measured from the nearest point. Where the curve passes near
--- itself, another branch can be (slightly) farther in plain distance but closer in
--- grid units; the cell then belongs to that branch, otherwise lines would get gaps
--- at junctions. Only foot points within sqrt(2) * nearest distance can win.
--- @param frames CurveFrame[]
--- @param index table
--- @param c Vector
--- @return number|nil
local function cell_u(frames, index, c)
    local j0, d0 = nearest_frame(frames, index, c)
    local best_u = frame_u(frames, j0, c)

    local radius = math.sqrt(d0) * 1.415 + 0.05
    local radius2 = radius * radius
    for bx = math.floor((c.x - radius) / BUCKET), math.floor((c.x + radius) / BUCKET) do
        local column = index[bx]
        if column then
            for by = math.floor((c.y - radius) / BUCKET), math.floor((c.y + radius) / BUCKET) do
                local list = column[by]
                if list then
                    for _, j in ipairs(list) do
                        if j ~= j0 and dist2(c, frames[j].p) <= radius2 then
                            local u, along = frame_u(frames, j, c)
                            if u and math.abs(along) <= FOOT_TOLERANCE
                                and (best_u == nil or math.abs(u) < math.abs(best_u)) then
                                best_u = u
                            end
                        end
                    end
                end
            end
        end
    end
    if not best_u then return nil end

    -- Quantize: on rational slopes (45° especially) cell centres land exactly on band
    -- edges, and sampling noise (~1e-5) would otherwise push both cells of a staircase
    -- step out of the band, breaking 4-connectivity.
    return math.floor(best_u * U_QUANTUM + 0.5) / U_QUANTUM
end

local function cell_key(x, y)
    return x .. "," .. y
end

--- Assign every grid cell near the curve to at most one band.
--- @param frames CurveFrame[]
--- @param bands LayerBand[]
--- @return table<string, {x: integer, y: integer, band: LayerBand}>
function lib.rasterize(frames, bands)
    local cells = {}
    if #frames == 0 or #bands == 0 then return cells end

    local umin, umax = math.huge, -math.huge
    for _, band in pairs(bands) do
        umin = math.min(umin, band.lo)
        umax = math.max(umax, band.hi)
    end

    local index = build_index(frames)
    local seen = {}
    for _, f in ipairs(frames) do
        local v = umin - 1
        while v <= umax + 1 do
            local d = v * f.w
            local x = math.floor(f.p.x + f.n.x * d)
            local y = math.floor(f.p.y + f.n.y * d)
            local key = cell_key(x, y)
            if not seen[key] then
                seen[key] = true
                local u = cell_u(frames, index, { x = x + 0.5, y = y + 0.5 })
                if u then
                    for _, band in pairs(bands) do
                        if u >= band.lo and u < band.hi then
                            cells[key] = { x = x, y = y, band = band }
                            break
                        end
                    end
                end
            end
            v = v + lib.SAMPLE_STEP
        end
    end
    return cells
end

--- @param x integer
--- @param y integer
--- @param checkerboard integer
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
--- @field unsupported integer[]   # layer indices whose type the builder cannot handle yet
--- @field skipped integer         # spaced entities that found no free spot

--- Place `layer`'s entities every `spacing` tiles along the middle of its band.
--- @param frames CurveFrame[]
--- @param band LayerBand
--- @param occupied table<string, boolean>
--- @param plan BuildPlan
local function plan_spaced(frames, band, occupied, plan)
    local layer = band.layer
    local size = layer.size
    local spacing = math.max(1, layer.spacing or size)
    local u_mid = (band.lo + band.hi) / 2

    -- The line the entities sit on, and its arc length.
    local line = {}
    for i, f in ipairs(frames) do
        line[i] = vect.add(f.p, vect.scale(u_mid * f.w, f.n))
    end

    local function try_place(target)
        local xa, xb = snap_candidates(target.x, size)
        local ya, yb = snap_candidates(target.y, size)
        local candidates = { { x = xa, y = ya }, { x = xb, y = ya }, { x = xa, y = yb }, { x = xb, y = yb } }
        table.sort(candidates, function(p, q) return dist2(p, target) < dist2(q, target) end)
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
                table.insert(plan.entities, {
                    name = layer.name, quality = layer.quality, position = pos, size = size, layer = layer.idx,
                })
                return
            end
        end
        plan.skipped = plan.skipped + 1
    end

    local next_at = 0
    local travelled = 0
    try_place(line[1])
    next_at = spacing
    for i = 2, #line do
        local seg = vect.distance(line[i - 1], line[i])
        while seg > 0 and travelled + seg >= next_at do
            local k = (next_at - travelled) / seg
            try_place(vect.add(line[i - 1], vect.scale(k, vect.sub(line[i], line[i - 1]))))
            next_at = next_at + spacing
        end
        travelled = travelled + seg
    end
end

--- @param curve BezierCurve
--- @param layers table<integer, Buildable>
--- @return BuildPlan
function lib.plan(curve, layers)
    --- @type BuildPlan
    local plan = { entities = {}, tiles = {}, unsupported = {}, skipped = 0 }
    local points = curve_control.worldSamples(curve, lib.SAMPLE_STEP)
    local frames = lib.frames(points)
    if #frames < 2 then return plan end

    local bands = lib.bands(layers)
    local cells = lib.rasterize(frames, bands)

    -- Entities and tiles live on different planes; only entities compete for cells.
    local occupied = {}

    -- Deterministic order makes plans reproducible.
    local keys = {}
    for key in pairs(cells) do table.insert(keys, key) end
    table.sort(keys)

    for _, key in ipairs(keys) do
        local cell = cells[key]
        local layer = cell.band.layer
        if BAND_TYPES[layer.type] and checkerboard_keep(cell.x, cell.y, layer.checkerboard) then
            if layer.type == "tile" then
                table.insert(plan.tiles, { name = layer.name, x = cell.x, y = cell.y, layer = layer.idx })
            else
                occupied[key] = true
                table.insert(plan.entities, {
                    name = layer.name,
                    quality = layer.quality,
                    position = { x = cell.x + 0.5, y = cell.y + 0.5 },
                    size = 1,
                    layer = layer.idx,
                })
            end
        end
    end

    local spaced = {}
    for _, band in pairs(bands) do
        local layer_type = band.layer.type
        if SPACED_TYPES[layer_type] then
            table.insert(spaced, band)
        elseif layer_type ~= "nil" and not BAND_TYPES[layer_type] then
            table.insert(plan.unsupported, band.layer.idx)
        end
    end
    table.sort(spaced, function(a, b)
        if a.layer.priority ~= b.layer.priority then return a.layer.priority > b.layer.priority end
        return a.layer.idx < b.layer.idx
    end)
    for _, band in ipairs(spaced) do
        plan_spaced(frames, band, occupied, plan)
    end

    return plan
end

--- @alias BezierioBuildMode "forced"|"superforced"

--- @class BuildResult
--- @field placed integer
--- @field existing integer
--- @field blocked integer
--- @field instant boolean  # entities were built directly instead of as ghosts

local IGNORED_IN_THE_WAY = {
    ["character"] = true,
    ["resource"] = true,
    ["corpse"] = true,
    ["entity-ghost"] = true,
    ["tile-ghost"] = true,
    ["item-on-ground"] = true,
}

--- Players in the map editor or with cheat mode get real entities, not ghosts.
--- @param player LuaPlayer
--- @return boolean
function lib.builds_instantly(player)
    return player.cheat_mode
        or player.controller_type == defines.controllers.editor
        or player.physical_controller_type == defines.controllers.editor
end

--- @class BuildContext
--- @field surface LuaSurface
--- @field force LuaForce
--- @field player LuaPlayer
--- @field mode BezierioBuildMode
--- @field instant boolean
--- @field tiles Tile[]          # instant mode: tiles to set in one go
--- @field result BuildResult

--- @param ctx BuildContext
--- @param tile PlannedTile
local function build_tile(ctx, tile)
    local surface, result = ctx.surface, ctx.result
    local position = { x = tile.x + 0.5, y = tile.y + 0.5 }
    if surface.get_tile(tile.x, tile.y).name == tile.name then
        result.existing = result.existing + 1
        return
    end
    for _, ghost in pairs(surface.find_entities_filtered { type = "tile-ghost", position = position }) do
        if ghost.ghost_name == tile.name then
            if ctx.instant then
                ghost.destroy()
                break
            end
            result.existing = result.existing + 1
            return
        end
    end
    if not surface.can_place_entity {
            name = "tile-ghost", inner_name = tile.name, position = position, force = ctx.force,
            build_check_type = defines.build_check_type.manual_ghost,
        } then
        result.blocked = result.blocked + 1
        return
    end
    if ctx.instant then
        table.insert(ctx.tiles, { name = tile.name, position = { x = tile.x, y = tile.y } })
    else
        surface.create_entity {
            name = "tile-ghost", inner_name = tile.name, position = position,
            force = ctx.force, player = ctx.player, raise_built = true,
        }
    end
    result.placed = result.placed + 1
end

--- Get an obstacle out of the way: removed outright when building instantly,
--- otherwise marked for deconstruction.
--- @param ctx BuildContext
--- @param other LuaEntity
local function clear(ctx, other)
    if ctx.instant then
        other.destroy { raise_destroy = true }
    else
        other.order_deconstruction(ctx.force, ctx.player)
    end
end

--- @param ctx BuildContext
--- @param entity PlannedEntity
local function build_entity(ctx, entity)
    local surface, force, result = ctx.surface, ctx.force, ctx.result
    local prototype = prototypes.entity[entity.name]
    if not prototype then
        result.blocked = result.blocked + 1
        return
    end
    local position = entity.position

    if surface.find_entity(entity.name, position) then
        result.existing = result.existing + 1
        return
    end
    local ghost = surface.find_entities_filtered { ghost_name = entity.name, position = position, limit = 1 }[1]
    if ghost then
        if ctx.instant and ghost.revive { raise_revive = true } then
            result.placed = result.placed + 1
        else
            result.existing = result.existing + 1
        end
        return
    end

    local box = prototype.collision_box
    local area = {
        left_top = { x = position.x + box.left_top.x, y = position.y + box.left_top.y },
        right_bottom = { x = position.x + box.right_bottom.x, y = position.y + box.right_bottom.y },
    }

    if ctx.mode == "superforced" then
        for _, other in pairs(surface.find_entities_filtered { area = area }) do
            if other.valid then
                if other.type == "entity-ghost" then
                    other.destroy()
                elseif not IGNORED_IN_THE_WAY[other.type]
                    and (other.force == force or other.force.name == "neutral") then
                    clear(ctx, other)
                end
            end
        end
    else
        -- Check with the real entity name: with name = "entity-ghost" + inner_name the
        -- engine's manual ghost check rejects free spots next to existing walls (2.1.24).
        -- With forced = true, trees and rocks don't block (they get cleared below).
        if not surface.can_place_entity {
                name = entity.name, position = position, force = force,
                build_check_type = defines.build_check_type.manual_ghost, forced = true,
            } then
            result.blocked = result.blocked + 1
            return
        end
        for _, other in pairs(surface.find_entities_filtered { area = area, type = { "tree", "simple-entity" } }) do
            clear(ctx, other)
        end
    end

    local created
    if ctx.instant then
        created = surface.create_entity {
            name = entity.name, position = position, quality = entity.quality,
            force = force, player = ctx.player, raise_built = true, move_stuck_players = true,
        }
    else
        created = surface.create_entity {
            name = "entity-ghost", inner_name = entity.name, position = position, quality = entity.quality,
            force = force, player = ctx.player, raise_built = true,
        }
    end
    if created then
        result.placed = result.placed + 1
    else
        result.blocked = result.blocked + 1
    end
end

--- Build a plan on the player's surface: ghosts normally, real entities and tiles
--- for players in the map editor or cheat mode.
--- @param player LuaPlayer
--- @param plan BuildPlan
--- @param mode BezierioBuildMode
--- @return BuildResult
function lib.execute(player, plan, mode)
    --- @type BuildContext
    local ctx = {
        surface = player.surface,
        force = player.force --[[@as LuaForce]],
        player = player,
        mode = mode,
        instant = lib.builds_instantly(player),
        tiles = {},
        result = { placed = 0, existing = 0, blocked = 0, instant = false },
    }
    ctx.result.instant = ctx.instant
    for _, tile in ipairs(plan.tiles) do
        build_tile(ctx, tile)
    end
    if #ctx.tiles > 0 then
        ctx.surface.set_tiles(ctx.tiles, true, "abort_on_collision", true, true, player)
    end
    for _, entity in ipairs(plan.entities) do
        build_entity(ctx, entity)
    end
    return ctx.result
end

return lib
