local state = require("scripts.state")
local builder = require("scripts.build.builder")

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
    local ui = state.ui(e.player_index)
    ui.draw_curve = e.element.toggled
    state.mark_dirty(e.player_index)
end

--- @param e EventData.on_gui_click
lib["preview_build"] = function(e)
    local ui = state.ui(e.player_index)
    ui.preview_build = e.element.toggled
    state.mark_dirty(e.player_index)
end

--- @param player LuaPlayer
--- @param mode BezierioBuildMode
local function build(player, mode)
    local curve = state.curve(player.index)
    if curve.degree < 1 then
        player.print({ "bezierio-message.need-two-points" })
        return
    end
    local plan = builder.plan(curve, state.layers(player.index))
    for _, idx in ipairs(plan.unsupported) do
        player.print({ "bezierio-message.unsupported-layer", idx })
    end
    local result = builder.execute(player, plan, mode)
    local message = result.instant and "bezierio-message.build-result-instant" or "bezierio-message.build-result"
    player.print({ message, result.placed, result.existing, result.blocked + plan.skipped })
end

--- @param e EventData.on_gui_click
lib["build"] = function(e)
    local player = game.get_player(e.player_index)
    if player then build(player, "forced") end
end

--- @param e EventData.on_gui_click
lib["super_build"] = function(e)
    local player = game.get_player(e.player_index)
    if player then build(player, "superforced") end
end

return lib
