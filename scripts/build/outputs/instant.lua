--- Output: real entities and tiles, straight away (map editor, cheat mode).
--- Obstacles are removed; existing ghosts on the curve are revived.

--- Turret priorities and ammo, as planned.
--- @param built LuaEntity
--- @param entity PlannedEntity
local function finish(built, entity)
    if entity.priority_targets then
        for i, name in ipairs(entity.priority_targets) do built.set_priority_target(i, name) end
        built.ignore_unprioritised_targets = entity.ignore_unprioritised == true
    end
    if entity.ammo then
        local ammo = entity.ammo
        built.insert { name = ammo.name, quality = ammo.quality, count = ammo.count }
    end
end

--- @type BuildOutput
return {
    name = "instant",

    matching_tile_ghost = function(job, player, ghost)
        ghost.destroy()
        return nil -- carry on and set the tile
    end,

    place_tile = function(job, player, tile, undo_index)
        table.insert(job.tile_batch, { name = tile.name, position = { x = tile.x, y = tile.y } })
    end,

    flush = function(job, player, undo_index)
        if #job.tile_batch > 0 then
            job.surface.set_tiles(job.tile_batch, true, "abort_on_collision", true, true, player, undo_index)
            job.tile_batch = {}
        end
    end,

    matching_entity_ghost = function(job, player, ghost, entity)
        local _, revived, proxy = ghost.revive { raise_revive = true }
        -- (raise_revive: another mod may have removed it already)
        if not (revived and revived.valid) then return "existing" end
        -- The ghost's item request (our ammo, from a ghost build) is filled here.
        if entity.ammo and proxy and proxy.valid then proxy.destroy() end
        finish(revived, entity)
        return "placed", revived
    end,

    clear = function(job, player, obstacle, undo_index)
        obstacle.destroy { raise_destroy = true, player = player, undo_index = undo_index }
    end,

    create_entity = function(job, player, entity, undo_index)
        local built = job.surface.create_entity {
            name = entity.name, position = entity.position, quality = entity.quality,
            direction = entity.direction, color = entity.color, type = entity.belt_type,
            rail_layer = entity.rail_layer and defines.rail_layer[entity.rail_layer] or nil,
            force = job.force, player = player, raise_built = true, move_stuck_players = true,
            undo_index = undo_index,
        }
        -- (raise_built: another mod may have removed it already)
        if not (built and built.valid) then return nil end
        finish(built, entity)
        return built
    end,
}
