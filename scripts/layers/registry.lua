--- Layer types. Each type is defined in its own file in this folder and listed in
--- TYPE_FILES below; the planner, the layer GUI and the item picker only use this
--- module, so adding a type means adding a file.
---
--- Layers are plain data in `storage`. They name prototypes instead of holding them,
--- so a save survives other mods removing/renaming prototypes.
local lib = {}

---@class LayerField
---@field name string                                        # key in the layer table
---@field widget "slider"|"checkbox"|"choice"|"item"|"targets"  # targets: a list of entity names (turret priorities)
---@field options? string[]                              # choice: the values, in menu order (labels: label_prefix .. value)
---@field label_prefix? string                           # choice: locale section for the option labels
---@field item_filters? table                            # item: elem_filters for the picker
---@field visible_if? fun(layer: Layer): boolean          # hide the control when false
---@field valid? fun(layer: Layer, value: any): boolean    # item: whether the layer can use it
---@field min? integer|fun(layer: Layer): integer
---@field max? integer|fun(layer: Layer): integer
---@field default any|fun(layer: Layer): any
---@field labels? table<integer, LocalisedString>         # show words instead of numbers
---@field disabled_by? string                             # a checkbox field that makes this one irrelevant

---@class LayerType
---@field name string                       # stored as layer.type
---@field entity_types? string[]        # entity prototype types this layer type is used for
---@field tile? boolean                  # used for tiles
---@field hidden? boolean                # not offered in the item picker (not buildable yet)
---@field placement "band"|"spaced"|"path"|"rail"|"none"|"unsupported"
---@field output? "entity"|"tile"
---@field priority integer                  # higher priority layers claim contested cells first
---@field fields LayerField[]               # editable settings, in GUI order
---@field init? fun(layer: Layer, prototype: LuaEntityPrototype|LuaTilePrototype)  # derived values
---@field keep? fun(layer: Layer, x: integer, y: integer): boolean  # band layers: whether a cell gets one (default: the checkerboard)
---@field decorate? fun(layer: Layer, entity: PlannedEntity, info: PlacementInfo)  # spaced layers: direction, colour, ammo, ...
---@field attach? fun(layer: Layer, entity: PlannedEntity, ctx: FeedContext)  # spaced layers: what goes with each entity (turret feeds)
---@field wants_feed? fun(layer: Layer): boolean  # spaced layers: whether each entity gets a feed (attach)
---@field can_attach? fun(layer: Layer, entity: PlannedEntity, ctx: FeedContext): boolean  # ... and whether it fits there
---@field thickness? fun(layer: Layer): number  # band width in grid units (default: footprint size)
---@field join_corners? boolean        # band layers: cells meeting only at a corner get a corner cell (walls; not with a checkerboard)

---@class Layer
---@field idx integer          # 0 is centred on the curve, >0 to the right of travel, <0 to the left
---@field type string          # LayerType.name
---@field name string|nil      # entity or tile prototype name
---@field placed_by string|nil # item name
---@field quality string|nil   # quality name
---@field size integer         # footprint in tiles
---@field needs_power boolean|nil  # runs on electricity (smart pole placement powers it)
---@field preview false|nil    # false: not drawn in the build preview (still built)
---@field offset integer       # gap between this layer and the one closer to layer 0
---@field [string] any         # type-specific fields

---@class PlacementInfo
---@field outward Vector    # unit vector away from the curve on the layer's side (layer 0: layer 1's side)
---@field arc number|nil    # distance along the curve where it was aimed

