--- Builds a plan into the world, as a resumable job.
---
--- What "building" means is up to the output module (outputs/*.lua): ghosts, or
--- real entities in the map editor / cheat mode. This module does what they share:
--- skipping what's already there, the placement check, finding obstacles, wiring
--- pole chains, and keeping everything in one undo item.
local undo = require("scripts.build.undo")
local wires = require("scripts.build.wires")
local cover = require("scripts.build.cover")

local lib = {}

--- How hard a build pushes (as the game's build modes, FFF-383):
--- - normal: anything in the way blocks;
--- - forced: trees, rocks and cliffs in the way are removed (marked for
---   deconstruction, as ghosts), and cover tiles (landfill, foundation, ...) are
---   laid where the ground can't take what's planned (build/cover.lua);
--- - superforced: as forced, and the player's own and neutral entities in the way
---   are removed too.
--- @alias BezierioBuildMode "normal"|"forced"|"superforced"

--- @class BuildOutput
--- @field name string
--- @field matching_tile_ghost fun(job: BuildJob, player: LuaPlayer, ghost: LuaEntity): "existing"|nil
--- @field place_tile fun(job: BuildJob, player: LuaPlayer, tile: PlannedTile, undo_index: integer)
--- @field flush fun(job: BuildJob, player: LuaPlayer, undo_index: integer)
--- @field matching_entity_ghost fun(job: BuildJob, player: LuaPlayer, ghost: LuaEntity, entity: PlannedEntity): "placed"|"existing", LuaEntity|nil  # the entity revived from it
--- @field clear fun(job: BuildJob, player: LuaPlayer, obstacle: LuaEntity, undo_index: integer)
--- @field create_entity fun(job: BuildJob, player: LuaPlayer, entity: PlannedEntity, undo_index: integer): LuaEntity|nil
--- @field place_cover fun(job: BuildJob, player: LuaPlayer, cell: {x: integer, y: integer, tile: string}, undo_index: integer)  # at once, before what goes on it

--- @type table<string, BuildOutput>
lib.outputs = {
    ghost = require("scripts.build.outputs.ghost"),
    instant = require("scripts.build.outputs.instant"),
}

--- Work units per placement, for budgeting.
lib.COST = { tile = 3, entity = 6, wire = 4 }

--- @class BuildResult
--- @field placed integer
--- @field existing integer
--- @field blocked integer
--- @field covered integer|nil  # cover tiles laid

--- @class BuildJob: WireWalk
--- @field player_index integer
--- @field surface LuaSurface
--- @field force LuaForce
--- @field mode BezierioBuildMode
--- @field output string          # key in lib.outputs
--- @field plan BuildPlan         # finished plan (read only)
--- @field stage "tiles"|"entities"|"wires"|"done"
--- @field cursor integer
--- @field tile_batch Tile[]      # used by the instant output
--- @field undo UndoTracking
--- @field result BuildResult
--- @field own table<integer, true>|nil  # unit numbers of what this build made
--- @field cover_tiles string[]|nil  # the player's cover items, in order
--- @field aborted boolean|nil  # stopped: its surface or force went away

--- Entity types super force never clears: characters and their corpses, items on
--- the ground, ore, robots in flight, effects, request proxies (entity types, not
--- names: an item on the ground is an "item-entity").
local IGNORED_IN_THE_WAY = {}
for _, t in ipairs({
    "character", "character-corpse", "corpse", "resource", "item-entity", "item-request-proxy",
    "entity-ghost", "tile-ghost", "deconstructible-tile-proxy",
    "construction-robot", "logistic-robot", "combat-robot", "capture-robot",
    "projectile", "beam", "stream", "fire", "sticker", "explosion", "smoke-with-trigger", "particle-source",
    "highlight-box", "speech-bubble",
}) do IGNORED_IN_THE_WAY[t] = true end

--- Types whose way round matters for "already there": a belt facing the other way
--- isn't the planned belt. (Not rails: the game folds opposite directions together.)
local DIRECTED = {
    ["transport-belt"] = true, ["underground-belt"] = true, ["pipe-to-ground"] = true,
    ["pump"] = true, ["inserter"] = true,
}

--- Does what's there (an entity or ghost of the planned name) face the planned way?
--- @param found LuaEntity
--- @param entity PlannedEntity
--- @param kind string  # the prototype type
--- @return boolean
local function same_way(found, entity, kind)
    if not DIRECTED[kind] or entity.direction == nil then return true end
    if found.direction ~= entity.direction then return false end
    if entity.belt_type and kind == "underground-belt" and found.belt_to_ground_type ~= entity.belt_type then
        return false
    end
    return true
end

--- Players in the map editor or with cheat mode get real entities, not ghosts.
--- @param player LuaPlayer
--- @return boolean
function lib.builds_instantly(player)
    return player.cheat_mode
        or player.controller_type == defines.controllers.editor
        or player.physical_controller_type == defines.controllers.editor
end

--- @param player LuaPlayer
--- @param plan BuildPlan  # must be done
--- @param mode BezierioBuildMode
--- @param cover_tiles string[]|nil  # the player's cover items, in order (none: each tile's default)
--- @return BuildJob
function lib.new_job(player, plan, mode, cover_tiles)
    local chain_keys = wires.chain_keys(plan)
    return {
        player_index = player.index,
        surface = player.surface,
        force = player.force --[[@as LuaForce]],
        mode = mode,
        output = lib.builds_instantly(player) and "instant" or "ghost",
        plan = plan,
        stage = "tiles",
        cursor = 1,
        chain_keys = chain_keys,
        chain_cursor = 1,
        tile_batch = {},
        undo = {},
        result = { placed = 0, existing = 0, blocked = 0, covered = 0 },
        cover_tiles = cover_tiles,
    }
end

--- Rough share of the work done, 0..1.
--- @param job BuildJob
--- @return number
function lib.progress(job)
    local total = #job.plan.tiles + #job.plan.entities
    if total == 0 or job.stage == "done" or job.stage == "wires" then return 1 end
    local done = job.stage == "tiles" and job.cursor - 1 or #job.plan.tiles + job.cursor - 1
    return done / total
end

--- Run one output action inside the job's undo item. `arg` is the action's subject
--- (tile, entity, obstacle) or nil for actions without one.
--- @param job BuildJob
--- @param player LuaPlayer
--- @param fn function
--- @param arg any
--- @return any
local function with_undo(job, player, fn, arg)
    local index = undo.index(job.undo, player)
    local result
    if arg == nil then
        result = fn(job, player, index)
    else
        result = fn(job, player, arg, index)
    end
    undo.after(job.undo, player)
    return result
end

--- The item that places a tile, if any.
--- @param name string
--- @return LuaItemPrototype|nil
local function tile_item(name)
    local tile = prototypes.tile[name]
    local item = tile and cover.item_of(tile)
    return item and prototypes.item[item] or nil
end

--- A cover tile ghost already at a cell (from this build, or before) whose tile
--- takes what's planned.
--- @param surface LuaSurface
--- @param x integer
--- @param y integer
--- @param takes fun(tile: LuaTilePrototype): boolean
--- @return boolean
local function cover_ghost_at(surface, x, y, takes)
    for _, ghost in pairs(surface.find_entities_filtered { type = "tile-ghost", position = { x + 0.5, y + 0.5 } }) do
        local t = prototypes.tile[ghost.ghost_name]
        if t and t.is_foundation and takes(t) then return true end
    end
    return false
end

--- @param job BuildJob
--- @param player LuaPlayer
--- @param output BuildOutput
--- @param tile PlannedTile
local function build_tile(job, player, output, tile)
    local surface, result = job.surface, job.result
    local position = { x = tile.x + 0.5, y = tile.y + 0.5 }
    if surface.get_tile(tile.x, tile.y).name == tile.name then
        result.existing = result.existing + 1
        return
    end
    for _, ghost in pairs(surface.find_entities_filtered { type = "tile-ghost", position = position }) do
        if ghost.ghost_name == tile.name then
            if output.matching_tile_ghost(job, player, ghost) == "existing" then
                result.existing = result.existing + 1
                return
            end
            break
        end
    end
    -- Ground the tile can't go on (water under a stone path): cover first, when
    -- forced. (The ghost check doesn't know about a cover ghost under it.)
    local here = surface.get_tile(tile.x, tile.y).prototype
    local item = tile_item(tile.name)
    local covered = false
    if item and not cover.item_goes_on(item, here) then
        if job.mode == "normal" then
            result.blocked = result.blocked + 1
            return
        end
        local below = cover_ghost_at(surface, tile.x, tile.y, function(t) return cover.item_goes_on(item, t) end)
        if not below then
            local c = cover.choose(here, function(t) return cover.item_goes_on(item, t) end, job.cover_tiles)
            if not c then
                result.blocked = result.blocked + 1
                return
            end
            with_undo(job, player, output.place_cover, { x = tile.x, y = tile.y, tile = c.tile })
            result.covered = (result.covered or 0) + 1
        end
        covered = true
    end
    if not covered and not surface.can_place_entity {
            name = "tile-ghost", inner_name = tile.name, position = position, force = job.force,
            build_check_type = defines.build_check_type.manual_ghost,
        } then
        result.blocked = result.blocked + 1
        return
    end
    with_undo(job, player, output.place_tile, tile)
    result.placed = result.placed + 1
end

--- @param job BuildJob
--- @param player LuaPlayer
--- @param output BuildOutput
--- @param entity PlannedEntity
--- Entity types a rail is made of (a gate goes over them; never cleared for one).
local RAIL_TYPES = { "straight-rail", "half-diagonal-rail", "curved-rail-a", "curved-rail-b", "rail-ramp", "legacy-straight-rail", "legacy-curved-rail" }
local IS_RAIL = {}
for _, t in ipairs(RAIL_TYPES) do IS_RAIL[t] = true end

--- Elevated rail pieces: nothing on the ground is in their way.
local IS_ELEVATED = {
    ["elevated-straight-rail"] = true, ["elevated-half-diagonal-rail"] = true,
    ["elevated-curved-rail-a"] = true, ["elevated-curved-rail-b"] = true,
}

--- What track is made of: rails cross and overlap each other, and signals and
--- supports stand among them, so building track never clears any of these.
local IS_TRACK = { ["rail-signal"] = true, ["rail-chain-signal"] = true, ["rail-support"] = true }
for t in pairs(IS_RAIL) do IS_TRACK[t] = true end
for t in pairs(IS_ELEVATED) do IS_TRACK[t] = true end

--- Remember an entity (or ghost) this build made, so that super force never clears it.
--- @param job BuildJob
--- @param made LuaEntity|nil
local function own(job, made)
    if not (made and made.valid) then return nil end
    if made.unit_number then
        job.own = job.own or {}
        job.own[made.unit_number] = true
    end
    return made
end

--- @param job BuildJob
--- @param other LuaEntity
local function is_own(job, other)
    return job.own ~= nil and other.unit_number ~= nil and job.own[other.unit_number] == true
end

--- A wall planned where a straight rail crosses: the gate to build instead, if one
--- fits over the rail (gates only go over straight, axis-aligned rails).
--- @param job BuildJob
--- @param entity PlannedEntity
--- @return PlannedEntity|nil
local function gate_instead(job, entity)
    local p = entity.position
    local area = { { p.x - 0.4, p.y - 0.4 }, { p.x + 0.4, p.y + 0.4 } }
    if not job.surface.find_entities_filtered { area = area, type = "straight-rail", limit = 1 }[1] then return nil end
    for _, direction in ipairs({ defines.direction.north, defines.direction.east }) do
        -- (A forced check refuses gates over rails.)
        if job.surface.can_place_entity {
                name = entity.gate, position = p, direction = direction, force = job.force,
                build_check_type = defines.build_check_type.manual_ghost,
            } then
            return { name = entity.gate, quality = entity.quality, position = p, size = 1, layer = entity.layer, direction = direction }
        end
    end
    return nil
end

--- Straight rail planned across walls already there: the walls become gates
--- (turned across the rail), then the rail goes through them.
--- @param job BuildJob
--- @param player LuaPlayer
--- @param output BuildOutput
--- @param entity PlannedEntity  # a straight rail with `gate`
local function gate_walls(job, player, output, entity)
    local p = entity.position
    local area = { { p.x - 1, p.y - 1 }, { p.x + 1, p.y + 1 } }
    local gate_direction = (entity.direction == defines.direction.north or entity.direction == defines.direction.south)
        and defines.direction.east or defines.direction.north
    local surface, result = job.surface, job.result
    for _, wall in pairs(surface.find_entities_filtered { area = area, type = "wall", force = job.force }) do
        -- (built over before: its gate ghost is there already)
        if wall.valid and not surface.find_entities_filtered { ghost_name = entity.gate, position = wall.position, limit = 1 }[1] then
            local at, name, quality = wall.position, wall.name, wall.quality.name
            local gate = { name = entity.gate, quality = "normal", position = at, size = 1, direction = gate_direction }
            with_undo(job, player, output.clear, wall)
            -- Ghosts go over a wall marked for removal; built for real, the wall is
            -- gone first, and comes back if the gate can't go there after all.
            local fits = job.output == "ghost" or surface.can_place_entity {
                name = entity.gate, position = at, direction = gate_direction, force = job.force,
                build_check_type = defines.build_check_type.manual_ghost,
            }
            if fits and own(job, with_undo(job, player, output.create_entity, gate)) then
                result.placed = result.placed + 1
            elseif job.output ~= "ghost" then
                with_undo(job, player, output.create_entity, { name = name, quality = quality, position = at, size = 1 })
                result.blocked = result.blocked + 1
            end
        end
    end
end

--- Where obstacles are looked for: the collision box turned the planned way, or
--- for diagonals and track a square around it (a curved rail's box isn't its
--- footprint).
--- @param prototype LuaEntityPrototype
--- @param entity PlannedEntity
--- @return BoundingBox
local function obstacle_area(prototype, entity)
    local box, p = prototype.collision_box, entity.position
    local l, t, r, b = box.left_top.x, box.left_top.y, box.right_bottom.x, box.right_bottom.y
    local d = entity.direction or 0
    if IS_TRACK[prototype.type] or d % 4 ~= 0 then
        local half = math.max(-l, -t, r, b)
        l, t, r, b = -half, -half, half, half
    elseif d == 4 then -- east: (x, y) -> (-y, x)
        l, t, r, b = -b, l, -t, r
    elseif d == 8 then -- south
        l, t, r, b = -r, -b, -l, -t
    elseif d == 12 then -- west: (x, y) -> (y, -x)
        l, t, r, b = t, -r, b, -l
    end
    return { left_top = { x = p.x + l, y = p.y + t }, right_bottom = { x = p.x + r, y = p.y + b } }
end

--- Types a force build removes when they're in the way.
local NATURAL = { "tree", "simple-entity", "cliff" }
local IS_NATURAL = { tree = true, ["simple-entity"] = true, cliff = true }

--- The cells under an area.
--- @param area BoundingBox
--- @return {x: integer, y: integer}[]
local function cells_of(area)
    local out = {}
    for x = math.floor(area.left_top.x), math.ceil(area.right_bottom.x) - 1 do
        for y = math.floor(area.left_top.y), math.ceil(area.right_bottom.y) - 1 do
            out[#out + 1] = { x = x, y = y }
        end
    end
    return out
end

--- Lay cover where the ground under an entity can't take it (water under a
--- wall). False when some cell has no cover that fits: then nothing is laid.
--- @param job BuildJob
--- @param player LuaPlayer
--- @param output BuildOutput
--- @param prototype LuaEntityPrototype
--- @param area BoundingBox
--- @return boolean ok
local function lay_cover(job, player, output, prototype, area)
    local surface = job.surface
    local function takes(t) return not cover.entity_needs(prototype, t) end
    local todo = {}
    for _, c in ipairs(cells_of(area)) do
        local here = surface.get_tile(c.x, c.y).prototype
        if cover.entity_needs(prototype, here) and not cover_ghost_at(surface, c.x, c.y, takes) then
            local choice = cover.choose(here, takes, job.cover_tiles)
            if not choice then return false end
            todo[#todo + 1] = { x = c.x, y = c.y, tile = choice.tile }
        end
    end
    for _, cell in ipairs(todo) do
        with_undo(job, player, output.place_cover, cell)
        job.result.covered = (job.result.covered or 0) + 1
    end
    return true
end

--- Is anything a force build doesn't remove in the way? (Checked before laying
--- cover, so a blocked spot isn't left with landfill.)
--- @param job BuildJob
--- @param area BoundingBox
--- @return boolean
local function hard_obstacle(job, area)
    for _, other in pairs(job.surface.find_entities_filtered { area = area }) do
        if other.valid and not IGNORED_IN_THE_WAY[other.type] and not IS_NATURAL[other.type] then return true end
    end
    return false
end

local function build_entity(job, player, output, entity)
    local surface, force, result = job.surface, job.force, job.result
    if entity.gate and entity.track then
        gate_walls(job, player, output, entity)
    elseif entity.gate then
        if surface.find_entity(entity.gate, entity.position)
            or surface.find_entities_filtered { ghost_name = entity.gate, position = entity.position, limit = 1 }[1] then
            result.existing = result.existing + 1
            return
        end
        local gate = gate_instead(job, entity)
        if gate then
            if own(job, with_undo(job, player, output.create_entity, gate)) then
                result.placed = result.placed + 1
            else
                result.blocked = result.blocked + 1
            end
            return
        end
    end
    local prototype = prototypes.entity[entity.name]
    if not prototype then
        result.blocked = result.blocked + 1
        return
    end
    local position = entity.position

    -- Facing another way: in the way (the placement check may not say so: belts
    -- can be placed over belts), replaced by super force.
    local found = surface.find_entity(entity.name, position)
    if found and same_way(found, entity, prototype.type) then
        result.existing = result.existing + 1
        return
    elseif found then
        if job.mode ~= "superforced" or is_own(job, found) or found.force ~= force then
            result.blocked = result.blocked + 1
            return
        end
        with_undo(job, player, output.clear, found)
    end
    local ghost = surface.find_entities_filtered { ghost_name = entity.name, position = position, limit = 1 }[1]
    if ghost and same_way(ghost, entity, prototype.type) then
        local outcome, revived = output.matching_entity_ghost(job, player, ghost, entity)
        if revived then own(job, revived) end
        result[outcome] = result[outcome] + 1
        return
    elseif ghost then
        if job.mode ~= "superforced" or ghost.force ~= force then
            result.blocked = result.blocked + 1
            return
        end
        ghost.destroy()
    end

    local area = obstacle_area(prototype, entity)

    -- Check with the real entity name: with name = "entity-ghost" + inner_name the
    -- engine's manual ghost check rejects free spots next to existing walls (2.1.24).
    -- With forced = true, trees and rocks don't block (they get cleared below).
    local function placeable()
        return surface.can_place_entity {
            name = entity.name, position = position, direction = entity.direction, force = force,
            build_check_type = defines.build_check_type.manual_ghost, forced = job.mode ~= "normal",
        }
    end

    -- Cover first, where the ground can't take it (forced: only if nothing that
    -- stays is in the way).
    if job.mode ~= "normal" and entity.rail_layer ~= "elevated" and not IS_ELEVATED[prototype.type] then
        local needs = false
        for _, c in ipairs(cells_of(area)) do
            if cover.entity_needs(prototype, surface.get_tile(c.x, c.y).prototype) then needs = true break end
        end
        if needs then
            if job.mode == "forced" and hard_obstacle(job, area) then
                result.blocked = result.blocked + 1
                return
            end
            if not lay_cover(job, player, output, prototype, area) then
                result.blocked = result.blocked + 1
                return
            end
        end
    end

    if entity.rail_layer == "elevated" then
        -- Up on elevated track: nothing on the ground in the way (and the ground
        -- placement check doesn't know about elevated rails).
    elseif job.mode == "superforced" and not IS_ELEVATED[prototype.type] and not placeable() then
        -- Clear what's in the way: never what this build made, and for track never
        -- other track (the square around a curved rail reaches far past it).
        local track = IS_TRACK[prototype.type]
        for _, other in pairs(surface.find_entities_filtered { area = area }) do
            if other.valid and not is_own(job, other) then
                local kind = other.type == "entity-ghost" and other.ghost_type or other.type
                if track and IS_TRACK[kind] then
                    -- rails over rails
                elseif other.type == "entity-ghost" then
                    -- (only our own force's ghosts)
                    if other.force == force then other.destroy() end
                elseif not IGNORED_IN_THE_WAY[other.type] and not (entity.gate and IS_RAIL[other.type])
                    and (other.force == force or other.force.name == "neutral") then
                    with_undo(job, player, output.clear, other)
                end
            end
        end
    elseif job.mode == "normal" then
        if not placeable() then
            result.blocked = result.blocked + 1
            return
        end
    else
        -- Trees and rocks don't fail the forced check, cliffs do: when only those
        -- are in the way, clear them, then check again.
        local fits = placeable()
        if not fits and hard_obstacle(job, area) then
            result.blocked = result.blocked + 1
            return
        end
        for _, other in pairs(surface.find_entities_filtered { area = area, type = NATURAL }) do
            with_undo(job, player, output.clear, other)
        end
        if not fits and not placeable() then
            result.blocked = result.blocked + 1
            return
        end
    end

    if own(job, with_undo(job, player, output.create_entity, entity)) then
        result.placed = result.placed + 1
    else
        result.blocked = result.blocked + 1
    end
end

--- The pole (or pole ghost) built for a planned entity.
--- @param surface LuaSurface
--- @param entity PlannedEntity
--- @return LuaEntity|nil
local function built_entity(surface, entity)
    return surface.find_entity(entity.name, entity.position)
        or surface.find_entities_filtered { ghost_name = entity.name, position = entity.position, limit = 1 }[1]
end

--- Connect two entities (or ghosts): poles with copper, and red / green wire as asked.
--- @param a LuaEntity
--- @param b LuaEntity
--- @param copper boolean
--- @param red boolean
--- @param green boolean
local function connect(a, b, copper, red, green)
    local ids = {}
    if copper then table.insert(ids, defines.wire_connector_id.pole_copper) end
    if red then table.insert(ids, defines.wire_connector_id.circuit_red) end
    if green then table.insert(ids, defines.wire_connector_id.circuit_green) end
    for _, id in ipairs(ids) do
        local from = a.get_wire_connector(id, true)
        local to = b.get_wire_connector(id, true)
        if from and to then from.connect_to(to, true, defines.wire_origin.player) end
    end
end

--- Wire each pole chain in order along the curve, then the other links (land mines).
--- @param job BuildJob
--- @param budget number
--- @return number used
local function step_wires(job, budget)
    local plan, surface = job.plan, job.surface
    local used, done = wires.step(job, plan, budget, lib.COST.wire,
        function(chain, a, b)
            local x, y = built_entity(surface, plan.entities[a]), built_entity(surface, plan.entities[b])
            if x and y then connect(x, y, true, chain.red, chain.green) end
        end,
        function(link)
            local x, y = built_entity(surface, plan.entities[link.a]), built_entity(surface, plan.entities[link.b])
            if x and y then connect(x, y, false, link.red, link.green) end
        end)
    if done then job.stage = "done" end
    return used
end

--- Do up to about `budget` units of work: tiles, then entities, then wires.
--- @param job BuildJob
--- @param budget number
--- @return boolean done, number used
function lib.step(job, budget)
    local player = game.get_player(job.player_index)
    if not (player and player.valid and job.surface.valid and job.force.valid) then
        -- (the surface or force is gone: nothing to report)
        job.stage, job.aborted = "done", true
        return true, 0
    end
    local output = lib.outputs[job.output]
    local used, plan = 0, job.plan

    if job.stage == "tiles" then
        while job.cursor <= #plan.tiles and used < budget do
            build_tile(job, player, output, plan.tiles[job.cursor])
            job.cursor = job.cursor + 1
            used = used + lib.COST.tile
        end
        with_undo(job, player, output.flush)
        if job.cursor > #plan.tiles then
            job.stage, job.cursor = "entities", 1
        end
    end
    if job.stage == "entities" then
        while job.cursor <= #plan.entities and used < budget do
            build_entity(job, player, output, plan.entities[job.cursor])
            job.cursor = job.cursor + 1
            used = used + lib.COST.entity
        end
        if job.cursor > #plan.entities then
            job.stage, job.cursor = "wires", 1
        end
    end
    if job.stage == "wires" and used < budget then
        used = used + step_wires(job, budget - used)
    end
    return job.stage == "done", used
end

return lib
