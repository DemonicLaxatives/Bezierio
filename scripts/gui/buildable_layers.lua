local buildable_types = require("scripts.build.buildable_types")
local debug = require("scripts.debug")

local lib = {}

---@param flow LuaGuiElement
---@param name string
---@param tags table
---@param min number
---@param max number
---@param value number
function lib.setupSliderTextBoxPair(flow, name, tags, min, max, value, tooltip)
    
    local frame = flow.add {
        type = "frame",
        name = name.."_frame",
        tags = tags,
        direction = "vertical"
    }

    local labels = frame.add {
        type = "flow",
        name = name.."_labels",
        tags = tags,
        direction = "horizontal"
    }

    labels.add {
        type = "label",
        name = "label",
        caption = {"slider-caption."..name},
        tooltip = {"tooltip."..tooltip}
    }

    local text = ""
    local widhth = 40
    local numeric = true
    local read_only = false
    if tags.values then
        text = tags.values[value]
        widhth = 80
        read_only = true
        numeric = false
    else
        text = tostring(value)
    end

    local indicator = labels.add {
        type = "text-box",
        name = "slider_indicator",
        tags = tags,
        text = text,
        numeric = numeric,
        read_only = read_only,
        allow_decimal = false,
        allow_blank = false
    }
    indicator.style.width = widhth

    local slider_flow = frame.add {
        type = "flow",
        name = name.."_slider_flow",
        direction = "horizontal"
    }

    slider_flow.add {
        type = "label",
        name = "min",
        caption = min
    }

    local slider = slider_flow.add {
        type = "slider",
        name = name,
        tags = tags,
        minimum_value = min,
        maximum_value = max,
        value = value,
    }
    slider.style.width = 100

    slider_flow.add {
        type = "label",
        name = "max",
        caption = max
    }
    return frame
end

---@param flow LuaGuiElement
---@param buildable BaseBuildable
function lib.setupBaseBuildableGuiFrame(flow, buildable)
    if #flow.children > 0 then
        flow.clear()
    end

    flow.add{
        type = "label",
        caption = {"label.layer", buildable.idx}
    }

    local up = flow.add{
        type = "sprite-button",
        name = "layer_move_up",
        tags = {group = "layer", action = "move", direction = 1, idx = buildable.idx},
        sprite = "utility/hint_arrow_up",
        tooltip = {"button.move-layer-up"}
    }

    up.style.width = 30

    local down = flow.add{
        type = "sprite-button",
        name = "layer_move_down",
        tags = {group = "layer", action = "move", direction = -1, idx = buildable.idx},
        sprite = "utility/hint_arrow_down",
        tooltip = {"button.move-layer-down"}
    }

    down.style.width = 30

    flow.add{
        type = "sprite-button",
        name = "layer_delete",
        tags = {group = "layer", action = "delete", idx = buildable.idx},
        sprite = "utility/trash",
        tooltip = {"button.delete-layer"}
    }

    local quality = buildable.quality
    local quality_name = nil
    if quality then
        quality_name = quality.name
    end

    flow.add{
        type = "choose-elem-button",
        name = "layer_type",
        tags = {group = "layer", action = "type", idx = buildable.idx},
        elem_type = "item-with-quality",
        elem_filters = storage.item_filter,
        ---@diagnostic disable-next-line
        ["item-with-quality"] = {name = buildable.placed_by, quality = quality_name}
    }

    if buildable.idx ~= 0 then
        local offset_frame = lib.setupSliderTextBoxPair(
            flow, "offset",
            {group = "layer", action = "offset", idx = buildable.idx},
            0, 10, buildable.offset,
            "offset")
    end
end

---@param flow LuaGuiElement
---@param buildable Wall
function lib.setupWallGuiFrame(flow, buildable)
    lib.setupBaseBuildableGuiFrame(flow, buildable)

    lib.setupSliderTextBoxPair(
        flow, "checkerboard",
        {group = "layer", action = "checkerboard_changed", idx = buildable.idx},
        -10, 10, buildable.checkerboard,
        "checkerboard")


    lib.setupSliderTextBoxPair(
        flow, "radius",
        {group = "layer", action = "radius_changed", idx = buildable.idx},
        1, 10, buildable.radius,
        "radius")
end

---@param flow LuaGuiElement
---@param buildable Tile
function lib.setupTileGuiFrame(flow, buildable)
    lib.setupBaseBuildableGuiFrame(flow, buildable)

    lib.setupSliderTextBoxPair(
        flow, "checkerboard",
        {group = "layer", action = "checkerboard_changed", idx = buildable.idx},
        -10, 10, buildable.checkerboard, 
        "checkerboard")


    lib.setupSliderTextBoxPair(
        flow, "radius",
        {group = "layer", action = "radius_changed", idx = buildable.idx},
        1, 10, buildable.radius, 
        "radius")
end


