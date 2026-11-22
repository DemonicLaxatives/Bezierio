--- Layer types. Each type is defined in its own file in this folder and listed in
--- TYPE_FILES below; the planner, the layer GUI and the item picker only use this
--- module, so adding a type means adding a file.
---
--- Layers are plain data in `storage`. They name prototypes instead of holding them,
--- so a save survives other mods removing/renaming prototypes.
local lib = {}

---@class LayerField
---@field name string                                        # key in the layer table
---@field widget "slider"|"checkbox"
---@field min? integer|fun(layer: Layer): integer
---@field max? integer|fun(layer: Layer): integer
---@field default any|fun(layer: Layer): any
---@field labels? table<integer, LocalisedString>         # show words instead of numbers

---@class LayerType
---@field name string                       # stored as layer.type
---@field entity_types? string[]        # entity prototype types this layer type is used for
---@field tile? boolean                  # used for tiles
---@field hidden? boolean                # not offered in the item picker (not buildable yet)
---@field placement "band"|"spaced"|"none"|"unsupported"
---@field output? "entity"|"tile"
---@field priority integer                  # higher priority layers claim contested cells first
---@field fields LayerField[]               # editable settings, in GUI order
---@field init? fun(layer: Layer, prototype: LuaEntityPrototype|LuaTilePrototype)  # derived values
---@field thickness? fun(layer: Layer): number  # band width in grid units (default: footprint size)

---@class Layer
---@field idx integer          # 0 is centred on the curve, >0 to the right of travel, <0 to the left
---@field type string          # LayerType.name
---@field name string|nil      # entity or tile prototype name
---@field placed_by string|nil # item name
---@field quality string|nil   # quality name
---@field size integer         # footprint in tiles
---@field offset integer       # gap between this layer and the one closer to layer 0
---@field [string] any         # type-specific fields

local TYPE_FILES = {
    "scripts.layers.empty",
    "scripts.layers.wall",
    "scripts.layers.tile",
    "scripts.layers.electric_pole",
    "scripts.layers.electric_turret",
    "scripts.layers.roboport",
    "scripts.layers.rail",
}

--- @type table<string, LayerType>
lib.types = {}
--- @type table<string, LayerType>  # entity prototype type -> layer type
local by_entity_type = {}
--- @type LayerType|nil
local tile_type = nil

--- Shown for every layer except layer 0.
--- @type LayerField
lib.offset_field = { name = "offset", widget = "slider", min = 0, max = 10, default = 0 }

--- @param def LayerType
function lib.register(def)
    assert(not lib.types[def.name], "layer type registered twice: " .. def.name)
    lib.types[def.name] = def
    for _, entity_type in ipairs(def.entity_types or {}) do
        by_entity_type[entity_type] = def
    end
    if def.tile then tile_type = def end
end

for _, file in ipairs(TYPE_FILES) do
    lib.register(require(file))
end

--- @param layer Layer
--- @return LayerType
function lib.type_of(layer)
    local def = lib.types[layer.type]
    if not def then error("Unknown layer type: " .. tostring(layer.type)) end
    return def
end

--- @param layer_idx integer
--- @return Layer
function lib.new_empty(layer_idx)
    return { idx = layer_idx, type = "empty", size = 1, offset = 0 }
end

--- @param layer Layer
--- @param field LayerField
--- @param key "min"|"max"|"default"
local function resolve(layer, field, key)
    local value = field[key]
    if type(value) == "function" then return value(layer) end
    return value
end

--- Find a field definition by name (including the common offset field).
--- @param layer Layer
--- @param field_name string
--- @return LayerField|nil
function lib.field(layer, field_name)
    if field_name == "offset" then return lib.offset_field end
    for _, field in ipairs(lib.type_of(layer).fields) do
        if field.name == field_name then return field end
    end
    return nil
end

--- @param layer Layer
--- @param field_name string
--- @return integer|nil min, integer|nil max
function lib.field_range(layer, field_name)
    local field = lib.field(layer, field_name)
    if not field then return nil, nil end
    return resolve(layer, field, "min"), resolve(layer, field, "max")
end

--- Band width of a layer in grid units.
--- @param layer Layer
--- @return number
function lib.thickness(layer)
    local def = lib.type_of(layer)
    if def.thickness then return def.thickness(layer) end
    return layer.size or 1
end

-- Prototype helpers (runtime only: they use `prototypes`). -------------------

--- Footprint of a prototype in whole tiles (largest side).
--- Uses the prototype's grid footprint, not its collision box: rounding the box
--- outward makes 1x1 entities (poles, walls, boxes of ±0.15..0.29) look 2x2.
--- @param prototype LuaEntityPrototype|LuaTilePrototype
--- @return integer
function lib.footprint_size(prototype)
    if prototype.type == "tile" then return 1 end
    return math.max(1, prototype.tile_width, prototype.tile_height)
end

--- What an item places.
--- @param item_name string
--- @return LuaEntityPrototype|LuaTilePrototype
function lib.prototype_for_item(item_name)
    local item = prototypes.item[item_name]
    if not item then error("No item found with name: " .. item_name) end
    if item.place_result then return item.place_result end
    if item.place_as_tile_result then return item.place_as_tile_result.result end
    error("Item does not place anything: " .. item_name)
end

--- A new layer for an item picked in the GUI.
--- @param layer_idx integer
--- @param item_name string
--- @param quality_name string|nil
--- @param offset integer|nil
--- @return Layer
function lib.new_layer(layer_idx, item_name, quality_name, offset)
    local prototype = lib.prototype_for_item(item_name)
    local def = prototype.type == "tile" and tile_type or by_entity_type[prototype.type]
    if not def then error("Unsupported entity type: " .. prototype.type) end
    if quality_name and not prototypes.quality[quality_name] then
        error("No quality prototype found with name: " .. quality_name)
    end

    --- @type Layer
    local layer = {
        idx = layer_idx,
        type = def.name,
        name = prototype.name,
        placed_by = item_name,
        quality = quality_name or "normal",
        size = lib.footprint_size(prototype),
        offset = offset or 0,
    }
    if def.init then def.init(layer, prototype) end
    for _, field in ipairs(def.fields) do
        if layer[field.name] == nil then
            layer[field.name] = resolve(layer, field, "default")
        end
    end
    return layer
end

--- Filter for the layer item pickers: every item that places a supported entity
--- type or a tile.
--- @return ItemPrototypeFilter[]
function lib.build_item_filter()
    local entity_types = {}
    for entity_type, def in pairs(by_entity_type) do
        if not def.hidden then table.insert(entity_types, entity_type) end
    end
    table.sort(entity_types)

    local item_filter = {
        {
            filter = "place-result",
            elem_filters = {
                { filter = "type",          type = entity_types, mode = "or" },
                { filter = "blueprintable", mode = "and" },
                { filter = "hidden",        invert = true,       mode = "and" },
            },
        },
    }
    if tile_type then
        table.insert(item_filter, { filter = "place-as-tile", elem_filters = { { filter = "blueprintable" } } })
    end

    local names = {}
    for name in pairs(prototypes.get_item_filtered(item_filter)) do
        table.insert(names, name)
    end
    table.sort(names)
    return { { filter = "name", name = names } }
end

return lib
