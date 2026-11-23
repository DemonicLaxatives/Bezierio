--- Builds a plan into the world, as a resumable job.
---
--- What "building" means is up to the output module (outputs/*.lua): ghosts, or
--- real entities in the map editor / cheat mode. This module does what they share:
--- skipping what's already there, the placement check, finding obstacles, wiring
--- pole chains, and keeping everything in one undo item.
local undo = require("scripts.build.undo")

local lib = {}

--- @alias BezierioBuildMode "forced"|"superforced"

--- @class BuildOutput
--- @field name string
--- @field matching_tile_ghost fun(job: BuildJob, player: LuaPlayer, ghost: LuaEntity): "existing"|nil
--- @field place_tile fun(job: BuildJob, player: LuaPlayer, tile: PlannedTile, undo_index: integer)
--- @field flush fun(job: BuildJob, player: LuaPlayer, undo_index: integer)
--- @field matching_entity_ghost fun(job: BuildJob, player: LuaPlayer, ghost: LuaEntity): "placed"|"existing"
--- @field clear fun(job: BuildJob, player: LuaPlayer, obstacle: LuaEntity, undo_index: integer)
--- @field create_entity fun(job: BuildJob, player: LuaPlayer, entity: PlannedEntity, undo_index: integer): LuaEntity|nil

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

--- @class BuildJob
--- @field player_index integer
--- @field surface LuaSurface
--- @field force LuaForce
--- @field mode BezierioBuildMode
--- @field output string          # key in lib.outputs
--- @field plan BuildPlan         # finished plan (read only)
--- @field stage "tiles"|"entities"|"wires"|"done"
--- @field cursor integer
--- @field chain_keys integer[]   # layer indices of plan.chains, for the wires stage
--- @field chain_cursor integer
--- @field tile_batch Tile[]      # used by the instant output
--- @field undo UndoTracking
--- @field result BuildResult

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

--- @param player LuaPlayer
--- @param plan BuildPlan  # must be done
--- @param mode BezierioBuildMode
--- @return BuildJob
function lib.new_job(player, plan, mode)
    local chain_keys = {}
    for idx in pairs(plan.chains) do table.insert(chain_keys, idx) end
    table.sort(chain_keys)
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
        result = { placed = 0, existing = 0, blocked = 0 },
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
    if not surface.can_place_entity {
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

local function build_entity(job, player, output, entity)
    local surface, force, result = job.surface, job.force, job.result
    if entity.gate then
        if surface.find_entity(entity.gate, entity.position)
            or surface.find_entities_filtered { ghost_name = entity.gate, position = entity.position, limit = 1 }[1] then
            result.existing = result.existing + 1
            return
        end
        local gate = gate_instead(job, entity)
        if gate then
            if with_undo(job, player, output.create_entity, gate) then
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

    if surface.find_entity(entity.name, position) then
        result.existing = result.existing + 1
        return
    end
    local ghost = surface.find_entities_filtered { ghost_name = entity.name, position = position, limit = 1 }[1]
    if ghost then
        local outcome = output.matching_entity_ghost(job, player, ghost)
        result[outcome] = result[outcome] + 1
        return
    end

    -- Obstacles: a square around the collision box, so rotated (and diagonal)
    -- footprints are covered too.
    local box = prototype.collision_box
    local half = math.max(-box.left_top.x, -box.left_top.y, box.right_bottom.x, box.right_bottom.y)
    local area = {
        left_top = { x = position.x - half, y = position.y - half },
        right_bottom = { x = position.x + half, y = position.y + half },
    }

    if job.mode == "superforced" then
        for _, other in pairs(surface.find_entities_filtered { area = area }) do
            if other.valid then
                if other.type == "entity-ghost" then
                    other.destroy()
                elseif not IGNORED_IN_THE_WAY[other.type] and not (entity.gate and IS_RAIL[other.type])
                    and (other.force == force or other.force.name == "neutral") then
                    with_undo(job, player, output.clear, other)
                end
            end
        end
    else
        -- Check with the real entity name: with name = "entity-ghost" + inner_name the
        -- engine's manual ghost check rejects free spots next to existing walls (2.1.24).
        -- With forced = true, trees and rocks don't block (they get cleared below).
        if not surface.can_place_entity {
                name = entity.name, position = position, direction = entity.direction, force = force,
                build_check_type = defines.build_check_type.manual_ghost, forced = true,
            } then
            result.blocked = result.blocked + 1
            return
        end
        for _, other in pairs(surface.find_entities_filtered { area = area, type = { "tree", "simple-entity" } }) do
            with_undo(job, player, output.clear, other)
        end
    end

    if with_undo(job, player, output.create_entity, entity) then
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
    local used, plan = 0, job.plan
    if job.chain_cursor > #job.chain_keys then
        local links = plan.links or {}
        job.link_cursor = job.link_cursor or 1
        while job.link_cursor <= #links and used < budget do
            local link = links[job.link_cursor]
            local a = built_entity(job.surface, plan.entities[link.a])
            local b = built_entity(job.surface, plan.entities[link.b])
            if a and b then connect(a, b, false, link.red, link.green) end
            job.link_cursor = job.link_cursor + 1
            used = used + lib.COST.wire
        end
        if job.link_cursor > #links then job.stage = "done" end
        return used
    end
    while job.chain_cursor <= #job.chain_keys and used < budget do
        local chain = plan.chains[job.chain_keys[job.chain_cursor]]
        local members = chain.members
        local count = #members
        local pairs_total = (plan.closed and count > 2) and count or count - 1
        while job.cursor <= pairs_total and used < budget do
            local a = built_entity(job.surface, plan.entities[members[job.cursor]])
            local b = built_entity(job.surface, plan.entities[members[job.cursor % count + 1]])
            if a and b then connect(a, b, true, chain.red, chain.green) end
            job.cursor = job.cursor + 1
            used = used + lib.COST.wire
        end
        if job.cursor > pairs_total then
            job.chain_cursor = job.chain_cursor + 1
            job.cursor = 1
        end
    end
    return used
end

--- Do up to about `budget` units of work: tiles, then entities, then wires.
--- @param job BuildJob
--- @param budget number
--- @return boolean done, number used
function lib.step(job, budget)
    local player = game.get_player(job.player_index)
    if not (player and player.valid and job.surface.valid and job.force.valid) then
        job.stage = "done"
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
