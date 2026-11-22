local vect = require("scripts.vector_math")

local lib = {}

lib.types = {
    "wall",
    "tile",
    "electric-pole",
    "electric-turret",
    "straight-rail",
    "roboport",
}

script.on_configuration_changed(
function()
    local entity_filter = {
        {filter="type", type=lib.types, mode="or"},
        {filter="blueprintable", mode="and"},
        {filter="hidden", invert=true, mode="and"},
    }

    local tile_filter = {
        {filter="blueprintable"},
    }

    local item_filter = {
        {filter = "place-result", elem_filters = entity_filter},
        {filter = "place-as-tile", elem_filters = tile_filter},
    }

    storage.item_filter = {{filter = "name", name = {}}}
    local items = prototypes.get_item_filtered(item_filter)
    for name, _ in pairs(items) do
        table.insert(storage.item_filter[1].name, name)
    end
end)

---@param name string
---@return LuaEntityPrototype|LuaTilePrototype
function lib.getBuildablePrototypeByName(name)
    local items = prototypes.get_item_filtered({{filter="name", name=name}})
    local item = items[name]
    if not item then
        error("No item found with name: "..name)
    end
    local entity_prototype = item.place_result
    if entity_prototype then
        return entity_prototype
    end
    local tile_prototype = item.place_as_tile_result
    if tile_prototype then
        return tile_prototype.result
    end
    error("No prototype found for item: "..name)
end

---@param name string|LuaQualityPrototype
---@return LuaQualityPrototype
function lib.getQualityPrototypeByName(name)
    local prototype = prototypes.quality[name]
    if not prototype then
        error("No quality prototype found with name: "..name)
    end
    return prototype
end

---@param prototype LuaEntityPrototype|LuaTilePrototype
---@return integer 
function lib.getPrototypeSize(prototype)
    if prototype.type == "tile" then
        return 1
    else
        local bbox = prototype.collision_box
        local left_top = vect.floor(bbox.left_top)
        local right_bottom = vect.ceil(bbox.right_bottom)
        local extent = vect.sub(right_bottom, left_top)
        return vect.max(extent)
    end
end

return lib