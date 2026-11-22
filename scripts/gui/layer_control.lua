--- GUI actions for the layer list (group = "layer").
local debug = require("scripts.debug")
local state = require("scripts.state")
local buildable_layers = require("scripts.gui.buildable_layers")
local buildable_types = require("scripts.build.buildable_types")
local buildable_utils = require("scripts.build.utils")

local lib = {}

--- @param data table<integer, any>
--- @return integer, integer
function lib.key_bounds(data)
    local min_key, max_key = 0, 0
    for k, _ in pairs(data) do
        if k > max_key then max_key = k end
        if k < min_key then min_key = k end
    end
    return min_key, max_key
end

--- Rebuild the layer list and request a preview redraw.
--- @param player_index integer
local function layers_changed(player_index)
    state.mark_dirty(player_index)
    local player = game.get_player(player_index)
    if not player then return end
    local window = player.gui.screen.bezierio_window
    if window then
        buildable_layers.add_layer_controls(window.main)
    end
end

--- @param e EventData.on_gui_click
lib["new_layer"] = function(e)
    local layers = state.layers(e.player_index)
    local direction = tonumber(e.element.tags.direction)
    if not direction then return end

    local min_key, max_key = lib.key_bounds(layers)
    local key = direction == 1 and max_key + 1 or min_key - 1
    layers[key] = buildable_types.contructNilBuildable(key)
    layers_changed(e.player_index)
end

--- Swap a layer with its neighbour.
--- @param e EventData.on_gui_click
lib["move"] = function(e)
    local layers = state.layers(e.player_index)
    local layer = tonumber(e.element.tags.idx)
    local direction = tonumber(e.element.tags.direction)
    if not layer or not direction then return end

    local other = layer + direction
    local buildable_a = layers[layer]
    local buildable_b = layers[other]
    if not buildable_a or not buildable_b then return end

    buildable_a.idx = other
    buildable_b.idx = layer
    layers[layer] = buildable_b
    layers[other] = buildable_a
    layers_changed(e.player_index)
end

--- Remove a layer; the layers further out move one step inward.
--- @param e EventData.on_gui_click
lib["delete"] = function(e)
    local layers = state.layers(e.player_index)
    local layer = tonumber(e.element.tags.idx)
    if not layer or layer == 0 then return end

    local min_key, max_key = lib.key_bounds(layers)
    if layer > 0 then
        for k = layer, max_key - 1 do
            layers[k] = layers[k + 1]
            layers[k].idx = k
        end
        layers[max_key] = nil
    else
        for k = layer, min_key + 1, -1 do
            layers[k] = layers[k - 1]
            layers[k].idx = k
        end
        layers[min_key] = nil
    end
    layers_changed(e.player_index)
end

--- The item picker changed: replace the layer with a fresh buildable of that type.
--- @param e EventData.on_gui_elem_changed
lib["type"] = function(e)
    local layers = state.layers(e.player_index)
    local layer = tonumber(e.element.tags.idx)
    if not layer then return end

    local value = e.element.elem_value --[[@as ItemIDAndQualityIDPair?]]
    ---@type Buildable
    local buildable = buildable_types.contructNilBuildable(layer)
    if value then
        local item_name = (type(value.name) == "string" and value.name or value.name.name) --[[@as string]]
        local quality = value.quality
        local quality_name = type(quality) == "string" and quality or (quality and quality.name) or "normal"
        buildable = buildable_types.constructBuildable {
            idx = layer,
            placed_by = item_name,
            prototype = buildable_utils.getBuildablePrototypeByName(item_name),
            quality = buildable_utils.getQualityPrototypeByName(quality_name).name,
            offset = layers[layer] and layers[layer].offset,
        }
    end
    layers[layer] = buildable
    layers_changed(e.player_index)
end

--- A slider moved or its number box was confirmed.
--- @param e EventData.on_gui_value_changed|EventData.on_gui_confirmed
lib["set_value"] = function(e)
    local element = e.element
    local field = element.tags.field --[[@as string]]
    local idx = tonumber(element.tags.idx)
    local layer = idx and state.layers(e.player_index)[idx]
    if not layer or type(layer[field]) ~= "number" then
        debug.print("Cannot set " .. tostring(field) .. " on layer " .. tostring(idx))
        return
    end

    local value
    if element.type == "slider" then
        value = element.slider_value
    else
        value = tonumber(element.text) or layer[field]
    end
    local min, max = buildable_types.fieldRange(layer, field)
    value = math.floor(value + 0.5)
    if min then value = math.max(min, value) end
    if max then value = math.min(max, value) end

    layer[field] = value
    buildable_layers.syncValue(element, field, value)
    state.mark_dirty(e.player_index)
end

--- @param e EventData.on_gui_checked_state_changed
lib["set_flag"] = function(e)
    local element = e.element
    local field = element.tags.field --[[@as string]]
    local idx = tonumber(element.tags.idx)
    local layer = idx and state.layers(e.player_index)[idx]
    if not layer or type(layer[field]) ~= "boolean" then return end
    layer[field] = element.state
    state.mark_dirty(e.player_index)
end

return lib
