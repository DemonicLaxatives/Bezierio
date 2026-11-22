--- Builds a plan into the world, as a resumable job.
---
--- What "building" means is up to the output module (outputs/*.lua): ghosts, or
--- real entities in the map editor / cheat mode. This module does what they share:
--- skipping what's already there, the placement check, and finding obstacles.
local lib = {}

--- @alias BezierioBuildMode "forced"|"superforced"

--- @class BuildOutput
--- @field name string
--- @field matching_tile_ghost fun(job: BuildJob, player: LuaPlayer, ghost: LuaEntity): "existing"|nil
--- @field place_tile fun(job: BuildJob, player: LuaPlayer, tile: PlannedTile)
--- @field flush fun(job: BuildJob, player: LuaPlayer)
--- @field matching_entity_ghost fun(job: BuildJob, player: LuaPlayer, ghost: LuaEntity): "placed"|"existing"
--- @field clear fun(job: BuildJob, player: LuaPlayer, obstacle: LuaEntity)
--- @field create_entity fun(job: BuildJob, player: LuaPlayer, entity: PlannedEntity): LuaEntity|nil

--- @type table<string, BuildOutput>
lib.outputs = {
    ghost = require("scripts.build.outputs.ghost"),
    instant = require("scripts.build.outputs.instant"),
}

--- Work units per placement, for budgeting.
lib.COST = { tile = 3, entity = 6 }

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
--- @field stage "tiles"|"entities"|"done"
--- @field cursor integer
--- @field tile_batch Tile[]      # used by the instant output
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
    return {
        player_index = player.index,
        surface = player.surface,
        force = player.force --[[@as LuaForce]],
        mode = mode,
        output = lib.builds_instantly(player) and "instant" or "ghost",
        plan = plan,
        stage = "tiles",
        cursor = 1,
        tile_batch = {},
        result = { placed = 0, existing = 0, blocked = 0 },
    }
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
    output.place_tile(job, player, tile)
    result.placed = result.placed + 1
end

--- @param job BuildJob
--- @param player LuaPlayer
--- @param output BuildOutput
--- @param entity PlannedEntity
local function build_entity(job, player, output, entity)
    local surface, force, result = job.surface, job.force, job.result
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

    local box = prototype.collision_box
    local area = {
        left_top = { x = position.x + box.left_top.x, y = position.y + box.left_top.y },
        right_bottom = { x = position.x + box.right_bottom.x, y = position.y + box.right_bottom.y },
    }

    if job.mode == "superforced" then
        for _, other in pairs(surface.find_entities_filtered { area = area }) do
            if other.valid then
                if other.type == "entity-ghost" then
                    other.destroy()
                elseif not IGNORED_IN_THE_WAY[other.type]
                    and (other.force == force or other.force.name == "neutral") then
                    output.clear(job, player, other)
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
            output.clear(job, player, other)
        end
    end

    if output.create_entity(job, player, entity) then
        result.placed = result.placed + 1
    else
        result.blocked = result.blocked + 1
    end
end

--- Do up to about `budget` units of work. Tiles go first, then entities.
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
        output.flush(job, player)
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
            job.stage = "done"
        end
    end
    return job.stage == "done", used
end

return lib
