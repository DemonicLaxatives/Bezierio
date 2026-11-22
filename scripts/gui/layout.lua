--- The main window (group = "main"): controls and curve on the left, layers on the right.
local control = require("scripts.gui.control")
local curve_control = require("scripts.gui.curve_control")
local layer_view = require("scripts.gui.layer_view")
local view_settings = require("scripts.gui.view_settings")
local preset_control = require("scripts.gui.preset_control")
local state = require("scripts.state")

local lib = {}

--- @param frame LuaGuiElement
local function add_title_bar(frame)
    local title_bar = frame.add { type = "flow", name = "title_bar", direction = "horizontal" }
    title_bar.add {
        type = "label",
        style = "frame_title",
        caption = { "titles.gui-title" },
        ignored_by_interaction = true,
    }
    local dragger = title_bar.add { type = "empty-widget", style = "draggable_space_header" }
    dragger.style.horizontally_stretchable = true
    dragger.style.height = 24
    dragger.style.minimal_width = 24
    dragger.drag_target = frame
    title_bar.add {
        type = "sprite-button",
        name = "main_close_button",
        tags = { group = "main", action = "close" },
        sprite = "utility/close",
        style = "frame_action_button",
        mouse_button_filter = { "left" },
    }
end

--- @param player LuaPlayer
function lib.create_main_window(player)
    -- The status and totals lines start empty; make jobs.lua fill them in again.
    local controller = state.get(player.index)
    controller.work.status, controller.work.totals_revision = nil, nil
    controller.ui.preset_mode = nil

    local frame = player.gui.screen.add { type = "frame", name = "bezierio_window", direction = "vertical" }
    frame.location = { 75, 75 }
    player.opened = frame

    add_title_bar(frame)
    local main = frame.add { type = "flow", name = "main", direction = "horizontal" }
    local left = main.add { type = "flow", name = "left_column", direction = "vertical" }
    control.add(left, player)
    view_settings.add(left, player)
    curve_control.add(left, player)
    local right = main.add { type = "flow", name = "right_column", direction = "vertical" }
    preset_control.add(right, player)
    layer_view.add(right, player.index)
end

--- @param e EventData.on_gui_click|EventData.on_gui_closed
lib["close"] = function(e)
    local player = game.get_player(e.player_index)
    if player and player.gui.screen.bezierio_window then
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

return lib
