local state = require("scripts.state")
local curve_lib = require("scripts.curve.curve")

local lib = {}

--- @param frame LuaGuiElement
function lib.add_control_flow(frame)
    local flow = frame.add {
        type = "flow",
        name = "control_flow",
        direction = "vertical"
    }

    local ui = state.ui(frame.player_index)

    flow.add {
        type = "button",
        name = "draw_curve",
        tags = { group = "control", action = "draw_curve" },
        caption = { "button.draw-curve" },
        auto_toggle = true,
        toggled = ui.draw_curve
    }

    flow.add {
        type = "button",
        name = "preview_build",
        tags = { group = "control", action = "preview_build" },
        caption = { "button.preview-build" },
        auto_toggle = true,
        toggled = ui.preview_build
    }

    flow.add {
        type = "sprite-button",
        name = "build",
        tags = { group = "control", action = "build" },
        sprite = "utility/ghost_cursor",
        tooltip = { "tooltip.force-build" },
    }

    flow.add {
        type = "sprite-button",
        name = "super_build",
        tags = { group = "control", action = "super_build" },
        sprite = "utility/force_ghost_cursor",
        tooltip = { "tooltip.super-force-build" }
    }
end

--- @param e EventData.on_gui_click
lib["draw_curve"] = function(e)
    state.ui(e.player_index).draw_curve = e.element.toggled
    state.request_redraw(e.player_index)
end

--- @param e EventData.on_gui_click
lib["preview_build"] = function(e)
    state.ui(e.player_index).preview_build = e.element.toggled
    state.request_redraw(e.player_index)
end

--- Building happens in the tick loop (jobs.lua) once the plan is ready.
--- @param player_index integer
--- @param mode BezierioBuildMode
local function request_build(player_index, mode)
    local player = game.get_player(player_index)
    if not player then return end
    if not curve_lib.is_drawable(state.curve(player_index)) then
        player.print({ "bezierio-message.need-two-points" })
        return
    end
    state.request_build(player_index, mode)
end

--- @param e EventData.on_gui_click
lib["build"] = function(e)
    request_build(e.player_index, "forced")
end

--- @param e EventData.on_gui_click
lib["super_build"] = function(e)
    request_build(e.player_index, "superforced")
end

return lib
