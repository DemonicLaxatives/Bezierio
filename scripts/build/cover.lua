--- Cover tiles (landfill, foundation, ice platform, space platform foundation):
--- what a force build lays first where the ground can't take what's planned, as
--- the game's own force build does (FFF-383).
---
--- All from the prototypes: an entity needs cover where a tile's collision mask
--- meets its own (water and walls both have `water_tile`). A tile item can go on a
--- tile when the tile's mask misses the item's `place_as_tile_result.condition`
--- (meets it, with `invert`) and, if `tile_condition` lists tiles, the tile is one
--- of them. Which cover: the first of the player's `cover_tiles` setting that can
--- go there and takes what's planned, else the tile's `default_cover_tile`
--- (landfill on water, foundation on lava, ...).
local lib = {}

--- @param a {layers: table<string, true>}|nil
--- @param b {layers: table<string, true>}|nil
--- @return boolean
function lib.masks_meet(a, b)
    local la, lb = a and a.layers, b and b.layers
    if not (la and lb) then return false end
    for layer in pairs(la) do
        if lb[layer] then return true end
    end
    return false
end

--- Can this tile item be placed on this tile?
--- @param item LuaItemPrototype
--- @param tile LuaTilePrototype
--- @return boolean
function lib.item_goes_on(item, tile)
    local r = item.place_as_tile_result
    if not r then return false end
    local hit = lib.masks_meet(tile.collision_mask, r.condition)
    if r.invert then
        if not hit then return false end
    elseif hit then
        return false
    end
    local list = r.tile_condition
    if list and #list > 0 then
        for _, t in pairs(list) do
            if t.name == tile.name then return true end
        end
        return false
    end
    return true
end

--- The item that places a tile (what robots bring).
--- @param tile LuaTilePrototype
--- @return string|nil
function lib.item_of(tile)
    local items = tile.items_to_place_this
    local first = items and items[1]
    return first and first.name or nil
end

--- The cover for a tile, as {tile = name, item = name}, or nil when none fits.
--- @param tile LuaTilePrototype      # what's there now
--- @param takes fun(cover: LuaTilePrototype): boolean  # what's planned can go on it
--- @param priority string[]|nil      # the player's cover items, in order
--- @return {tile: string, item: string}|nil
function lib.choose(tile, takes, priority)
    for _, name in ipairs(priority or {}) do
        local item = prototypes.item[name]
        local r = item and item.place_as_tile_result
        if r and lib.item_goes_on(item, tile) and takes(r.result) then
            return { tile = r.result.name, item = name }
        end
    end
    local default = tile.default_cover_tile
    local item = default and lib.item_of(default)
    if item and prototypes.item[item] and lib.item_goes_on(prototypes.item[item], tile) and takes(default) then
        return { tile = default.name, item = item }
    end
    return nil
end

--- Does an entity need cover on this tile?
--- @param entity LuaEntityPrototype
--- @param tile LuaTilePrototype
--- @return boolean
function lib.entity_needs(entity, tile)
    return lib.masks_meet(entity.collision_mask, tile.collision_mask)
end

return lib
