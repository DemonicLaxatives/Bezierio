local buildable_layers = require("scripts.gui.buildable_layers")
local curve_control = require("scripts.gui.curve_control")
local control = require("scripts.gui.control")

local lib = {}

--- @param frame LuaGuiElement
function lib.add_title_bar(frame)
    if frame.title_bar then
        frame.title_bar.destroy()
    end
    local title_bar = frame.add{
        type = "flow", 
        name = "title_bar", 
        direction = "horizontal"
    }

    title_bar.add{
        type = "label",
        style = "frame_title",
        caption = {"titles.gui-title"},
        ignored_by_interaction = true
    }

    local dragger = title_bar.add{
        type = "empty-widget",
        style = "draggable_space_header",
    }
    dragger.style.horizontally_stretchable = true
    dragger.style.height = 24
    dragger.style.minimal_width = 24
    dragger.drag_target = frame

    title_bar.add{
        type = "sprite-button",
        name = "main_close_button",
        tags = {group = "main", action = "close"},
        sprite = "utility/close",
        style = "frame_action_button",
        mouse_button_filter = {"left"}
    }
end

--- @param frame LuaGuiElement
function lib.add_controls(frame)
    control.add_control_flow(frame)
    curve_control.add_curve_control_flow(frame)
    buildable_layers.add_layer_controls(frame)
end

function lib.create_main_window(player)
    local frame = player.gui.screen.add{
        type = "frame",
        name = "bezierio_window",
        direction = "vertical"
    }
    frame.location = {75, 75}
    player.opened = frame

    lib.add_title_bar(frame)

    frame.add{
        type = "flow",
        name = "main",
        direction = "horizontal"
    }
    lib.add_controls(frame.main)
end

--- @param e EventData.on_gui_click|EventData.on_gui_closed
lib["close"] = function (e)
    local player = game.get_player(e.player_index)
    if not player then return end

    if player.gui.screen.bezierio_window then
        player.gui.screen.bezierio_window.destroy()
    end
end

--- @param e EventData.on_gui_click
lib["toggle"] = function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    if player.gui.screen.bezierio_window then
            lib["close"](e)
    else
        lib.create_main_window(player)
    end
end

return lib