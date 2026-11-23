--- Output: ghosts for robots (or the player) to build. Obstacles are marked for
--- deconstruction.
--- @type BuildOutput
return {
    name = "ghost",

    matching_tile_ghost = function(job, player, ghost)
        return "existing"
    end,

    place_tile = function(job, player, tile, undo_index)
        job.surface.create_entity {
            name = "tile-ghost", inner_name = tile.name, position = { x = tile.x + 0.5, y = tile.y + 0.5 },
            force = job.force, player = player, raise_built = true, undo_index = undo_index,
        }
    end,

    flush = function(job, player, undo_index) end,

    matching_entity_ghost = function(job, player, ghost)
        return "existing"
    end,

    clear = function(job, player, obstacle, undo_index)
        obstacle.order_deconstruction(job.force, player, undo_index)
    end,

    create_entity = function(job, player, entity, undo_index)
        local ghost = job.surface.create_entity {
            name = "entity-ghost", inner_name = entity.name, position = entity.position, quality = entity.quality,
            direction = entity.direction, color = entity.color, type = entity.belt_type,
            force = job.force, player = player, raise_built = true, undo_index = undo_index,
        }
        -- Ammo arrives with the robots that build it.
        if ghost and entity.ammo then
            local ammo = entity.ammo
            ghost.insert_plan = { {
                id = { name = ammo.name, quality = ammo.quality },
                items = { in_inventory = { { inventory = defines.inventory[ammo.inventory], stack = 0, count = ammo.count } } },
            } }
        end
        return ghost
    end,
}
