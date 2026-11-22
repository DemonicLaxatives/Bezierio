local calc = require("scripts.curve_math.control")
local state = require("scripts.state")

local lib = {}

--- @param frame LuaGuiElement
function lib.add_curve_control_flow(frame)
    local player_index = frame.player_index
    local ui = state.ui(player_index)
    local curve = state.curve(player_index)

    local flow = frame.add {
        type = "flow",
        name = "button_flow",
        direction = "vertical"
    }

    local control_point_flow = flow.add {
        type = "flow",
        name = "control_point_flow",
        direction = "horizontal"
    }

    control_point_flow.add {
        type = "sprite-button",
        name = "control_points_clear",
        tags = { group = "curve", action = "clear" },
        tooltip = { "button.clear-all" },
        sprite = "utility/refresh",
        style = "tool_button"
    }

    local cp_table = flow.add {
        type = "table",
        name = "cp_table",
        column_count = 3
    }

    for i = 1, state.MAX_CONTROL_POINTS do
        cp_table.add {
            type = "button",
            name = "cp_button_" .. i,
            caption = "P" .. i,
            tooltip = { "tooltip.control-point" },
            tags = { group = "curve", action = "select_cp", idx = i },
            auto_toggle = true,
            style = "tool_button",
            toggled = ui.active_control_point == i
        }
        local point = curve.raw_control_points[i]
        for _, axis in pairs({ "x", "y" }) do
            local box = cp_table.add {
                type = "textfield",
                name = "cp_" .. axis .. "_" .. i,
                tags = { group = "curve", action = "update_cp", idx = i, axis = axis },
                text = point and point[axis] and tostring(point[axis]) or "",
                numeric = true,
                allow_decimal = true,
                allow_negative = true,
            }
            box.style.width = 60
        end
    end
end

--- @param idx integer
--- @param point Vector|nil
--- @param flow LuaGuiElement  # the cp_table
function lib.updateControlPointTextfields(idx, point, flow)
    flow["cp_x_" .. idx].text = point and point.x and tostring(point.x) or ""
    flow["cp_y_" .. idx].text = point and point.y and tostring(point.y) or ""
end

--- Left click: put that control point's pointer in the cursor (or take it away).
--- Right click: delete the control point.
--- @param e EventData.on_gui_click
lib["select_cp"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end

    local element = e.element
    local flow = element.parent --[[@as LuaGuiElement]]
    local idx = tonumber(element.tags.idx)
    if not idx then return end

    if e.button == defines.mouse_button_type.right then
        -- auto_toggle already flipped it; undo that
        element.toggled = not element.toggled
        calc.updateControlPoint(player, idx, nil)
        lib.updateControlPointTextfields(idx, nil, flow)
        return
    end

    -- Changing the cursor raises on_player_cursor_stack_changed, which syncs the buttons.
    if element.toggled then
        player.cursor_stack.set_stack { name = "bezierio-pointer-" .. idx, count = 1 }
    else
        player.cursor_stack.clear()
    end
end

--- @param e EventData.on_gui_click
lib["clear"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end

    calc.clear(player.index)

    local cp_table = e.element.parent.parent.cp_table
    for _, element in pairs(cp_table.children) do
        if element.type == "textfield" then
            element.text = ""
        end
    end
end

--- @param e EventData.on_gui_confirmed
lib["update_cp"] = function(e)
    local element = e.element
    local flow = element.parent --[[@as LuaGuiElement]]
    local axis = element.tags.axis --[[@as string]]
    local idx = tonumber(element.tags.idx)
    if not (axis == "x" or axis == "y") or not idx then return end

    local player = game.get_player(e.player_index)
    if not player then return end

    local old = state.curve(player.index).raw_control_points[idx]
    local point = { x = old and old.x, y = old and old.y }

    if element.text == "" then
        point[axis] = nil
    else
        local value = tonumber(element.text)
        if not value then
            lib.updateControlPointTextfields(idx, old, flow)
            return
        end
        point[axis] = value
    end

    if point.x == nil and point.y == nil then
        calc.updateControlPoint(player, idx, nil)
    else
        -- A half-entered point (only x or only y) is kept but not used by the curve.
        calc.updateControlPoint(player, idx, point)
    end
    lib.updateControlPointTextfields(idx, state.curve(player.index).raw_control_points[idx], flow)
end

return lib
