--- Cover tiles (landfill, foundation, ice platform, concrete, ...): what a force
--- build lays first where the ground can't take what's planned, as the game's
--- own force build does (FFF-383).
---
--- All from the prototypes: an entity needs cover where a tile's collision mask
--- meets its own (water and walls both have `water_tile`; ice and heat-needing
--- entities both `meltable`). A tile item can go on a tile when the tile's mask
--- misses the item's `place_as_tile_result.condition` (meets it, with `invert`)
--- and, if `tile_condition` lists tiles, the tile is one of them.
---
--- Cover can take two layers: ammoniacal ocean takes an ice platform, which a
--- wall still can't stand on (`meltable`), so concrete goes on top. The choice
--- at each layer: the player's `cover_tiles` setting in order, then the tile's
--- `default_cover_tile` (landfill on water, foundation on lava, ice platform on
--- ammoniacal ocean, ...), then any tile item by its tile's `order` (stone path,
--- concrete, ..., the plainest first). Under a planned floor tile only foundation
--- tiles go (no concrete under a stone path).
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

--- Every tile item, by its tile's order (then name): the fallback choices.
--- (A per-session cache: prototypes don't change while the game runs.)
--- @type {tile: string, item: string}[]|nil
local all_items

--- @return {tile: string, item: string}[]
local function tile_items()
    if all_items then return all_items end
    all_items = {}
    for name, item in pairs(prototypes.item) do
        local r = item.place_as_tile_result
        if r and not item.hidden then all_items[#all_items + 1] = { tile = r.result.name, item = name, order = r.result.order or "" } end
    end
    table.sort(all_items, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.item < b.item
    end)
    return all_items
end

--- What can go on a tile, best first (see the top of this file).
--- @param tile LuaTilePrototype
--- @param priority string[]|nil
--- @param foundations_only boolean|nil
--- @return {tile: string, item: string}[]
function lib.candidates(tile, priority, foundations_only)
    local out, seen = {}, {}
    local function try(item_name)
        if seen[item_name] then return end
        seen[item_name] = true
        local item = prototypes.item[item_name]
        local r = item and item.place_as_tile_result
        if not r or not lib.item_goes_on(item, tile) then return end
        if foundations_only and not r.result.is_foundation then return end
        out[#out + 1] = { tile = r.result.name, item = item_name }
    end
    for _, name in ipairs(priority or {}) do try(name) end
    local default = tile.default_cover_tile
    local default_item = default and lib.item_of(default)
    if default_item then try(default_item) end
    for _, entry in ipairs(tile_items()) do try(entry.item) end
    return out
end

--- The cover for a tile: the tiles to lay, bottom first (one or two), or nil when
--- nothing fits.
--- @param tile LuaTilePrototype      # what's there now
--- @param takes fun(cover: LuaTilePrototype): boolean  # what's planned can go on it
--- @param priority string[]|nil      # the player's cover items, in order
--- @param foundations_only boolean|nil  # (under a planned floor tile)
--- @return {tile: string, item: string}[]|nil
function lib.choose(tile, takes, priority, foundations_only)
    local first = lib.candidates(tile, priority, foundations_only)
    for _, c in ipairs(first) do
        if takes(prototypes.tile[c.tile]) then return { c } end
    end
    for _, c in ipairs(first) do
        for _, c2 in ipairs(lib.candidates(prototypes.tile[c.tile], priority, foundations_only)) do
            if takes(prototypes.tile[c2.tile]) then return { c, c2 } end
        end
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
