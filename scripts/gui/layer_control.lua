--- GUI actions for the layer list and detail pane (group = "layer").
local debug = require("scripts.debug")
local state = require("scripts.state")
local registry = require("scripts.layers.registry")
local layer_view = require("scripts.gui.layer_view")

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

--- Layers changed: plan again and rebuild the layer column.
--- @param player_index integer
local function layers_changed(player_index)
    state.changed(player_index)
    local player = game.get_player(player_index)
    if player then layer_view.refresh(player) end
end

--- A layer's item or settings button: open its settings window.
--- @param e EventData.on_gui_click
lib["select"] = function(e)
    local idx = tonumber(e.element.tags.idx)
    local player = game.get_player(e.player_index)
    if idx == nil or not player then return end
    layer_view.open_settings(player, idx)
end

--- @param e EventData.on_gui_click
lib["ok"] = function(e)
    local player = game.get_player(e.player_index)
    if player then layer_view.accept(player) end
end

--- @param e EventData.on_gui_click
lib["cancel"] = function(e)
    local player = game.get_player(e.player_index)
    if player then layer_view.cancel(player) end
end

--- @param e EventData.on_gui_click
lib["new_layer"] = function(e)
    local layers = state.layers(e.player_index)
    local direction = tonumber(e.element.tags.direction)
    if not direction then return end

    local min_key, max_key = key_bounds(layers)
    local key = direction == 1 and max_key + 1 or min_key - 1
    layers[key] = registry.new_empty(key)
    state.ui(e.player_index).selected_layer = key
    layers_changed(e.player_index)
    -- Pick its item and settings straight away (Cancel removes it again).
    local player = game.get_player(e.player_index)
    if player then layer_view.open_settings(player, key, true) end
end

--- Swap a layer with its neighbour; the selection follows the moved layer.
--- @param e EventData.on_gui_click
lib["move"] = function(e)
    local layers = state.layers(e.player_index)
    local idx = tonumber(e.element.tags.idx)
    local direction = tonumber(e.element.tags.direction)
    if not idx or not direction then return end
    local player = game.get_player(e.player_index)
    if player then layer_view.accept(player) end

    local other = idx + direction
    local layer_a, layer_b = layers[idx], layers[other]
    if not layer_a or not layer_b then return end

    layer_a.idx = other
    layer_b.idx = idx
    layers[idx] = layer_b
    layers[other] = layer_a
    local ui = state.ui(e.player_index)
    if ui.selected_layer == idx then
        ui.selected_layer = other
    elseif ui.selected_layer == other then
        ui.selected_layer = idx
    end
    layers_changed(e.player_index)
end

--- Remove a layer; the layers further out move one step inward.
--- @param e EventData.on_gui_click
lib["delete"] = function(e)
    local layers = state.layers(e.player_index)
    local idx = tonumber(e.element.tags.idx)
    if not idx or idx == 0 then return end
    local player = game.get_player(e.player_index)
    if player then layer_view.accept(player) end

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
    local ui = state.ui(e.player_index)
    if not layers[ui.selected_layer] then ui.selected_layer = 0 end
    layers_changed(e.player_index)
end

--- The item picker changed: replace the layer with a fresh one for that item,
--- keeping the settings it shares with the old one.
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
        layer = registry.new_layer(idx, item_name, quality_name)
    end
    registry.carry_over(layer, layers[idx])
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
    local player = game.get_player(e.player_index)
    if player then layer_view.sync_value(player, layer, field_name) end
    state.changed(e.player_index)
end

--- Show or hide a layer in the build preview (only the drawing changes).
--- @param e EventData.on_gui_click
lib["toggle_preview"] = function(e)
    local idx = tonumber(e.element.tags.idx)
    local layer = idx and state.layers(e.player_index)[idx]
    if not layer then return end
    if e.element.toggled then layer.preview = nil else layer.preview = false end
    state.request_redraw(e.player_index)
end

--- Place a layer or not (not placed: it keeps its room, builds nothing).
--- @param e EventData.on_gui_click
lib["toggle_place"] = function(e)
    local idx = tonumber(e.element.tags.idx)
    local layer = idx and state.layers(e.player_index)[idx]
    if not (layer and layer.placed_by) then return end
    if e.element.toggled then layer.place = nil else layer.place = false end
    layers_changed(e.player_index)
end

--- A drop-down setting (e.g. turret facing, lamp colour).
--- @param e EventData.on_gui_selection_state_changed
lib["set_choice"] = function(e)
    local field_name = e.element.tags.field --[[@as string]]
    local idx = tonumber(e.element.tags.idx)
    local layer = idx and state.layers(e.player_index)[idx]
    local field = layer and registry.field(layer, field_name)
    if not (field and field.widget == "choice") then return end
    local value = field.options[e.element.selected_index]
    if not value then return end
    layer[field_name] = value
    -- Other controls may depend on it (e.g. the rainbow length).
    layers_changed(e.player_index)
end

--- An item setting (turret ammo). Items the layer can't use are refused.
--- @param e EventData.on_gui_elem_changed
lib["set_item"] = function(e)
    local field_name = e.element.tags.field --[[@as string]]
    local idx = tonumber(e.element.tags.idx)
    local layer = idx and state.layers(e.player_index)[idx]
    local field = layer and registry.field(layer, field_name)
    if not (layer and field and field.widget == "item") then return end
    local value = e.element.elem_value --[[@as string?]]
    if value and field.valid and not field.valid(layer, value) then
        local player = game.get_player(e.player_index)
        if player then player.print({ "bezierio-message.item-not-usable", "[item=" .. value .. "]", "[item=" .. layer.placed_by .. "]" }) end
        e.element.elem_value = layer[field_name]
        return
    end
    layer[field_name] = value
    -- Derived values may depend on it (the inserter's reach).
    registry.refresh(layer)
    layers_changed(e.player_index)
end

--- @param e EventData.on_gui_checked_state_changed
lib["set_flag"] = function(e)
    local element = e.element
    local field_name = element.tags.field --[[@as string]]
    local idx = tonumber(element.tags.idx)
    local layer = idx and state.layers(e.player_index)[idx]
    if not layer then return end
    local field = registry.field(layer, field_name)
    if not (field and field.widget == "checkbox") then return end
    layer[field_name] = element.state
    -- (placed is the default: stored only when off)
    if field_name == "place" and element.state then layer.place = nil end
    layers_changed(e.player_index)
end

--- A turret's priority list: one picker changed (cleared ones close the gap).
--- @param e EventData.on_gui_elem_changed
lib["set_target"] = function(e)
    local element = e.element
    local field_name = element.tags.field --[[@as string]]
    local idx = tonumber(element.tags.idx)
    local index = tonumber(element.tags.index)
    local layer = idx and state.layers(e.player_index)[idx]
    local field = layer and registry.field(layer, field_name)
    if not (field and field.widget == "targets" and index) then return end
    local list = {}
    for i, name in ipairs(layer[field_name] or {}) do list[i] = name end
    list[index] = element.elem_value --[[@as string?]]
    local compact = {}
    for i = 1, registry.MAX_TARGETS do
        if list[i] then compact[#compact + 1] = list[i] end
    end
    layer[field_name] = #compact > 0 and compact or nil
    layers_changed(e.player_index)
end

return lib
