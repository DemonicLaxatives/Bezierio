--- Builds the per-layer rows of the main window.
local buildable_types = require("scripts.build.buildable_types")
local state = require("scripts.state")

local lib = {}

--- Fields whose values are shown as words instead of numbers.
local VALUE_LABELS = {
    direction_of_travel = {
        [-1] = { "label.direction-backwards" },
        [0] = { "label.direction-neither" },
        [1] = { "label.direction-forwards" },
    },
}

--- @param field string
local function locale_key(field)
    return (string.gsub(field, "_", "-"))
end

--- A captioned slider with a number box (or a word label) showing its value.
--- Element layout: <field>_frame > { <field>_labels > {label, slider_indicator},
---                                   <field>_slider_flow > {min, <field>, max} }
--- @param flow LuaGuiElement
--- @param buildable Buildable
--- @param field string
function lib.setupSliderTextBoxPair(flow, buildable, field)
    local min, max = buildable_types.fieldRange(buildable, field)
    local value = buildable[field]
    local tags = { group = "layer", action = "set_value", field = field, idx = buildable.idx }
    local key = locale_key(field)

    local frame = flow.add { type = "frame", name = field .. "_frame", direction = "vertical" }
    local labels = frame.add { type = "flow", name = field .. "_labels", direction = "horizontal" }
    labels.add {
        type = "label",
        name = "label",
        caption = { "slider-caption." .. key },
        tooltip = { "tooltip." .. key },
    }

    if VALUE_LABELS[field] then
        local indicator = labels.add { type = "label", name = "slider_indicator", caption = VALUE_LABELS[field][value] }
        indicator.style.width = 80
    else
        local indicator = labels.add {
            type = "textfield",
            name = "slider_indicator",
            tags = tags,
            text = tostring(value),
            numeric = true,
            allow_decimal = false,
            allow_negative = min < 0,
        }
        indicator.style.width = 40
    end

    local slider_flow = frame.add { type = "flow", name = field .. "_slider_flow", direction = "horizontal" }
    slider_flow.add { type = "label", name = "min", caption = tostring(min) }
    local slider = slider_flow.add {
        type = "slider",
        name = field,
        tags = tags,
        minimum_value = min,
        maximum_value = max,
        value = value,
        value_step = 1,
        discrete_values = true,
    }
    slider.style.width = 100
    slider_flow.add { type = "label", name = "max", caption = tostring(max) }
    return frame
end

--- Push a (validated) value back into a slider/indicator pair.
--- @param element LuaGuiElement  # the slider or its number box
--- @param field string
--- @param value integer
function lib.syncValue(element, field, value)
    local frame = element.parent and element.parent.parent
    if not frame then return end
    local slider = frame[field .. "_slider_flow"][field]
    slider.slider_value = value
    local indicator = frame[field .. "_labels"].slider_indicator
    if VALUE_LABELS[field] then
        indicator.caption = VALUE_LABELS[field][value]
    else
        indicator.text = tostring(value)
    end
end

--- @param flow LuaGuiElement
--- @param buildable Buildable
--- @param field string
local function add_checkbox(flow, buildable, field)
    flow.add {
        type = "checkbox",
        name = field,
        caption = { "checkbox." .. locale_key(field) },
        state = buildable[field],
        tags = { group = "layer", action = "set_flag", field = field, idx = buildable.idx },
    }
end

---@param flow LuaGuiElement
---@param buildable Buildable
function lib.setupBaseBuildableGuiFrame(flow, buildable)
    flow.clear()

    flow.add { type = "label", caption = { "label.layer", tostring(buildable.idx) } }

    local up = flow.add {
        type = "sprite-button",
        name = "layer_move_up",
        tags = { group = "layer", action = "move", direction = 1, idx = buildable.idx },
        sprite = "utility/hint_arrow_up",
        tooltip = { "tooltip.move-layer-up" }
    }
    up.style.width = 30

    local down = flow.add {
        type = "sprite-button",
        name = "layer_move_down",
        tags = { group = "layer", action = "move", direction = -1, idx = buildable.idx },
        sprite = "utility/hint_arrow_down",
        tooltip = { "tooltip.move-layer-down" }
    }
    down.style.width = 30

    flow.add {
        type = "sprite-button",
        name = "layer_delete",
        tags = { group = "layer", action = "delete", idx = buildable.idx },
        sprite = "utility/trash",
        tooltip = { "tooltip.delete-layer" },
        enabled = buildable.idx ~= 0,
    }

    local picker = flow.add {
        type = "choose-elem-button",
        name = "layer_type",
        tags = { group = "layer", action = "type", idx = buildable.idx },
        elem_type = "item-with-quality",
        elem_filters = state.item_filter(),
    }
    if buildable.placed_by then
        picker.elem_value = { name = buildable.placed_by, quality = buildable.quality or "normal" }
    end

    if buildable.idx ~= 0 then
        lib.setupSliderTextBoxPair(flow, buildable, "offset")
    end
end

--- Extra controls per buildable type.
local TYPE_FIELDS = {
    ["wall"] = { sliders = { "checkerboard", "radius" } },
    ["tile"] = { sliders = { "checkerboard", "radius" } },
    ["electric-pole"] = { sliders = { "spacing" }, checkboxes = { "smart_placement", "connect_with_circuit_wires" } },
    ["electric-turret"] = { sliders = { "spacing" } },
    ["straight-rail"] = { sliders = { "direction_of_travel", "signal_spacing" } },
    ["roboport"] = { sliders = { "spacing" } },
}

---@param flow LuaGuiElement
---@param buildable Buildable
function lib.setupBuildableGuiFrame(flow, buildable)
    lib.setupBaseBuildableGuiFrame(flow, buildable)
    local fields = TYPE_FIELDS[buildable.type]
    if not fields then return end
    for _, field in ipairs(fields.sliders or {}) do
        lib.setupSliderTextBoxPair(flow, buildable, field)
    end
    for _, field in ipairs(fields.checkboxes or {}) do
        add_checkbox(flow, buildable, field)
    end
end

--- (Re)build the whole layer list, highest layer on top.
--- @param frame LuaGuiElement
function lib.add_layer_controls(frame)
    local layers = state.layers(frame.player_index)

    if frame.layer_flow then
        frame.layer_flow.destroy()
    end

    local flow = frame.add { type = "flow", name = "layer_flow", direction = "vertical" }
    flow.add {
        type = "sprite-button",
        name = "add_layer_above",
        tags = { group = "layer", action = "new_layer", direction = 1 },
        sprite = "utility/add",
        tooltip = { "tooltip.add-layer" }
    }

    local min_layer, max_layer = 0, 0
    for k, _ in pairs(layers) do
        max_layer = math.max(max_layer, k)
        min_layer = math.min(min_layer, k)
    end
    for k = max_layer, min_layer, -1 do
        local layer = layers[k]
        if layer then
            local layer_flow = flow.add { type = "flow", name = "layer_" .. k, direction = "horizontal" }
            lib.setupBuildableGuiFrame(layer_flow, layer)
        end
    end

    flow.add {
        type = "sprite-button",
        name = "add_layer_below",
        tags = { group = "layer", action = "new_layer", direction = -1 },
        sprite = "utility/add",
        tooltip = { "tooltip.add-layer" }
    }
end

return lib
