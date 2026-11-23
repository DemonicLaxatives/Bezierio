--- The settings window (group = "view"), opened with the gear in the main window's
--- title bar: how this player's curve, points and preview are drawn, and the
--- player's other settings (how long unpowered / unfed marks stay, whether
--- blueprints carry their curve and preset).
local palette = require("scripts.palette")
local state = require("scripts.state")
local window = require("scripts.gui.window")

local lib = {}

lib.NAME = "bezierio_settings_window"

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
--- @param player_index integer
local function fill(pane, player_index)
    pane.clear()
    local view = state.view(player_index)
    pane.add { type = "label", caption = { "label.settings-view" }, style = "caption_label" }
    local grid = pane.add { type = "table", name = "view_table", column_count = 2, style = "bezierio_striped_table" }
    grid.style.vertical_align = "center"
    grid.style.horizontally_stretchable = true
    local items = color_items()
    for _, name in ipairs(palette.VIEW_COLORS) do
        local label = grid.add { type = "label", caption = { "view-setting." .. locale_key(name) } }
        label.style.horizontally_stretchable = true
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

    pane.add { type = "line" }
    pane.add { type = "label", caption = { "label.settings-builds" }, style = "caption_label" }
    local builds = pane.add { type = "table", name = "settings_table", column_count = 2, style = "bezierio_striped_table" }
    builds.style.vertical_align = "center"
    builds.style.horizontally_stretchable = true
    local seconds_label = builds.add { type = "label", caption = { "label.setting-highlight-seconds" }, tooltip = { "tooltip.setting-highlight-seconds" } }
    seconds_label.style.horizontally_stretchable = true
    local seconds = builds.add {
        type = "textfield",
        name = "setting_highlight_seconds",
        text = tostring(state.setting(player_index, "highlight_seconds")),
        numeric = true,
        allow_decimal = false,
        allow_negative = false,
        tooltip = { "tooltip.setting-highlight-seconds" },
        tags = { group = "view", action = "set_seconds" },
    }
    seconds.style.width = 60
    builds.add { type = "label", caption = { "label.setting-blueprint-source" }, tooltip = { "tooltip.setting-blueprint-source" } }
    builds.add {
        type = "checkbox",
        name = "setting_blueprint_source",
        state = state.setting(player_index, "blueprint_source") == true,
        tooltip = { "tooltip.setting-blueprint-source" },
        tags = { group = "view", action = "set_blueprint_source" },
    }

    pane.add { type = "line" }
    pane.add {
        type = "button",
        name = "view_reset",
        caption = { "button.view-reset" },
        tooltip = { "tooltip.settings-reset" },
        tags = { group = "view", action = "reset" },
    }
end

--- @param player LuaPlayer
--- @return LuaGuiElement|nil
function lib.get(player)
    return player.gui.screen[lib.NAME]
end

--- Open the window beside the main one.
--- @param player LuaPlayer
function lib.open(player)
    if lib.get(player) then return end
    local frame = player.gui.screen.add { type = "frame", name = lib.NAME, direction = "vertical" }
    local title_bar = frame.add { type = "flow", direction = "horizontal" }
    title_bar.style.horizontal_spacing = 6
    title_bar.add { type = "label", style = "frame_title", caption = { "titles.settings" }, ignored_by_interaction = true }
    local dragger = title_bar.add { type = "empty-widget", style = "draggable_space_header" }
    dragger.style.horizontally_stretchable = true
    dragger.style.height = 24
    dragger.style.minimal_width = 16
    dragger.drag_target = frame
    title_bar.add {
        type = "sprite-button",
        name = "settings_close_button",
        style = "frame_action_button",
        sprite = "utility/close",
        tooltip = { "tooltip.close-window" },
        tags = { group = "view", action = "close" },
        mouse_button_filter = { "left" },
    }
    local pane = frame.add { type = "frame", name = "view_settings", direction = "vertical", style = "inside_shallow_frame_with_padding" }
    pane.style.width = 320
    fill(pane, player.index)

    local main = window.get(player)
    if main then
        local width = (state.ui(player.index).narrow and 230 or 456) * player.display_scale
        frame.location = { x = main.location.x + width, y = main.location.y }
    else
        frame.force_auto_center()
    end
    local button = window.find(player, "settings_button")
    if button then button.toggled = true end
end

--- @param player LuaPlayer
function lib.close_window(player)
    local frame = lib.get(player)
    if frame then frame.destroy() end
    local button = window.find(player, "settings_button")
    if button then button.toggled = false end
end

--- The gear in the main window's title bar.
--- @param e EventData.on_gui_click
lib["toggle"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    if lib.get(player) then lib.close_window(player) else lib.open(player) end
end

--- @param e EventData.on_gui_click
lib["close"] = function(e)
    local player = game.get_player(e.player_index)
    if player then lib.close_window(player) end
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

--- Marks after a build stay this many seconds (0: until hidden), at most an hour.
--- @param e EventData.on_gui_confirmed
lib["set_seconds"] = function(e)
    local value = math.floor(tonumber(e.element.text) or 0)
    value = math.max(0, math.min(3600, value))
    state.set_setting(e.player_index, "highlight_seconds", value)
    e.element.text = tostring(value)
end

--- @param e EventData.on_gui_checked_state_changed
lib["set_blueprint_source"] = function(e)
    state.set_setting(e.player_index, "blueprint_source", e.element.state)
end

--- Everything back to its default.
--- @param e EventData.on_gui_click
lib["reset"] = function(e)
    local controller = state.get(e.player_index)
    controller.view = state.default_view()
    controller.settings = nil
    local player = game.get_player(e.player_index)
    local pane = player and window.find(player, "view_settings")
    if pane then fill(pane, e.player_index) end
    state.request_redraw(e.player_index)
end

return lib
