--- The layer list (one compact row per layer) and the layer settings window,
--- whose controls come from the layer type (see scripts/layers/).
---
--- The settings window opens from a layer's item or its settings button, and for a
--- new layer. While it is open the main window is locked; edits apply as they are
--- made (the preview follows), OK keeps them, Cancel (or Esc) puts the layer back
--- as it was (a new layer goes away).
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
    local disabled = field.disabled_by ~= nil and layer[field.disabled_by] == true
    if disabled then
        slider.enabled = false
        label.tooltip = { "tooltip.disabled-by-" .. locale_key(field.disabled_by) }
    end

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
            enabled = not disabled,
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

--- A captioned drop-down. Name: <field> (the drop-down).
--- @param flow LuaGuiElement
--- @param layer Layer
--- @param field LayerField
local function add_choice_field(flow, layer, field)
    local key = locale_key(field.name)
    local frame = flow.add { type = "flow", name = field.name .. "_frame", direction = "horizontal" }
    frame.style.vertical_align = "center"
    local label = frame.add { type = "label", caption = { "slider-caption." .. key }, tooltip = { "tooltip." .. key } }
    label.style.width = 110
    local items, selected = {}, 1
    for i, option in ipairs(field.options) do
        items[i] = { field.label_prefix .. "." .. option }
        if option == layer[field.name] then selected = i end
    end
    frame.add {
        type = "drop-down",
        name = field.name,
        items = items,
        selected_index = selected,
        tags = { group = "layer", action = "set_choice", field = field.name, idx = layer.idx },
    }
end

--- A captioned item picker (e.g. ammo). Name: <field> (the picker).
--- @param flow LuaGuiElement
--- @param layer Layer
--- @param field LayerField
local function add_item_field(flow, layer, field)
    local key = locale_key(field.name)
    local frame = flow.add { type = "flow", name = field.name .. "_frame", direction = "horizontal" }
    frame.style.vertical_align = "center"
    local label = frame.add { type = "label", caption = { "slider-caption." .. key }, tooltip = { "tooltip." .. key } }
    label.style.width = 110
    local picker = frame.add {
        type = "choose-elem-button",
        name = field.name,
        elem_type = "item",
        elem_filters = field.item_filters,
        tags = { group = "layer", action = "set_item", field = field.name, idx = layer.idx },
    }
    picker.elem_value = layer[field.name]
end

