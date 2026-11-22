--- The view settings pane (group = "view"): how this player's curve, points and
--- preview are drawn. Opened with the colour picker button next to Build.
local palette = require("scripts.palette")
local state = require("scripts.state")
local window = require("scripts.gui.window")

local lib = {}

--- Locale keys use dashes where setting names use underscores.
--- @param name string
local function locale_key(name)
    return (string.gsub(name, "_", "-"))
end

--- @return LocalisedString[]
local function color_items()
    local items = {}
    for i, entry in ipairs(palette.NAMED) do
        items[i] = { "", "[img=bezierio-color-" .. entry.name .. "] ", { "bezierio-color." .. entry.name } }
    end
    return items
end

--- @param pane LuaGuiElement
--- @param view ViewSettings
local function fill(pane, view)
    pane.clear()
    local grid = pane.add { type = "table", name = "view_table", column_count = 2 }
    grid.style.vertical_align = "center"
    local items = color_items()
    for _, name in ipairs(palette.VIEW_COLORS) do
        grid.add { type = "label", caption = { "view-setting." .. locale_key(name) } }
        local dropdown = grid.add {
            type = "drop-down",
            name = "view_" .. name,
            items = items,
            selected_index = palette.named_index(view[name]) or 1,
            tags = { group = "view", action = "set_color", setting = name },
        }
        dropdown.style.width = 150
    end
    for _, number in ipairs(palette.VIEW_NUMBERS) do
        grid.add { type = "label", caption = { "view-setting." .. locale_key(number.name) } }
        local flow = grid.add { type = "flow", direction = "horizontal" }
        flow.style.vertical_align = "center"
        local slider = flow.add {
            type = "slider",
            name = "view_" .. number.name,
            minimum_value = number.min,
            maximum_value = number.max,
            value_step = number.step,
            discrete_values = true,
            value = view[number.name],
            tags = { group = "view", action = "set_number", setting = number.name },
        }
        slider.style.width = 110
        local value = flow.add { type = "label", name = "view_" .. number.name .. "_value", caption = tostring(view[number.name]) }
        value.style.width = 30
    end
    pane.add {
        type = "button",
        name = "view_reset",
        caption = { "button.view-reset" },
        tags = { group = "view", action = "reset" },
    }
end

--- The toggle button (in the control row) and the hidden pane (in `parent`).
--- @param parent LuaGuiElement
--- @param player LuaPlayer
function lib.add(parent, player)
    local pane = parent.add {
        type = "frame",
        name = "view_settings",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding",
        visible = false,
    }
    fill(pane, state.view(player.index))
end

--- @param buttons LuaGuiElement
function lib.add_toggle(buttons)
    buttons.add {
        type = "sprite-button",
        name = "view_settings_button",
        sprite = "utility/color_picker",
        tooltip = { "tooltip.view-settings" },
        tags = { group = "view", action = "toggle" },
        auto_toggle = true,
        style = "tool_button",
    }
end

--- @param e EventData.on_gui_click
lib["toggle"] = function(e)
    local player = game.get_player(e.player_index)
    local pane = player and window.find(player, "view_settings")
    if pane then pane.visible = e.element.toggled end
end

--- @param e EventData.on_gui_selection_state_changed
lib["set_color"] = function(e)
    local setting = e.element.tags.setting --[[@as string]]
    local entry = palette.NAMED[e.element.selected_index]
    local view = state.view(e.player_index)
    if not entry or palette.VIEW_DEFAULTS[setting] == nil then return end
    view[setting] = entry.name
    state.request_redraw(e.player_index)
end

--- @param e EventData.on_gui_value_changed
lib["set_number"] = function(e)
    local setting = e.element.tags.setting --[[@as string]]
    if type(palette.VIEW_DEFAULTS[setting]) ~= "number" then return end
    local value = math.floor(e.element.slider_value + 0.5)
    state.view(e.player_index)[setting] = value
    local player = game.get_player(e.player_index)
    local label = player and window.find(player, "view_" .. setting .. "_value")
    if label then label.caption = tostring(value) end
    state.request_redraw(e.player_index)
end

--- @param e EventData.on_gui_click
lib["reset"] = function(e)
    local controller = state.get(e.player_index)
    controller.view = state.default_view()
    local player = game.get_player(e.player_index)
    local pane = player and window.find(player, "view_settings")
    if pane then fill(pane, controller.view) end
    state.request_redraw(e.player_index)
end

return lib
