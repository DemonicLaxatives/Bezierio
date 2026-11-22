local vect = require("scripts.vector_math")

local lib = {}

--- Entity types that can be selected for a layer.
lib.types = {
    "wall",
    "electric-pole",
    "electric-turret",
    "straight-rail",
    "roboport",
}

--- Build the filter used by the layer item pickers: every item that places
--- a supported entity type or a tile.
--- @return ItemPrototypeFilter[]
function lib.build_item_filter()
    local entity_filter = {
        { filter = "type",          type = lib.types, mode = "or" },
        { filter = "blueprintable", mode = "and" },
        { filter = "hidden",        invert = true,    mode = "and" },
    }

    local tile_filter = {
        { filter = "blueprintable" },
    }

    local item_filter = {
        { filter = "place-result",  elem_filters = entity_filter },
        { filter = "place-as-tile", elem_filters = tile_filter },
    }

    local names = {}
    for name, _ in pairs(prototypes.get_item_filtered(item_filter)) do
        table.insert(names, name)
    end
    return { { filter = "name", name = names } }
end

--- @param item_name string
--- @return LuaEntityPrototype|LuaTilePrototype
function lib.getBuildablePrototypeByName(item_name)
    local item = prototypes.item[item_name]
    if not item then
        error("No item found with name: " .. item_name)
    end
    if item.place_result then
        return item.place_result
    end
    if item.place_as_tile_result then
        return item.place_as_tile_result.result
    end
    error("Item does not place anything: " .. item_name)
end

--- @param name string
--- @return LuaQualityPrototype
function lib.getQualityPrototypeByName(name)
    local prototype = prototypes.quality[name]
    if not prototype then
        error("No quality prototype found with name: " .. tostring(name))
    end
    return prototype
end

--- Footprint of a prototype in whole tiles (largest side).
--- @param prototype LuaEntityPrototype|LuaTilePrototype
--- @return integer
function lib.getPrototypeSize(prototype)
    if prototype.type == "tile" then
        return 1
    end
    local bbox = prototype.collision_box
    local left_top = vect.floor(bbox.left_top)
    local right_bottom = vect.ceil(bbox.right_bottom)
    local extent = vect.sub(right_bottom, left_top)
    return math.max(1, vect.max(extent))
end

return lib
