local state = require("scripts.state")
local curve_lib = require("scripts.curve.curve")
local view_settings = require("scripts.gui.view_settings")

local lib = {}

--- Buttons, and the status and totals lines.
--- @param parent LuaGuiElement
--- @param player LuaPlayer
function lib.add(parent, player)
    local ui = state.ui(player.index)
    local flow = parent.add { type = "flow", name = "control_flow", direction = "vertical" }
    local buttons = flow.add { type = "flow", name = "control_buttons", direction = "horizontal" }
    buttons.add {
        type = "button",
        name = "draw_curve",
        tags = { group = "control", action = "draw_curve" },
        caption = { "button.draw-curve" },
        auto_toggle = true,
        toggled = ui.draw_curve,
    }
    buttons.add {
        type = "button",
        name = "preview_build",
        tags = { group = "control", action = "preview_build" },
        caption = { "button.preview-build" },
        auto_toggle = true,
        toggled = ui.preview_build,
    }
    buttons.add {
        type = "sprite-button",
        name = "build",
        tags = { group = "control", action = "build" },
        sprite = "bezierio-force-build",
        tooltip = { "tooltip.force-build" },
        style = "tool_button",
    }
    buttons.add {
        type = "sprite-button",
        name = "super_build",
        tags = { group = "control", action = "super_build" },
        sprite = "bezierio-super-force-build",
        tooltip = { "tooltip.super-force-build" },
        style = "tool_button",
    }
    buttons.add {
        type = "sprite-button",
        name = "blueprint_build",
        tags = { group = "control", action = "blueprint" },
        sprite = "item/blueprint",
        tooltip = { "tooltip.blueprint-build" },
        style = "tool_button",
    }
    view_settings.add_toggle(buttons)
    flow.add { type = "label", name = "status", caption = "" }

    -- Filled in by jobs.lua once the preview's plan is done.
    local totals = flow.add { type = "flow", name = "totals", direction = "vertical" }
    totals.style.vertical_spacing = 0
    totals.add { type = "label", name = "totals_length", caption = "" }
    local items = totals.add { type = "label", name = "totals_items", caption = "" }
    items.style.single_line = false
    items.style.maximal_width = 320
    local warnings = totals.add { type = "flow", name = "totals_warnings", direction = "horizontal" }
    for _, name in ipairs({ "bends", "gaps", "unpowered" }) do
        local label = warnings.add {
            type = "label",
            name = "totals_" .. name,
            caption = "",
            tooltip = { "tooltip.totals-" .. name },
            visible = false,
        }
        label.style.font_color = { r = 1, g = 0.3, b = 0.3 }
    end
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
--- @param mode BezierioBuildMode|"blueprint"
local function request_build(player_index, mode)
    local player = game.get_player(player_index)
    if not player then return end
    local group = player.permission_group
    if group and mode ~= "blueprint" and not group.allows_action(defines.input_action.build) then
        player.print({ "bezierio-message.not-allowed" })
        return
    end
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

--- @param e EventData.on_gui_click
lib["blueprint"] = function(e)
    request_build(e.player_index, "blueprint")
end

return lib
