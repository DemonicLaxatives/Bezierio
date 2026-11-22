--- The layer list (one compact row per layer) and the detail pane for the selected
--- layer, whose controls come from the layer type (see scripts/layers/).
local registry = require("scripts.layers.registry")
local state = require("scripts.state")
local palette = require("scripts.palette")
local window = require("scripts.gui.window")

local lib = {}

--- Locale keys use dashes where field names use underscores.
--- @param field_name string
local function locale_key(field_name)
    return (string.gsub(field_name, "_", "-"))
end

-- Detail pane -------------------------------------------------------------------

--- A captioned slider with a number box (or a word label) showing its value.
--- Names: <field>_frame, <field>_value (number box / label), <field>_slider.
--- @param flow LuaGuiElement
--- @param layer Layer
--- @param field LayerField
function lib.add_slider_field(flow, layer, field)
    local name = field.name
    local min, max = registry.field_range(layer, name)
    local value = layer[name]
    local tags = { group = "layer", action = "set_value", field = name, idx = layer.idx }
    local key = locale_key(name)

    local frame = flow.add { type = "flow", name = name .. "_frame", direction = "horizontal" }
    frame.style.vertical_align = "center"
    local label = frame.add {
        type = "label",
        caption = { "slider-caption." .. key },
        tooltip = { "tooltip." .. key },
    }
    label.style.width = 110

    local slider = frame.add {
        type = "slider",
        name = name .. "_slider",
        tags = tags,
        minimum_value = min,
        maximum_value = max,
        value = value,
        value_step = 1,
        discrete_values = true,
    }
    slider.style.width = 120

    if field.labels then
        local indicator = frame.add { type = "label", name = name .. "_value", caption = field.labels[value] }
        indicator.style.width = 80
    else
        local indicator = frame.add {
            type = "textfield",
            name = name .. "_value",
            tags = tags,
            text = tostring(value),
            numeric = true,
            allow_decimal = false,
            allow_negative = min < 0,
        }
        indicator.style.width = 40
    end
    return frame
end

--- Push a (validated) value back into a slider and its indicator.
--- @param player LuaPlayer
--- @param layer Layer
--- @param field_name string
function lib.sync_value(player, layer, field_name)
    local value = layer[field_name]
    local slider = window.find(player, field_name .. "_slider")
    if slider then slider.slider_value = value end
    local indicator = window.find(player, field_name .. "_value")
    if not indicator then return end
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
local function add_checkbox_field(flow, layer, field)
    flow.add {
        type = "checkbox",
        name = field.name,
        caption = { "checkbox." .. locale_key(field.name) },
        tooltip = { "tooltip." .. locale_key(field.name) },
        state = layer[field.name] == true,
        tags = { group = "layer", action = "set_flag", field = field.name, idx = layer.idx },
    }
end

--- @param detail LuaGuiElement
--- @param layer Layer
local function fill_detail(detail, layer)
    detail.clear()
    local header = detail.add { type = "flow", name = "layer_detail_header", direction = "horizontal" }
    header.style.vertical_align = "center"
    local title = header.add { type = "label", caption = { "label.layer-detail", tostring(layer.idx) }, style = "caption_label" }
    title.style.font_color = palette.layer_color(layer.idx)

    local picker = header.add {
        type = "choose-elem-button",
        name = "layer_type",
        tags = { group = "layer", action = "type", idx = layer.idx },
        elem_type = "item-with-quality",
        elem_filters = state.item_filter(),
        tooltip = { "tooltip.layer-type" },
    }
    if layer.placed_by then
        picker.elem_value = { name = layer.placed_by, quality = layer.quality or "normal" }
    else
        header.add { type = "label", caption = { "label.no-layer-item" } }
    end

    if layer.idx ~= 0 then
        lib.add_slider_field(detail, layer, registry.offset_field)
    end
    for _, field in ipairs(registry.type_of(layer).fields) do
        if field.widget == "slider" then
            lib.add_slider_field(detail, layer, field)
        elseif field.widget == "checkbox" then
            add_checkbox_field(detail, layer, field)
        end
    end
end

-- Layer list --------------------------------------------------------------------