--- @param detail LuaGuiElement
--- @param layer Layer
local function fill_detail(detail, layer)
    detail.clear()
    local header = detail.add { type = "flow", name = "layer_detail_header", direction = "horizontal" }
    header.style.vertical_align = "center"
    -- (the window's title says which layer)
    local label = header.add { type = "label", caption = { "slider-caption.layer-item" }, tooltip = { "tooltip.layer-type" } }
    label.style.width = 110

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
        if field.visible_if and not field.visible_if(layer) then
            -- not relevant for this entity (e.g. facing for turrets that turn all the way)
        elseif field.widget == "slider" then
            lib.add_slider_field(detail, layer, field)
        elseif field.widget == "checkbox" then
            add_checkbox_field(detail, layer, field)
        elseif field.widget == "choice" then
            add_choice_field(detail, layer, field)
        elseif field.widget == "item" then
            add_item_field(detail, layer, field)
        end
    end
end

-- Layer list --------------------------------------------------------------------

--- Height of the layer list before it scrolls (about eight rows).
lib.LIST_HEIGHT = 340

--- One layer: a row of cells in the layer table. Narrow: just the preview
--- checkbox, the item and the layer number.
--- @param list LuaGuiElement  # the table
--- @param layer Layer
--- @param selected boolean
--- @param narrow boolean
local function add_row(list, layer, selected, narrow)
    local k = layer.idx
    list.add {
        type = "checkbox",
        name = "layer_preview_" .. k,
        state = layer.preview ~= false,
        tooltip = { "tooltip.layer-preview" },
        tags = { group = "layer", action = "toggle_preview", idx = k },
    }
    local select = list.add {
        type = "sprite-button",
        name = "layer_select_" .. k,
        sprite = layer.placed_by and ("item/" .. layer.placed_by) or nil,
        tags = { group = "layer", action = "select", idx = k },
        tooltip = { "tooltip.layer-settings" },
        toggled = selected,
        style = "slot_button",
    }
    if layer.placed_by and layer.quality and layer.quality ~= "normal" then select.quality = layer.quality end
    local label = list.add {
        type = "label",
        name = "layer_label_" .. k,
        caption = narrow and ("L" .. k)
            or registry.is_underlay(layer) and { "label.layer-row-under", tostring(k), tostring(registry.thickness(layer)) }
            or { "label.layer-row", tostring(k), tostring(registry.thickness(layer)) },
    }
    label.style.font_color = palette.layer_color(k)
    label.style.horizontally_stretchable = true
    local settings = list.add {
        type = "sprite-button",
        name = "layer_settings_" .. k,
        sprite = "utility/list_view",
        tooltip = { "tooltip.layer-settings" },
        tags = { group = "layer", action = "select", idx = k },
        style = "tool_button",
    }
    settings.style.size = 24
    if narrow then return end

    local buttons = {
        { name = "layer_move_up_" .. k, sprite = "utility/hint_arrow_up", tooltip = "move-layer-up", action = "move", direction = 1 },
        { name = "layer_move_down_" .. k, sprite = "utility/hint_arrow_down", tooltip = "move-layer-down", action = "move", direction = -1 },
        { name = "layer_delete_" .. k, sprite = "utility/trash", tooltip = "delete-layer", action = "delete" },
    }
    for _, b in ipairs(buttons) do
        local fixed = b.action == "delete" and k == 0
        local button = list.add {
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

--- @param parent LuaGuiElement
--- @param direction integer  # 1: above the outermost + layer, -1: below the outermost - layer
local function add_bar(parent, direction)
    local bar = parent.add {
        type = "button",
        name = direction == 1 and "add_layer_above" or "add_layer_below",
        tags = { group = "layer", action = "new_layer", direction = direction },
        caption = "+",
        tooltip = { "tooltip.add-layer" },
        style = "bezierio_add_bar",
    }
    -- (apart from the preset bar's buttons above)
    if direction == 1 then bar.style.top_margin = 8 end
end

--- (Re)build the layer list, highest layer on top, then the detail pane (wide
--- window only).
--- @param column LuaGuiElement
--- @param player_index integer
function lib.fill(column, player_index)
    column.clear()
    local layers = state.layers(player_index)
    local ui = state.ui(player_index)
    local narrow = ui.narrow == true
    if not layers[ui.selected_layer] then ui.selected_layer = 0 end

    add_bar(column, 1)
    -- The list in its own sunken pane.
    local sunken = column.add { type = "frame", name = "layer_list_frame", direction = "vertical", style = "inside_deep_frame" }
    sunken.style.horizontally_stretchable = true
    local rows = sunken.add {
        type = "scroll-pane",
        name = "layer_rows",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy = "auto",
    }
    rows.style.maximal_height = lib.LIST_HEIGHT
    rows.style.horizontally_stretchable = true
    local list = rows.add {
        type = "table",
        name = "layer_table",
        column_count = narrow and 4 or 7,
        style = "bezierio_striped_table",
    }
    list.style.vertical_align = "center"
    list.style.horizontally_stretchable = true
    local min_layer, max_layer = 0, 0
    for k in pairs(layers) do
        max_layer = math.max(max_layer, k)
        min_layer = math.min(min_layer, k)
    end
    for k = max_layer, min_layer, -1 do
        if layers[k] then add_row(list, layers[k], k == ui.selected_layer, narrow) end
    end
    add_bar(column, -1)
    local selected = list["layer_select_" .. ui.selected_layer]
    if selected then rows.scroll_to_element(selected) end
end

--- @param parent LuaGuiElement
--- @param player_index integer
function lib.add(parent, player_index)
    local column = parent.add { type = "flow", name = "layers_column", direction = "vertical" }
    column.style.vertical_spacing = 4
    lib.fill(column, player_index)
end

--- The layer list and, if open, the settings window (the layer may have become
--- another type).
--- @param player LuaPlayer
function lib.refresh(player)
    local column = window.find(player, "layers_column")
    if column then lib.fill(column, player.index) end
    local editing = state.ui(player.index).editing
    local detail = window.find(player, "layer_detail")
    local layer = editing and state.layers(player.index)[editing.idx]
    if detail and layer then fill_detail(detail, layer) end
end

-- Layer settings window -----------------------------------------------------------

lib.WINDOW = "bezierio_layer_window"

--- @param value any
--- @return any
local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deep_copy(v) end
    return out
end

--- Lock or unlock the main window (it can't be used while a layer is edited).
--- @param player LuaPlayer
--- @param locked boolean
local function lock_main(player, locked)
    local main = window.get(player)
    if main then main.ignored_by_interaction = locked end
end

--- Close the settings window, keeping the edits.
--- @param player LuaPlayer
function lib.accept(player)
    local ui = state.ui(player.index)
    if not ui.editing then return end
    ui.editing = nil
    local frame = player.gui.screen[lib.WINDOW]
    if frame then frame.destroy() end
    lock_main(player, false)
    local main = window.get(player)
    if main and not ui.pinned then player.opened = main end
end

--- Close the settings window, putting the layer back as it was.
--- @param player LuaPlayer
function lib.cancel(player)
    local ui = state.ui(player.index)
    local editing = ui.editing
    if not editing then return end
    local layers = state.layers(player.index)
    if editing.new then
        layers[editing.idx] = nil
        if ui.selected_layer == editing.idx then ui.selected_layer = 0 end
    elseif editing.backup then
        layers[editing.idx] = editing.backup
    end
    lib.accept(player)
    state.changed(player.index)
    lib.refresh(player)
end

--- Open the settings window for a layer (another one open is accepted first).
--- @param player LuaPlayer
--- @param idx integer
--- @param new boolean|nil  # the layer was just added (Cancel removes it)
function lib.open_settings(player, idx, new)
    local ui = state.ui(player.index)
    local layer = state.layers(player.index)[idx]
    if not layer then return end
    if ui.editing then lib.accept(player) end
    ui.selected_layer = idx
    ui.editing = { idx = idx, backup = (not new) and deep_copy(layer) or nil, new = new or nil }

    local frame = player.gui.screen.add { type = "frame", name = lib.WINDOW, direction = "vertical" }
    local title_bar = frame.add { type = "flow", direction = "horizontal" }
    title_bar.style.horizontal_spacing = 6
    local title = title_bar.add { type = "label", style = "frame_title", caption = { "titles.layer-settings", tostring(idx) }, ignored_by_interaction = true }
    title.style.font_color = palette.layer_color(idx)
    local dragger = title_bar.add { type = "empty-widget", style = "draggable_space_header" }
    dragger.style.horizontally_stretchable = true
    dragger.style.height = 24
    dragger.style.minimal_width = 16
    dragger.drag_target = frame

    local detail = frame.add { type = "frame", name = "layer_detail", direction = "vertical", style = "inside_shallow_frame_with_padding" }
    detail.style.minimal_width = 360
    fill_detail(detail, layer)

    local buttons = frame.add { type = "flow", name = "layer_dialog_buttons", direction = "horizontal", style = "dialog_buttons_horizontal_flow" }
    buttons.add {
        type = "button",
        name = "layer_cancel",
        caption = { "button.layer-cancel" },
        tooltip = { "tooltip.layer-cancel" },
        style = "back_button",
        tags = { group = "layer", action = "cancel" },
    }
    local filler = buttons.add { type = "empty-widget", style = "draggable_space" }
    filler.style.horizontally_stretchable = true
    filler.style.height = 32
    filler.drag_target = frame
    buttons.add {
        type = "button",
        name = "layer_ok",
        caption = { "button.layer-ok" },
        tooltip = { "tooltip.layer-ok" },
        style = "confirm_button",
        tags = { group = "layer", action = "ok" },
    }
    frame.force_auto_center()
    lock_main(player, true)
    player.opened = frame
    lib.refresh(player)
end

return lib
