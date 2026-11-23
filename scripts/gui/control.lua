local state = require("scripts.state")
local curve_lib = require("scripts.curve.curve")
local view_settings = require("scripts.gui.view_settings")
local highlight = require("scripts.highlight")
local curve_control = require("scripts.gui.curve_control")
local preset_control = require("scripts.gui.preset_control")

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
    buttons.add {
        type = "sprite-button",
        name = "blueprint_load",
        tags = { group = "control", action = "blueprint_load" },
        sprite = "utility/import",
        tooltip = { "tooltip.blueprint-load" },
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
    for _, name in ipairs({ "bends", "gaps", "unpowered", "unfed" }) do
        -- (unpowered and unfed: click to mark them on the map)
        local clickable = name == "unpowered" or name == "unfed"
        local label = warnings.add {
            type = "label",
            name = "totals_" .. name,
            caption = "",
            tooltip = { "tooltip.totals-" .. name },
            visible = false,
            tags = clickable and { group = "control", action = "highlight_" .. name } or nil,
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

--- Show or hide the marks for one kind of warning, from the preview's plan.
--- @param e EventData.on_gui_click
--- @param kind HighlightKind
local function toggle_highlight(e, kind)
    local player = game.get_player(e.player_index)
    local controller = state.get(e.player_index)
    local plan_job = controller.work.plan
    if not (player and plan_job and plan_job.plan.done) then return end
    highlight.toggle(player, controller, plan_job.plan, kind)
end

--- @param e EventData.on_gui_click
lib["highlight_unpowered"] = function(e) toggle_highlight(e, "unpowered") end

--- @param e EventData.on_gui_click
lib["highlight_unfed"] = function(e) toggle_highlight(e, "unfed") end

--- The blueprint the player holds: from the inventory or the blueprint library, the
--- active one in a book.
--- @param player LuaPlayer
--- @return LuaItemStack|LuaRecord|nil
local function held_blueprint(player)
    local stack = player.cursor_stack
    if stack and stack.valid_for_read then
        local item = stack --[[@as LuaItemStack|LuaItemCommon]]
        for _ = 1, 10 do -- (books in books)
            if item.is_blueprint then return item end
            if not item.is_blueprint_book then return nil end
            local inventory = item.get_inventory(defines.inventory.item_main)
            local active = inventory and item.active_index and inventory[item.active_index]
            if not (active and active.valid_for_read) then return nil end
            item = active
        end
        return nil
    end
    local record = player.cursor_record
    if record and record.valid and record.type == "blueprint" then return record end
    return nil
end

--- Load the curve and preset a Bézierio blueprint carries (see jobs.lua): they are
--- tags on its first entity.
--- @param e EventData.on_gui_click
lib["blueprint_load"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local bp = held_blueprint(player)
    if not bp then
        player.print({ "bezierio-message.blueprint-load-none" })
        return
    end
    local source
    if bp.is_blueprint_setup() then
        -- (first entity; a few more in case the blueprint was edited)
        for i = 1, math.min(bp.get_blueprint_entity_count(), 20) do
            local tag = bp.get_blueprint_entity_tag(i, "bezierio")
            if type(tag) == "table" and tag.curve and tag.preset then
                source = tag
                break
            end
        end
    end
    if not source then
        player.print({ "bezierio-message.blueprint-load-no-data" })
        return
    end
    local curve_ok = curve_control.load(player, source.curve)
    local preset_ok = preset_control.load(player, source.preset)
    state.changed(player.index)
    if curve_ok and preset_ok then player.print({ "bezierio-message.blueprint-loaded" }) end
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
