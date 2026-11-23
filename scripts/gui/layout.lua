--- The main window (group = "main"): one column of sections, Curve, Layers and Build.
---
--- The title bar has a pin (a pinned window isn't the player's opened GUI, so
--- other GUIs and Esc don't close it) and a narrow toggle: the whole window
--- narrows at once, each section showing only its everyday controls (the points
--- as chips, layers without their move / delete buttons, tools in rows).
local control = require("scripts.gui.control")
local curve_control = require("scripts.gui.curve_control")
local layer_view = require("scripts.gui.layer_view")
local view_settings = require("scripts.gui.view_settings")
local preset_control = require("scripts.gui.preset_control")
local state = require("scripts.state")

local lib = {}

--- Width of every section in the narrow and the wide window.
lib.NARROW_WIDTH = 212
lib.WIDE_WIDTH = 420

--- A frame action button (white icon, black when hovered or pressed).
--- @param parent LuaGuiElement
--- @param params table
local function action_button(parent, params)
    params.type = "sprite-button"
    params.style = "frame_action_button"
    params.mouse_button_filter = { "left" }
    return parent.add(params)
end

--- @param frame LuaGuiElement
--- @param ui InterfaceState
local function add_title_bar(frame, ui)
    local title_bar = frame.add { type = "flow", name = "title_bar", direction = "horizontal" }
    title_bar.style.horizontal_spacing = 6
    title_bar.add {
        type = "label",
        style = "frame_title",
        caption = { "titles.gui-title" },
        ignored_by_interaction = true,
    }
    local dragger = title_bar.add { type = "empty-widget", style = "draggable_space_header" }
    dragger.style.horizontally_stretchable = true
    dragger.style.height = 24
    dragger.style.minimal_width = 16
    dragger.drag_target = frame
    action_button(title_bar, {
        name = "main_pin_button",
        tags = { group = "main", action = "pin" },
        sprite = ui.pinned and "utility/track_button" or "utility/track_button_white",
        hovered_sprite = "utility/track_button",
        clicked_sprite = "utility/track_button",
        tooltip = { "tooltip.pin-window" },
        auto_toggle = true,
        toggled = ui.pinned == true,
    })
    local narrow = ui.narrow == true
    action_button(title_bar, {
        name = "settings_button",
        tags = { group = "view", action = "toggle" },
        sprite = "bezierio-settings-white",
        hovered_sprite = "bezierio-settings-black",
        clicked_sprite = "bezierio-settings-black",
        tooltip = { "tooltip.view-settings" },
        auto_toggle = true,
        toggled = false,
    })
    action_button(title_bar, {
        name = "main_narrow_button",
        tags = { group = "main", action = "narrow" },
        sprite = narrow and "bezierio-widen-white" or "bezierio-narrow-white",
        hovered_sprite = narrow and "bezierio-widen-black" or "bezierio-narrow-black",
        clicked_sprite = narrow and "bezierio-widen-black" or "bezierio-narrow-black",
        tooltip = { narrow and "tooltip.widen-window" or "tooltip.narrow-window" },
    })
    action_button(title_bar, {
        name = "main_close_button",
        tags = { group = "main", action = "close" },
        sprite = "utility/close",
        tooltip = { "tooltip.close-window" },
    })
end

--- @param player LuaPlayer
--- @param location GuiLocation|nil  # where to put it (default: top left)
function lib.create_main_window(player, location)
    -- The status and totals lines start empty; make jobs.lua fill them in again.
    local controller = state.get(player.index)
    controller.work.status, controller.work.totals_revision = nil, nil
    controller.ui.preset_mode = nil
    local ui = controller.ui

    local frame = player.gui.screen.add { type = "frame", name = "bezierio_window", direction = "vertical" }
    frame.location = location or { 75, 75 }
    if not ui.pinned and not ui.editing then player.opened = frame end
    -- (locked while a layer's settings are open)
    if ui.editing then frame.ignored_by_interaction = true end

    add_title_bar(frame, ui)
    local body = frame.add { type = "flow", name = "main", direction = "vertical" }
    body.style.vertical_spacing = 8
    body.style.width = ui.narrow and lib.NARROW_WIDTH or lib.WIDE_WIDTH
    curve_control.add(body, player)
    local layers = body.add { type = "frame", name = "layers_frame", direction = "vertical", style = "inside_shallow_frame_with_padding" }
    layers.style.horizontally_stretchable = true
    layers.add { type = "label", caption = { "label.section-layers" }, style = "caption_label" }
    preset_control.add(layers, player)
    layer_view.add(layers, player.index)
    control.add(body, player)
end

--- Close and open the window again where it was (after the narrow toggle).
--- @param player LuaPlayer
local function rebuild(player)
    layer_view.accept(player)
    view_settings.close_window(player)
    local window = player.gui.screen.bezierio_window
    local location = window and window.location
    if window then window.destroy() end
    lib.create_main_window(player, location)
end

--- @param e EventData.on_gui_click|EventData.on_gui_closed
lib["close"] = function(e)
    local player = game.get_player(e.player_index)
    if player and player.gui.screen.bezierio_window then
        layer_view.accept(player)
        view_settings.close_window(player)
        player.gui.screen.bezierio_window.destroy()
    end
end

--- @param e EventData.on_gui_click
lib["toggle"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    if player.gui.screen.bezierio_window then
        lib["close"](e)
    else
        lib.create_main_window(player)
    end
end

--- Pinned: not the player's opened GUI, so opening another one (or Esc) leaves
--- the window be.
--- @param e EventData.on_gui_click
lib["pin"] = function(e)
    local player = game.get_player(e.player_index)
    local window = player and player.gui.screen.bezierio_window
    if not (player and window) then return end
    local ui = state.ui(e.player_index)
    ui.pinned = e.element.toggled
    e.element.sprite = ui.pinned and "utility/track_button" or "utility/track_button_white"
    if ui.pinned then
        if player.opened == window then player.opened = nil end
    else
        player.opened = window
    end
end

--- @param e EventData.on_gui_click
lib["narrow"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local ui = state.ui(e.player_index)
    ui.narrow = not ui.narrow
    rebuild(player)
end

return lib