local TYPE_FILES = {
    "scripts.layers.empty",
    "scripts.layers.wall",
    "scripts.layers.tile",
    "scripts.layers.electric_pole",
    "scripts.layers.electric_turret",
    "scripts.layers.turret",
    "scripts.layers.roboport",
    "scripts.layers.solar_panel",
    "scripts.layers.accumulator",
    "scripts.layers.radar",
    "scripts.layers.lamp",
    "scripts.layers.land_mine",
    "scripts.layers.belt",
    "scripts.layers.pipe",
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

--- Every layer with an item: placed (default) or not. A layer that isn't placed
--- still takes up its room in the plan, so the layers outside it stay where they are.
lib.place_field = { name = "place", widget = "checkbox", default = true }

--- Most entries in a turret's targeting priority list.
lib.MAX_TARGETS = 8

--- Entity types a turret's priority list may hold: enemies and asteroids.
lib.TARGET_TYPES = { "unit", "unit-spawner", "turret", "spider-unit", "segmented-unit", "asteroid" }

--- Whether an entity may be a priority target (always, outside the game).
--- @param name any
--- @return boolean
function lib.is_target(name)
    if type(name) ~= "string" then return false end
    if not prototypes then return true end
    local prototype = prototypes.entity[name]
    if not prototype then return false end
    for _, t in ipairs(lib.TARGET_TYPES) do
        if prototype.type == t then return true end
    end
    return false
end


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
    if field_name == "place" then return lib.place_field end
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

--- A number for a slider field: whole, within the field's range (nil: not a number).
--- @param layer Layer
--- @param field LayerField
--- @param value any
--- @return integer|nil
local function slider_value(layer, field, value)
    if type(value) ~= "number" or value ~= value then return nil end -- (NaN)
    local min, max = resolve(layer, field, "min"), resolve(layer, field, "max")
    if min then value = math.max(min, value) end
    if max then value = math.min(max, value) end
    if value == math.huge or value == -math.huge then return nil end
    return math.floor(value + 0.5)
end

--- Keep the settings of `old` that `layer`'s type also has (same field name and
--- value type), clamped to the new ranges: switching a layer to another quality or
--- a similar item shouldn't reset its width, spacing, etc. Offset always carries.
--- @param layer Layer  # freshly made, with defaults
--- @param old Layer|nil
function lib.carry_over(layer, old)
    if not old then return end
    -- (values may come from an import string: checked like the GUI would)
    layer.offset = slider_value(layer, lib.offset_field, old.offset) or layer.offset
    if old.place == false and layer.placed_by then layer.place = false end
    for _, field in ipairs(lib.type_of(layer).fields) do
        local value = old[field.name]
        if field.widget == "targets" then
            -- A list of entity names: only strings, at most MAX_TARGETS, ones that exist.
            local list = nil
            if type(value) == "table" then
                list = {}
                for _, name in ipairs(value) do
                    if #list < lib.MAX_TARGETS and lib.is_target(name) then list[#list + 1] = name end
                end
                if #list == 0 then list = nil end
            end
            value = nil
            layer[field.name] = list
        end
        if field.widget == "item" and value ~= nil
            and (type(value) ~= "string" or (field.valid and not field.valid(layer, value))) then
            value = nil
        end
        if field.widget == "choice" and value ~= nil then
            local valid = false
            for _, option in ipairs(field.options) do if option == value then valid = true end end
            if not valid then value = nil end
        end
        if value ~= nil and (type(value) == type(layer[field.name]) or (field.widget == "item" and type(value) == "string")) then
            if type(value) == "number" then value = slider_value(layer, field, value) end
            if value ~= nil then layer[field.name] = value end
        end
    end
end

--- Band width of a layer in grid units.
--- @param layer Layer
--- @return number
function lib.thickness(layer)
    local def = lib.type_of(layer)
    if def.thickness then return def.thickness(layer) end
    return layer.size or 1
end

--- A tile layer laid under the other layers instead of beside them.
--- @param layer Layer
--- @return boolean
function lib.is_underlay(layer)
    return layer.under == true and lib.type_of(layer).tile == true
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
    lib.refresh(layer, prototype)
    for _, field in ipairs(def.fields) do
        if layer[field.name] == nil then
            layer[field.name] = resolve(layer, field, "default")
        end
    end
    lib.check_fields(layer) -- (a default may lie outside the range, e.g. for a big lamp)
    return layer
end

--- Recompute the values a layer derives from its prototype (size, wire reach,
--- whether it needs power, ...). Run for new layers and, for saved ones, when mods
--- or prototypes change. Settings the player chose are left alone, except for
--- clamping them into ranges that depend on the derived values.
--- @param layer Layer
--- @param prototype LuaEntityPrototype|LuaTilePrototype|nil  # looked up by name if nil
--- @return boolean  # false if the prototype is gone
function lib.refresh(layer, prototype)
    if not layer.name then return true end
    if not prototype then
        prototype = layer.type == "tile" and prototypes.tile[layer.name] or prototypes.entity[layer.name]
        if not prototype then return false end
    end
    -- (mods may have removed the item that placed it, or its quality)
    if layer.placed_by and prototypes.item and not prototypes.item[layer.placed_by] then return false end
    if layer.quality and prototypes.quality and not prototypes.quality[layer.quality] then layer.quality = "normal" end
    local def = lib.type_of(layer)
    layer.size = lib.footprint_size(prototype)
    -- (non-square: placed on their own grid, common.fit_footprint)
    local square = prototype.type == "tile" or prototype.tile_width == prototype.tile_height
    layer.tile_w = (not square) and prototype.tile_width or nil
    layer.tile_h = (not square) and prototype.tile_height or nil
    layer.needs_power = prototype.type ~= "tile" and prototype.electric_energy_source_prototype ~= nil or nil
    if def.init then def.init(layer, prototype) end
    lib.check_fields(layer)
    return true
end

--- Keep a layer's settings within what its fields allow now: numbers clamped,
--- items and priority targets that are gone (or no longer fit) dropped.
--- @param layer Layer
function lib.check_fields(layer)
    for _, field in ipairs(lib.type_of(layer).fields) do
        local value = layer[field.name]
        if type(value) == "number" then
            local min, max = resolve(layer, field, "min"), resolve(layer, field, "max")
            if min then value = math.max(min, value) end
            if max then value = math.min(max, value) end
            layer[field.name] = value
        elseif field.widget == "item" and value ~= nil then
            if prototypes and (type(value) ~= "string" or not prototypes.item[value]
                    or (field.valid and not field.valid(layer, value))) then
                layer[field.name] = nil
            end
        elseif field.widget == "targets" and type(value) == "table" then
            local list = {}
            for _, name in ipairs(value) do
                if lib.is_target(name) and #list < lib.MAX_TARGETS then list[#list + 1] = name end
            end
            layer[field.name] = #list > 0 and list or nil
        end
    end
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
