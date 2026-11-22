local debug = require("scripts.debug")

local lib = {}

--- @param frame LuaGuiElement
function lib.add_control_flow(frame)
    local flow = frame.add{
        type = "flow",
        name = "control_flow",
        direction = "vertical"
    }

    local player_index = frame.player_index
    local state = storage.controllers[player_index].state

    flow.add{
        type = "button",
        name = "draw_curve",
        tags = {group = "control", action = "draw_curve"},
        caption = {"button.draw-curve"},
        auto_toggle = true,
        toggled = state.draw_curve
    }

    flow.add{
        type = "button",
        name = "preview_build",
        tags = {group = "control", action = "preview_build"},
        caption = {"button.preview-build"},
        auto_toggle = true,
        toggled = state.preview_build
    }

    flow.add{
        type = "sprite-button",
        name = "build",
        tags = {group = "control", action = "build"},
        sprite = "utility/ghost_cursor",
        tooltip = {"tooltip.force-build"},
    }

    flow.add{
        type = "sprite-button",
        name = "super_build",
        tags = {group = "control", action = "super_build"},
        sprite = "utility/force_ghost_cursor",
        tooltip = {"tooltip.super-force-build"}
    }
end

--- @param e EventData.on_gui_click
lib["draw_curve"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local state = storage.controllers[player.index].state
    state.draw_curve = e.element.toggled
end

--- @param e EventData.on_gui_click
lib["preview_build"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local state = storage.controllers[player.index].state
    state.preview_build = e.element.toggled
end

--- @param e EventData.on_gui_click
lib["build"] = function(e)
    debug.print("Not implemented")
end

--- @param e EventData.on_gui_click
lib["super_build"] = function(e)
    debug.print("Not implemented")
end

return lib