--- Height of the layer list before it scrolls (about eight rows).
lib.LIST_HEIGHT = 340

--- @param list LuaGuiElement
--- @param layer Layer
--- @param selected boolean
local function add_row(list, layer, selected)
    local k = layer.idx
    local row = list.add { type = "flow", name = "layer_row_" .. k, direction = "horizontal" }
    row.style.vertical_align = "center"

    row.add {
        type = "sprite-button",
        name = "layer_select_" .. k,
        sprite = layer.placed_by and ("item/" .. layer.placed_by) or nil,
        tags = { group = "layer", action = "select", idx = k },
        tooltip = { "tooltip.layer-select" },
        toggled = selected,
        style = "slot_button",
    }
    local label = row.add {
        type = "label",
        name = "layer_label_" .. k,
        caption = registry.is_underlay(layer)
            and { "label.layer-row-under", tostring(k), tostring(registry.thickness(layer)) }
            or { "label.layer-row", tostring(k), tostring(registry.thickness(layer)) },
    }
    label.style.font_color = palette.layer_color(k)
    label.style.width = 90

    local buttons = {
        { name = "layer_move_up_" .. k, sprite = "utility/hint_arrow_up", tooltip = "move-layer-up", action = "move", direction = 1 },
        { name = "layer_move_down_" .. k, sprite = "utility/hint_arrow_down", tooltip = "move-layer-down", action = "move", direction = -1 },
        { name = "layer_delete_" .. k, sprite = "utility/trash", tooltip = "delete-layer", action = "delete" },
    }
    for _, b in ipairs(buttons) do
        local fixed = b.action == "delete" and k == 0
        local button = row.add {
            type = "sprite-button",
            name = b.name,
            sprite = b.sprite,
            tooltip = { "tooltip." .. (fixed and "delete-layer-0" or b.tooltip) },
            tags = { group = "layer", action = b.action, direction = b.direction, idx = k },
            style = "tool_button",
            enabled = not fixed,
        }
        button.style.size = 24
    end
end

--- (Re)build the layer column: list, highest layer on top, then the detail pane.
--- @param column LuaGuiElement
--- @param player_index integer
function lib.fill(column, player_index)
    column.clear()
    local layers = state.layers(player_index)
    local ui = state.ui(player_index)
    if not layers[ui.selected_layer] then ui.selected_layer = 0 end

    local list = column.add { type = "frame", name = "layer_flow", direction = "vertical", style = "inside_shallow_frame_with_padding" }
    list.add {
        type = "sprite-button",
        name = "add_layer_above",
        tags = { group = "layer", action = "new_layer", direction = 1 },
        sprite = "utility/add",
        tooltip = { "tooltip.add-layer" },
        style = "tool_button",
    }
    local rows = list.add {
        type = "scroll-pane",
        name = "layer_rows",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy = "auto",
    }
    rows.style.maximal_height = lib.LIST_HEIGHT
    local min_layer, max_layer = 0, 0
    for k in pairs(layers) do
        max_layer = math.max(max_layer, k)
        min_layer = math.min(min_layer, k)
    end
    for k = max_layer, min_layer, -1 do
        if layers[k] then add_row(rows, layers[k], k == ui.selected_layer) end
    end
    list.add {
        type = "sprite-button",
        name = "add_layer_below",
        tags = { group = "layer", action = "new_layer", direction = -1 },
        sprite = "utility/add",
        tooltip = { "tooltip.add-layer" },
        style = "tool_button",
    }

    local detail = column.add { type = "frame", name = "layer_detail", direction = "vertical", style = "inside_shallow_frame_with_padding" }
    fill_detail(detail, layers[ui.selected_layer])
    local selected_row = rows["layer_row_" .. ui.selected_layer]
    if selected_row then rows.scroll_to_element(selected_row) end
end

--- @param parent LuaGuiElement
--- @param player_index integer
function lib.add(parent, player_index)
    local column = parent.add { type = "flow", name = "layers_column", direction = "vertical" }
    lib.fill(column, player_index)
end

--- @param player LuaPlayer
function lib.refresh(player)
    local column = window.find(player, "layers_column")
    if column then lib.fill(column, player.index) end
end

return lib
