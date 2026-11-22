--- GUI actions for the layer list (group = "layer").
local debug = require("scripts.debug")
local state = require("scripts.state")
local registry = require("scripts.layers.registry")
local layer_rows = require("scripts.gui.layer_rows")

local lib = {}

--- @param layers table<integer, Layer>
--- @return integer min_key, integer max_key
local function key_bounds(layers)
    local min_key, max_key = 0, 0
    for k in pairs(layers) do
        if k > max_key then max_key = k end
        if k < min_key then min_key = k end
    end
    return min_key, max_key
end

--- Layers changed: plan again and rebuild the layer list.
--- @param player_index integer
local function layers_changed(player_index)
    state.changed(player_index)
    local player = game.get_player(player_index)
    if not player then return end
    local window = player.gui.screen.bezierio_window
    if window then
        layer_rows.add_layer_rows(window.main)
    end
end

--- @param e EventData.on_gui_click
lib["new_layer"] = function(e)
    local layers = state.layers(e.player_index)
    local direction = tonumber(e.element.tags.direction)
    if not direction then return end

    local min_key, max_key = key_bounds(layers)
    local key = direction == 1 and max_key + 1 or min_key - 1
    layers[key] = registry.new_empty(key)
    layers_changed(e.player_index)
end

--- Swap a layer with its neighbour.
--- @param e EventData.on_gui_click
lib["move"] = function(e)
    local layers = state.layers(e.player_index)
    local idx = tonumber(e.element.tags.idx)
    local direction = tonumber(e.element.tags.direction)
    if not idx or not direction then return end

    local other = idx + direction
    local layer_a, layer_b = layers[idx], layers[other]
    if not layer_a or not layer_b then return end

    layer_a.idx = other
    layer_b.idx = idx
    layers[idx] = layer_b
    layers[other] = layer_a
    layers_changed(e.player_index)
end

--- Remove a layer; the layers further out move one step inward.
--- @param e EventData.on_gui_click
lib["delete"] = function(e)
    local layers = state.layers(e.player_index)
    local idx = tonumber(e.element.tags.idx)
    if not idx or idx == 0 then return end

    local min_key, max_key = key_bounds(layers)
    if idx > 0 then
        for k = idx, max_key - 1 do
            layers[k] = layers[k + 1]
            layers[k].idx = k
        end
        layers[max_key] = nil
    else
        for k = idx, min_key + 1, -1 do
            layers[k] = layers[k - 1]
            layers[k].idx = k
        end
        layers[min_key] = nil
    end
    layers_changed(e.player_index)
end

--- The item picker changed: replace the layer with a fresh one for that item.
--- @param e EventData.on_gui_elem_changed
lib["type"] = function(e)
    local layers = state.layers(e.player_index)
    local idx = tonumber(e.element.tags.idx)
    if not idx then return end

    local value = e.element.elem_value --[[@as ItemIDAndQualityIDPair?]]
    local layer = registry.new_empty(idx)
    if value then
        local item_name = (type(value.name) == "string" and value.name or value.name.name) --[[@as string]]
        local quality = value.quality
        local quality_name = type(quality) == "string" and quality or (quality and quality.name) or "normal"
        layer = registry.new_layer(idx, item_name, quality_name, layers[idx] and layers[idx].offset)
    end
    layers[idx] = layer
    layers_changed(e.player_index)
end

--- A slider moved or its number box was confirmed.
--- @param e EventData.on_gui_value_changed|EventData.on_gui_confirmed
lib["set_value"] = function(e)
    local element = e.element
    local field_name = element.tags.field --[[@as string]]
    local idx = tonumber(element.tags.idx)
    local layer = idx and state.layers(e.player_index)[idx]
    if not layer or type(layer[field_name]) ~= "number" then
        debug.print("Cannot set " .. tostring(field_name) .. " on layer " .. tostring(idx))
        return
    end

    local value
    if element.type == "slider" then
        value = element.slider_value
    else
        value = tonumber(element.text) or layer[field_name]
    end
    local min, max = registry.field_range(layer, field_name)
    value = math.floor(value + 0.5)
    if min then value = math.max(min, value) end
    if max then value = math.min(max, value) end

    layer[field_name] = value
    layer_rows.sync_value(element, layer, field_name)
    state.changed(e.player_index)
end

--- @param e EventData.on_gui_checked_state_changed
lib["set_flag"] = function(e)
    local element = e.element
    local field_name = element.tags.field --[[@as string]]
    local idx = tonumber(element.tags.idx)
    local layer = idx and state.layers(e.player_index)[idx]
    if not layer or type(layer[field_name]) ~= "boolean" then return end
    layer[field_name] = element.state
    state.changed(e.player_index)
end

return lib
