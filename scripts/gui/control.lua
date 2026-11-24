local state = require("scripts.state")
local curve_lib = require("scripts.curve.curve")
local highlight = require("scripts.highlight")
local curve_control = require("scripts.gui.curve_control")
local preset_control = require("scripts.gui.preset_control")

local lib = {}

--- The Build section: Draw / Preview (and the view settings), the build buttons,
--- and the status and totals lines.
--- @param parent LuaGuiElement
--- @param player LuaPlayer
function lib.add(parent, player)
    local ui = state.ui(player.index)
    local narrow = ui.narrow == true
    local flow = parent.add { type = "frame", name = "control_flow", direction = "vertical", style = "inside_shallow_frame_with_padding" }
    flow.style.horizontally_stretchable = true
    flow.add { type = "label", caption = { "label.section-build" }, style = "caption_label" }

    local view = flow.add { type = "flow", name = "control_view", direction = "horizontal" }
    view.style.horizontal_spacing = 8
    view.style.vertical_align = "center"
    for _, b in ipairs({ { "draw_curve", "button.draw-curve", ui.draw_curve }, { "preview_build", "button.preview-build", ui.preview_build } }) do
        local button = view.add {
            type = "button",
            name = b[1],
            tags = { group = "control", action = b[1] },
            caption = { b[2] },
            auto_toggle = true,
            toggled = b[3],
        }
        button.style.horizontally_stretchable = true
        button.style.minimal_width = 0
    end

    local buttons = flow.add { type = "flow", name = "control_buttons", direction = "horizontal" }
    buttons.style.horizontal_spacing = 8
    buttons.style.top_margin = 4
    local function add_button(name, action, sprite, tooltip)
        buttons.add {
            type = "sprite-button",
            name = name,
            tags = { group = "control", action = action },
            sprite = sprite,
            tooltip = { tooltip },
            style = "tool_button",
        }
    end
    add_button("normal_build", "normal_build", "bezierio-build", "tooltip.normal-build")
    add_button("build", "build", "bezierio-force-build", "tooltip.force-build")
    add_button("super_build", "super_build", "bezierio-super-force-build", "tooltip.super-force-build")
    add_button("blueprint_build", "blueprint", "item/blueprint", "tooltip.blueprint-build")
    add_button("blueprint_load", "blueprint_load", "utility/import", "tooltip.blueprint-load")
    local status = flow.add { type = "label", name = "status", caption = "", visible = false }
    status.style.single_line = false

    -- The summary, in its own sunken pane: length / items / warnings, divided by
    -- lines. Filled in (and shown) by jobs.lua once a plan is done. Narrow: the
    -- items are in the length's tooltip.
    local totals = flow.add { type = "frame", name = "totals", direction = "vertical", style = "inside_deep_frame", visible = false }
    totals.style.horizontally_stretchable = true
    totals.style.padding = 8
    totals.style.top_margin = 8
    -- The first row: the length (or what's happening, with a cancel button for builds).
    local head = totals.add { type = "flow", name = "totals_head", direction = "horizontal" }
    head.style.vertical_align = "center"
    local length = head.add { type = "label", name = "totals_length", caption = "", style = "bold_label" }
    length.style.single_line = false
    length.style.horizontally_stretchable = true
    local cancel = head.add {
        type = "sprite-button",
        name = "build_cancel",
        sprite = "utility/close",
        tooltip = { "tooltip.build-cancel" },
        tags = { group = "control", action = "cancel_build" },
        style = "tool_button",
        visible = false,
    }
    cancel.style.size = 24
    -- (while planning or building: the progress above, this bar, no summary)
    local bar = totals.add { type = "progressbar", name = "totals_progress", value = 0, visible = false }
    bar.style.horizontally_stretchable = true
    totals.add { type = "line", name = "totals_line_items", visible = not narrow }
    local items = totals.add { type = "label", name = "totals_items", caption = "", visible = not narrow }
    items.style.single_line = false
    items.style.maximal_width = 370
    totals.add { type = "line", name = "totals_line_warnings", visible = false }
    local warnings = totals.add { type = "flow", name = "totals_warnings", direction = narrow and "vertical" or "horizontal" }
    if not narrow then warnings.style.horizontal_spacing = 12 end
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

--- Cancel the queued command and stop the running build (what's built stays, one
--- undo step).
--- @param e EventData.on_gui_click
lib["cancel_build"] = function(e)
    local player = game.get_player(e.player_index)
    local work = state.get(e.player_index).work
    local had = work.build ~= nil or work.pending_build ~= nil
    work.pending_build, work.build = nil, nil
    if player and had then player.print({ "bezierio-message.build-cancelled" }) end
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
lib["normal_build"] = function(e)
    request_build(e.player_index, "normal")
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
