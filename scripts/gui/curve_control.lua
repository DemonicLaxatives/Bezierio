--- The curve panel: pointer button, closed-loop toggle, and the control point list
--- (group = "curve").
local curve_lib = require("scripts.curve.curve")
local state = require("scripts.state")
local window = require("scripts.gui.window")

local lib = {}

lib.POINTER = "bezierio-pointer"

--- @param player LuaPlayer
--- @return boolean
function lib.holds_pointer(player)
    local cursor = player.cursor_stack
    return cursor ~= nil and cursor.valid_for_read and cursor.name == lib.POINTER
end

--- @param pane LuaGuiElement
--- @param player_index integer
local function fill_points(pane, player_index)
    pane.clear()
    local curve = state.curve(player_index)
    local held = state.ui(player_index).held_point
    if #curve.points == 0 then
        pane.add { type = "label", name = "no_points", caption = { "label.no-points" } }
        return
    end
    local cp_table = pane.add { type = "table", name = "cp_table", column_count = 4 }
    for i, point in ipairs(curve.points) do
        local label = cp_table.add { type = "label", name = "cp_label_" .. i, caption = "P" .. i }
        if i == held then label.style.font_color = { r = 1, g = 0.85, b = 0.2 } end
        for _, axis in pairs({ "x", "y" }) do
            local box = cp_table.add {
                type = "textfield",
                name = "cp_" .. axis .. "_" .. i,
                tags = { group = "curve", action = "update_cp", idx = i, axis = axis },
                text = tostring(point[axis]),
                numeric = true,
                allow_decimal = true,
                allow_negative = true,
            }
            box.style.width = 60
        end
        local delete = cp_table.add {
            type = "sprite-button",
            name = "cp_delete_" .. i,
            sprite = "utility/close",
            tooltip = { "tooltip.delete-point" },
            tags = { group = "curve", action = "delete", idx = i },
            style = "tool_button",
        }
        delete.style.size = 24
    end
end

--- @param parent LuaGuiElement
--- @param player LuaPlayer
function lib.add(parent, player)
    local curve = state.curve(player.index)
    local frame = parent.add { type = "frame", name = "curve_frame", direction = "vertical", style = "inside_shallow_frame_with_padding" }

    local header = frame.add { type = "flow", name = "curve_header", direction = "horizontal" }
    header.style.vertical_align = "center"
    header.add {
        type = "sprite-button",
        name = "pointer_button",
        sprite = "item/" .. lib.POINTER,
        tooltip = { "tooltip.pointer-button" },
        tags = { group = "curve", action = "pointer" },
        auto_toggle = true,
        toggled = lib.holds_pointer(player),
        style = "tool_button",
    }
    header.add {
        type = "checkbox",
        name = "closed_loop",
        caption = { "checkbox.closed-loop" },
        tooltip = { "tooltip.closed-loop" },
        state = curve.closed,
        tags = { group = "curve", action = "closed" },
    }
    header.add {
        type = "sprite-button",
        name = "control_points_clear",
        tags = { group = "curve", action = "clear" },
        tooltip = { "button.clear-all" },
        sprite = "utility/trash",
        style = "tool_button",
    }

    local pane = frame.add {
        type = "scroll-pane",
        name = "points_pane",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy = "auto-and-reserve-space",
    }
    pane.style.maximal_height = 300
    fill_points(pane, player.index)
end

--- Rebuild the point list (after points were added, moved or removed).
--- @param player LuaPlayer
function lib.refresh_points(player)
    local pane = window.find(player, "points_pane")
    if pane then fill_points(pane, player.index) end
end

--- Keep the pointer button in sync with the cursor.
--- @param player LuaPlayer
function lib.sync_pointer_button(player)
    local button = window.find(player, "pointer_button")
    if button then button.toggled = lib.holds_pointer(player) end
end

--- The curve changed: plan again and show the new point list.
--- @param player LuaPlayer
function lib.points_changed(player)
    state.changed(player.index)
    lib.refresh_points(player)
end

--- @param e EventData.on_gui_click
lib["pointer"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    if e.element.toggled then
        player.cursor_stack.set_stack { name = lib.POINTER, count = 1 }
    elseif lib.holds_pointer(player) then
        player.cursor_stack.clear()
    end
end

--- @param e EventData.on_gui_checked_state_changed
lib["closed"] = function(e)
    state.curve(e.player_index).closed = e.element.state
    state.changed(e.player_index)
end

--- @param e EventData.on_gui_click
lib["clear"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    curve_lib.clear(state.curve(e.player_index))
    state.ui(e.player_index).held_point = nil
    lib.points_changed(player)
end

--- @param e EventData.on_gui_click
lib["delete"] = function(e)
    local player = game.get_player(e.player_index)
    local idx = tonumber(e.element.tags.idx)
    if not player or not idx then return end
    lib.remove_point(player, idx)
end

--- Remove a point, keeping a held point held.
--- @param player LuaPlayer
--- @param idx integer
function lib.remove_point(player, idx)
    local ui = state.ui(player.index)
    curve_lib.remove(state.curve(player.index), idx)
    if ui.held_point == idx then
        ui.held_point = nil
    elseif ui.held_point and ui.held_point > idx then
        ui.held_point = ui.held_point - 1
    end
    lib.points_changed(player)
end

--- @param e EventData.on_gui_confirmed
lib["update_cp"] = function(e)
    local player = game.get_player(e.player_index)
    local element = e.element
    local axis = element.tags.axis --[[@as string]]
    local idx = tonumber(element.tags.idx)
    if not player or not (axis == "x" or axis == "y") or not idx then return end

    local curve = state.curve(e.player_index)
    local old = curve.points[idx]
    if not old then return end
    local value = tonumber(element.text)
    if not value then
        element.text = tostring(old[axis])
        return
    end
    local point = { x = old.x, y = old.y }
    point[axis] = value
    curve_lib.set_point(curve, idx, point)
    element.text = tostring(curve.points[idx][axis])
    state.changed(e.player_index)
end

return lib
