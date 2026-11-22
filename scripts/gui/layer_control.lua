local debug = require("scripts.debug")
local build = {}
local buildable_layers = require("scripts.gui.buildable_layers")
local buildable_types = require("scripts.build.buildable_types")
local buildable_utils = require("scripts.build.utils")
local util = require("__core__.lualib.util")

local lib = {}

--- @param data table<integer, any>
--- @return integer, integer
function lib.key_bounds(data)
    local min_key = math.huge
    local max_key = -math.huge

    for k, _ in pairs(data) do
        if k > max_key then
            max_key = k
        end
        if k < min_key then
            min_key = k
        end
    end

    return min_key, max_key
end

--- @param e EventData.on_gui_click
lib["new_layer"] = function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local element = e.element
    local frame = player.gui.screen.bezierio_window.main

    local layers = storage.controllers[player.index].state.layers
    local direction = tonumber(element.tags.direction)
    if not direction then
        debug.print("Could not determine direction from element tags")
        return
    end

    local min_key, max_key = lib.key_bounds(layers)

    local key = 0
    if direction == 1 then
        key = max_key + 1
    else
        key = min_key - 1
    end

    layers[key] = buildable_types.contructNilBuildable(key)
    buildable_layers.add_layer_controls(frame)
end

--- @param e EventData.on_gui_click
lib["move"] = function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local element = e.element
    local frame = player.gui.screen.bezierio_window.main

    local layers = storage.controllers[player.index].state.layers
    local layer = tonumber(element.tags.idx)
    if not layer then
        debug.print("Could not determine layer number from element tags")
        return
    end

    local direction = element.tags.direction
    if not direction then
        debug.print("Could not determine direction from element tags")
        return
    end

    local buildable_a = util.table.deepcopy(layers[layer])
    local buildable_b = util.table.deepcopy(layers[layer + direction])

    if not buildable_b then
        debug.print("Could not find buildable for layer "..layer + direction)
        return
    end

    buildable_a.idx = layer + direction
    buildable_b.idx = layer

    layers[layer] = buildable_b
    layers[layer + direction] = buildable_a

    buildable_layers.add_layer_controls(frame)
end

--- @param e EventData.on_gui_click
lib["delete"]= function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local element = e.element
    local frame = player.gui.screen.bezierio_window.main

    local layers = storage.controllers[player.index].state.layers
    local layer = tonumber(element.tags.idx)
    if not layer then
        debug.print("Could not determine layer number from element tags")
        return
    end

    local layer = tonumber(e.element.tags.idx)
    if not layer and (layer ~= 0)then
        debug.print("Could not determine layer number from element tags")
        return
    end

    if layer == 0 then
        debug.print("Cannot delete layer 0")
        return
    end

    local min_key = 0
    local max_key = 0

    for k, _ in pairs(layers) do
        if k > max_key then
            max_key = k
        end
        if k < min_key then
            min_key = k
        end
    end

    local tmp_layer = nil
    if layer > 0 then

        for k = layer, max_key - 1 do
            tmp_layer = util.table.deepcopy(layers[k + 1])
            tmp_layer.idx = k
            layers[k] = tmp_layer
        end
        layers[max_key] = nil
    else
        for k = layer, min_key + 1, -1 do
            tmp_layer = util.table.deepcopy(layers[k - 1])
            tmp_layer.idx = k
            layers[k] = tmp_layer
        end
        layers[min_key] = nil
    end

    buildable_layers.add_layer_controls(frame)
end

--- @param e EventData.on_gui_elem_changed
lib["type"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local element = e.element
    local frame = player.gui.screen.bezierio_window.main

    local layers = storage.controllers[player.index].state.layers
    local layer = tonumber(element.tags.idx)
    if not layer then
        debug.print("Could not determine layer number from element tags")
        return
    end

    local layer = tonumber(e.element.tags.idx)
    if not layer then
        debug.print("Could not determine layer number from element tags")
        return
    end

    local value = element.elem_value
    local buildable = buildable_types.contructNilBuildable(layer)
    if value then
        local prototype = buildable_utils.getBuildablePrototypeByName(value.name)
        local quality = buildable_utils.getQualityPrototypeByName(value.quality)
        local parms = {
            idx = layer,
            name = value.name,
            prototype = prototype,
            quality = quality
        }
        buildable = buildable_types.constructBuildable(layer, value.name, prototype, quality)
    end

    layers[layer] = buildable

    buildable_layers.add_layer_controls(frame)

end

return lib