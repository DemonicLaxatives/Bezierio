--- Presets: named layer stacks. Each player has a list and edits the selected one
--- live (controller.presets[ui.preset_index]).
---
--- Export strings hold the layers as plain data: per layer the item, quality,
--- offset and the type's own settings (not derived values like size or wire reach,
--- which come from the prototypes when importing). Import rebuilds every layer the
--- way picking the item in the GUI does, so missing items, unknown qualities and
--- out-of-range values are handled the same way.
local registry = require("scripts.layers.registry")

local lib = {}

lib.FORMAT = "bezierio-preset"
lib.VERSION = 1
lib.MAX_PRESETS = 50
lib.MAX_NAME = 40
--- Layers further out than this are dropped on import.
lib.MAX_LAYER = 50

--- An integer, or nil (JSON numbers arrive as floats; Factorio's Lua has no
--- math.tointeger).
--- @param v any
--- @return integer|nil
local function int(v)
    if type(v) == "number" and v == math.floor(v) and v == v then return math.floor(v) end
    return nil
end

--- @generic T
--- @param value T
--- @return T
local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deep_copy(v) end
    return out
end

--- @param layers table<integer, Layer>
--- @return table<integer, Layer>
local function copy_layers(layers)
    return deep_copy(layers)
end

--- @param name string
--- @return string
function lib.clean_name(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", " ")
    if #name > lib.MAX_NAME then name = name:sub(1, lib.MAX_NAME) end
    return name
end

--- A name not used by any preset yet: `base`, else `base 2`, `base 3`, ...
--- @param presets Preset[]
--- @param base string
--- @return string
function lib.unique_name(presets, base)
    local used = {}
    for _, preset in ipairs(presets) do used[preset.name] = true end
    if not used[base] then return base end
    local n = 2
    while used[base .. " " .. n] do n = n + 1 end
    return base .. " " .. n
end

--- Add a new preset with an empty layer 0 and select it.
--- @param controller Controller
--- @return boolean added  # false when the list is full
function lib.new(controller)
    local presets = controller.presets
    if #presets >= lib.MAX_PRESETS then return false end
    table.insert(presets, { name = lib.unique_name(presets, "Preset"), layers = { [0] = registry.new_empty(0) } })
    controller.ui.preset_index = #presets
    return true
end

--- Add a copy of the selected preset and select it.
--- @param controller Controller
--- @return boolean added  # false when the list is full
function lib.duplicate(controller)
    local presets = controller.presets
    if #presets >= lib.MAX_PRESETS then return false end
    local current = presets[controller.ui.preset_index]
    table.insert(presets, { name = lib.unique_name(presets, current.name), layers = copy_layers(current.layers) })
    controller.ui.preset_index = #presets
    return true
end

--- @param controller Controller
--- @param name string
--- @return boolean renamed  # false for an empty name
function lib.rename(controller, name)
    name = lib.clean_name(name)
    if name == "" then return false end
    controller.presets[controller.ui.preset_index].name = name
    return true
end

--- Delete the selected preset; the one before it gets selected. The last preset
--- can't be deleted.
--- @param controller Controller
--- @return boolean deleted
function lib.delete(controller)
    local presets = controller.presets
    if #presets <= 1 then return false end
    table.remove(presets, controller.ui.preset_index)
    controller.ui.preset_index = math.max(1, math.min(controller.ui.preset_index - 1, #presets))
    return true
end

--- @param controller Controller
--- @param index integer
--- @return boolean switched
function lib.select(controller, index)
    if not controller.presets[index] or index == controller.ui.preset_index then return false end
    controller.ui.preset_index = index
    return true
end

--- Plain data for an export string.
--- @param preset Preset
--- @return table
function lib.to_data(preset)
    local layers = {}
    for idx, layer in pairs(preset.layers) do
        local entry = { idx = idx, offset = layer.offset }
        if layer.placed_by then
            entry.item = layer.placed_by
            entry.quality = layer.quality
            if layer.place == false then entry.place = false end
            for _, field in ipairs(registry.type_of(layer).fields) do
                entry[field.name] = layer[field.name]
            end
        end
        table.insert(layers, entry)
    end
    table.sort(layers, function(a, b) return a.idx < b.idx end)
    return { format = lib.FORMAT, version = lib.VERSION, name = preset.name, layers = layers }
end

--- @alias LayerMaker fun(idx: integer, item: string, quality: string): Layer|nil  # nil if the item can't be used

--- A preset from export data. Layers whose item is missing become empty layers
--- (listed in `missing`); gaps in the layer numbers are filled with empty layers.
--- @param data any
--- @param make_layer LayerMaker
--- @return Preset|nil preset, string[]|string missing_or_error
function lib.from_data(data, make_layer)
    if type(data) ~= "table" or data.format ~= lib.FORMAT or type(data.layers) ~= "table" then
        return nil, "not-a-preset"
    end
    if data.version ~= lib.VERSION then return nil, "unknown-version" end

    local layers, missing = {}, {}
    for _, entry in ipairs(data.layers) do
        local idx = type(entry) == "table" and int(entry.idx)
        if idx and math.abs(idx) <= lib.MAX_LAYER and not layers[idx] then
            -- Strings from before red and green wire were separate settings.
            if entry.connect_with_circuit_wires ~= nil and entry.red_wire == nil then
                entry.red_wire, entry.green_wire = entry.connect_with_circuit_wires, entry.connect_with_circuit_wires
            end
            local layer
            if type(entry.item) == "string" then
                layer = make_layer(idx, entry.item, type(entry.quality) == "string" and entry.quality or "normal")
                if not layer then table.insert(missing, entry.item) end
            end
            layer = layer or registry.new_empty(idx)
            entry.offset = int(entry.offset) or 0
            registry.carry_over(layer, entry)
            layers[idx] = layer
        end
    end
    local low, high = 0, 0
    for idx in pairs(layers) do
        low, high = math.min(low, idx), math.max(high, idx)
    end
    for idx = low, high do
        if not layers[idx] then layers[idx] = registry.new_empty(idx) end
    end
    local name = lib.clean_name(type(data.name) == "string" and data.name or "")
    return { name = name ~= "" and name or "Imported", layers = layers }, missing
end

-- Game-only parts (they use `helpers` and `prototypes`). --------------------------

--- @param preset Preset
--- @return string
function lib.export(preset)
    return helpers.encode_string(helpers.table_to_json(lib.to_data(preset))) --[[@as string]]
end

--- A layer for an item as the GUI picker makes it, or nil if the item is gone or
--- doesn't place anything Bézierio can build.
--- @type LayerMaker
local function make_layer(idx, item, quality)
    local prototype = prototypes.item[item]
    if not prototype or not (prototype.place_result or prototype.place_as_tile_result) then return nil end
    if not prototypes.quality[quality] then quality = "normal" end
    local ok, layer = pcall(registry.new_layer, idx, item, quality)
    if not ok or registry.type_of(layer).hidden then return nil end
    return layer
end

--- Add a preset from an export string and select it.
--- @param controller Controller
--- @param text string
--- @return boolean ok, string[]|string missing_or_error  # error: a locale key suffix
function lib.import(controller, text)
    if #controller.presets >= lib.MAX_PRESETS then return false, "too-many" end
    text = tostring(text or ""):gsub("%s", "")
    local json = text ~= "" and helpers.decode_string(text)
    local data = json and helpers.json_to_table(json)
    local preset, missing = lib.from_data(data, make_layer)
    if not preset then return false, missing end
    preset.name = lib.unique_name(controller.presets, preset.name)
    table.insert(controller.presets, preset)
    controller.ui.preset_index = #controller.presets
    return true, missing
end

return lib
