--- Builds the layer list of the main window: one row per layer, with the controls
--- its layer type declares (see scripts/layers/).
local registry = require("scripts.layers.registry")
local state = require("scripts.state")

local lib = {}

--- Locale keys use dashes where field names use underscores.
--- @param field_name string
local function locale_key(field_name)
    return (string.gsub(field_name, "_", "-"))
end

--- A captioned slider with a number box (or a word label) showing its value.
--- Element layout: <field>_frame > { <field>_labels > {label, slider_indicator},
---                                   <field>_slider_flow > {min, <field>, max} }
--- @param flow LuaGuiElement
--- @param layer Layer
--- @param field LayerField
function lib.add_slider_field(flow, layer, field)
    local name = field.name
    local min, max = registry.field_range(layer, name)
    local value = layer[name]
    local tags = { group = "layer", action = "set_value", field = name, idx = layer.idx }
    local key = locale_key(name)

    local frame = flow.add { type = "frame", name = name .. "_frame", direction = "vertical" }
    local labels = frame.add { type = "flow", name = name .. "_labels", direction = "horizontal" }
    labels.add {
        type = "label",
        name = "label",
        caption = { "slider-caption." .. key },
        tooltip = { "tooltip." .. key },
    }

    if field.labels then
        local indicator = labels.add { type = "label", name = "slider_indicator", caption = field.labels[value] }
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

    local slider_flow = frame.add { type = "flow", name = name .. "_slider_flow", direction = "horizontal" }
    slider_flow.add { type = "label", name = "min", caption = tostring(min) }
    local slider = slider_flow.add {
        type = "slider",
        name = name,
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

--- Push a (validated) value back into a slider and its indicator.
--- @param element LuaGuiElement  # the slider or its number box
--- @param layer Layer
--- @param field_name string
function lib.sync_value(element, layer, field_name)
    local frame = element.parent and element.parent.parent
    if not frame then return end
    local value = layer[field_name]
    frame[field_name .. "_slider_flow"][field_name].slider_value = value
    local indicator = frame[field_name .. "_labels"].slider_indicator
    local field = registry.field(layer, field_name)
    if field and field.labels then
        indicator.caption = field.labels[value]
    else
        indicator.text = tostring(value)
    end
end

--- @param flow LuaGuiElement
--- @param layer Layer
--- @param field LayerField
function lib.add_checkbox_field(flow, layer, field)
    flow.add {
        type = "checkbox",
        name = field.name,
        caption = { "checkbox." .. locale_key(field.name) },
        state = layer[field.name],
        tags = { group = "layer", action = "set_flag", field = field.name, idx = layer.idx },
    }
end

--- One layer's row: index, move/delete buttons, item picker, offset, type fields.
--- @param flow LuaGuiElement
--- @param layer Layer
function lib.fill_row(flow, layer)
    flow.clear()

    flow.add { type = "label", caption = { "label.layer", tostring(layer.idx) } }

    local up = flow.add {
        type = "sprite-button",
        name = "layer_move_up",
        tags = { group = "layer", action = "move", direction = 1, idx = layer.idx },
        sprite = "utility/hint_arrow_up",
        tooltip = { "tooltip.move-layer-up" },
    }
    up.style.width = 30

    local down = flow.add {
        type = "sprite-button",
        name = "layer_move_down",
        tags = { group = "layer", action = "move", direction = -1, idx = layer.idx },
        sprite = "utility/hint_arrow_down",
        tooltip = { "tooltip.move-layer-down" },
    }
    down.style.width = 30

    flow.add {
        type = "sprite-button",
        name = "layer_delete",
        tags = { group = "layer", action = "delete", idx = layer.idx },
        sprite = "utility/trash",
        tooltip = { "tooltip.delete-layer" },
        enabled = layer.idx ~= 0,
    }

    local picker = flow.add {
        type = "choose-elem-button",
        name = "layer_type",
        tags = { group = "layer", action = "type", idx = layer.idx },
        elem_type = "item-with-quality",
        elem_filters = state.item_filter(),
    }
    if layer.placed_by then
        picker.elem_value = { name = layer.placed_by, quality = layer.quality or "normal" }
    end

    if layer.idx ~= 0 then
        lib.add_slider_field(flow, layer, registry.offset_field)
    end
    for _, field in ipairs(registry.type_of(layer).fields) do
        if field.widget == "slider" then
            lib.add_slider_field(flow, layer, field)
        elseif field.widget == "checkbox" then
            lib.add_checkbox_field(flow, layer, field)
        end
    end
end

--- (Re)build the whole layer list, highest layer on top.
--- @param frame LuaGuiElement
function lib.add_layer_rows(frame)
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
        tooltip = { "tooltip.add-layer" },
    }

    local min_layer, max_layer = 0, 0
    for k in pairs(layers) do
        max_layer = math.max(max_layer, k)
        min_layer = math.min(min_layer, k)
    end
    for k = max_layer, min_layer, -1 do
        local layer = layers[k]
        if layer then
            local row = flow.add { type = "flow", name = "layer_" .. k, direction = "horizontal" }
            lib.fill_row(row, layer)
        end
    end

    flow.add {
        type = "sprite-button",
        name = "add_layer_below",
        tags = { group = "layer", action = "new_layer", direction = -1 },
        sprite = "utility/add",
        tooltip = { "tooltip.add-layer" },
    }
end

return lib