---@param flow LuaGuiElement
---@param buildable ElectricPole
function lib.setupElectricPoleGuiFrame(flow, buildable)
    lib.setupBaseBuildableGuiFrame(flow, buildable)

    lib.setupSliderTextBoxPair(
        flow, "spacing",
        {group = "layer", action = "spacing", idx = buildable.idx},
        buildable.size, buildable.wire_distance, buildable.spacing,
        "spacing")

    flow.add {
        type = "checkbox",
        name = "smart_placement",
        caption = {"checkbox.smart-placement"},
        state = buildable.smart_placement,
    }

    flow.add {
        type = "checkbox",
        name = "connect_with_circuit_wires",
        caption = {"checkbox.connect-with-circuit-wires"},
        state = buildable.connect_with_circuit_wires,
    }
end

---@param flow LuaGuiElement
---@param buildable ElectricTurret
function lib.setupElectricTurretGuiFrame(flow, buildable)
    lib.setupBaseBuildableGuiFrame(flow, buildable)

    lib.setupSliderTextBoxPair(
        flow, "spacing",
        {group = "layer", action = "spacing", idx = buildable.idx},
        buildable.size, 10, buildable.spacing,
        "spacing")
end

---@param flow LuaGuiElement
---@param buildable Rail
function lib.setupRailGuiFrame(flow, buildable)
    lib.setupBaseBuildableGuiFrame(flow, buildable)


    lib.setupSliderTextBoxPair(
        flow, "direction-of-travel",
        {group = "layer", action = "direction_of_travel", idx = buildable.idx, values = {[-1] = "backwards", [0] = "neither", [1] = "forwards"}},
        -1, 1, buildable.direction_of_travel,
        "direction-of-travel")

    lib.setupSliderTextBoxPair(
        flow, "signal_spacing",
        {group = "layer", action = "signal_spacing", idx = buildable.idx},
        0, 6, buildable.signal_spacing,
        "signal-spacing")
end

---@param flow LuaGuiElement
---@param buildable Roboport
function lib.setupRoboportGuiFrame(flow, buildable)
    lib.setupBaseBuildableGuiFrame(flow, buildable)

    lib.setupSliderTextBoxPair(
        flow, "spacing",
        {group = "layer", action = "spacing", idx = buildable.idx},
        buildable.size, buildable.logistic_radius, buildable.spacing,
        "spacing")
end

---@param flow LuaGuiElement
---@param buildable Buildable|nil
function lib.setupBuildableGuiFrame(flow, buildable)
    if buildable.type == "nil" then
        ---@diagnostic disable-next-line
        lib.setupBaseBuildableGuiFrame(flow, buildable)
        return
    end
    if buildable.type == "tile" then
        lib.setupTileGuiFrame(flow, buildable)
    elseif buildable.type == "wall" then
        lib.setupWallGuiFrame(flow, buildable)
    elseif buildable.type == "electric-pole" then
        lib.setupElectricPoleGuiFrame(flow, buildable)
    elseif buildable.type == "electric-turret" then
        lib.setupElectricTurretGuiFrame(flow, buildable)
    elseif buildable.type == "straight-rail" then
        lib.setupRailGuiFrame(flow, buildable)
    elseif buildable.type == "roboport" then
        lib.setupRoboportGuiFrame(flow, buildable)
    else
        debug.print("Unknown buildable type: "..buildable.type)
    end
end

--- @param frame LuaGuiElement
function lib.add_layer_controls(frame)
    local player_index = frame.player_index
    local state = storage.controllers[player_index].state

    if frame.layer_flow then
        frame.layer_flow.destroy()
    end

    local flow = frame.add{
        type = "flow",
        name = "layer_flow",
        direction = "vertical"
    }
    flow.add{
        type = "sprite-button",
        name = "add_layer_above",
        tags = {group = "layer", action = "new_layer", direction = 1},
        sprite = "utility/add",
        tooltip = {"button.add-layer"}
    }

    local layers = state.layers
    local num_layers = 0
    for k, _ in pairs(layers) do
        num_layers = num_layers + 1
    end

    if num_layers > 0 then
        local min_layer = 0
        local max_layer = 0
        for k, _ in pairs(layers) do
            if k > max_layer then
                max_layer = k
            end
            if k < min_layer then
                min_layer = k
            end
        end
        local a = 1
        for k = max_layer, min_layer, -1 do
            local layer = layers[k]
            local layer_flow = flow.add{
                type = "flow",
                name = "layer_"..k,
                direction = "horizontal"
            }

            lib.setupBuildableGuiFrame(layer_flow, layer)
        end
    else
        debug.print("No layers to display")
    end

    flow.add{
        type = "sprite-button",
        name = "add_layer_below",
        tags = {group = "layer", action = "new_layer", direction = -1},
        sprite = "utility/add",
        tooltip = {"button.add-layer"}
    }
end

return lib