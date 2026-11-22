local draw = require("scripts.draw")
local vect = require("scripts.vector_math")
local calc = require("scripts.curve_math.control")

local lib = {}

--- @param frame LuaGuiElement
function lib.add_curve_control_flow(frame)
    local player_index = frame.player_index
    local controller = storage.controllers[player_index]
    local state = controller.state
    local curve_params = controller.curve_cache[controller.state.preset_indx][0]

    local flow = frame.add{
        type = "flow",
        name = "button_flow",
        direction = "vertical"
    }

    local control_point_flow = flow.add{
        type = "flow",
        name = "control_point_flow",
        direction = "horizontal"
    }

    control_point_flow.add{
        type = "sprite-button",
        name = "control_points_clear",
        tags = {group = "curve", action = "clear"},
        tooltip = {"button.clear-all"},
        sprite = "utility/refresh",
        style = "tool_button"
    }

    local table = flow.add{
        type = "table",
        name = "cp_table",
        column_count = 3
    }

    for i = 1, 9 do
        table.add{
            type = "button",
            name = "cp_button_"..i,
            caption = "P"..i,
            tags = {group = "curve", action = "select_cp", idx = i},
            auto_toggle = true,
            style = "tool_button",
            toggled = state.active_control_point == i
        }
        local x = ""
        local y = ""
        if curve_params.raw_control_points[i] then
            x = tostring(curve_params.raw_control_points[i].x)
            y = tostring(curve_params.raw_control_points[i].y)
        end
        local x_box = table.add{
            type = "textfield",
            name = "cp_x_"..i,
            tags = {group = "curve", action = "update_cp", idx = i, axis = "x"},
            text = x
        }
        x_box.style.width = 60
        local y_box = table.add{
            type = "textfield",
            name = "cp_y_"..i,
            tags = {group = "curve", action = "update_cp", idx = i, axis = "y"},
            text = y
        }
        y_box.style.width = 60
    end
end

--- @param idx integer
--- @param point Vector|nil
--- @param flow LuaGuiElement
function lib.updateControlPointTextfields(idx, point, flow)
    local x = ""
    local y = ""
    if point then
        if point.x then
            x = tostring(point.x)
        end
        if point.y then
            y = tostring(point.y)
        end
    end
    flow["cp_x_"..idx].text = x
    flow["cp_y_"..idx].text = y
end

--- @param e EventData.on_gui_click
lib["select_cp"] = function (e)
    local player = game.get_player(e.player_index)
    if not player then return end

    local element = e.element
    local flow = element.parent
    if not flow then
        error("No parent flow found")
    end

    local idx = tonumber(element.tags.idx)
    if not idx then return end

    local right_click = e.button == defines.mouse_button_type.right
    local button_state = element.toggled

    --- Right click clears the control point and nothing else
    if right_click then
        flow["cp_button_"..idx].toggled = not button_state
        lib.updateControlPoint(player, idx, nil)
        lib.updateControlPointTextfields(idx, nil, flow)
        return
    end

    --- Changing the cursor_stack will trigger on_player_cursor_stack_changed event
    --- That is where the logic is
    if button_state then
        player.cursor_stack.set_stack{name = "bezierio-pointer-"..idx, count = 1}
    else
        player.cursor_stack.clear()
    end
end

--- @param e EventData.on_gui_click
lib["clear"] = function (e)
    local player = game.get_player(e.player_index)
    if not player then return end

    local controller = storage.controllers[e.player_index]
    curve_params_ = controller.curve_cache[controller.state.current_layer]
    
    curve_params_ = {}
    curve_params_[0] = {}

    local curve_params = curve_params_[0]
    curve_params.raw_control_points = {}
    curve_params.control_points = {}
    curve_params.p0 = nil
    curve_params.degree = -1
    curve_params.parameters_changed = true

    draw.control_points(player)

    local flow = e.element.parent.parent
    if not flow then return end
    for _, element in pairs(flow.cp_table.children) do
        if element.type == "textfield" then
            element.text = ""
        end
    end
end

--- @param e EventData.on_gui_confirmed
lib["update_cp"] = function (e)
    local flow = e.element.parent
    if not flow then return end

    local element = e.element
    local axis = tostring(element.tags.axis)
    local idx = tonumber(element.tags.idx)
    if not axis or not idx then
        error("Invalid element tags")
    end

    local player = game.get_player(e.player_index)
    if not player then return end
    local curve_params = storage.controllers[player.index].state.curve_parameters

    local value = nil
    local point = curve_params.raw_control_points[idx]

    if element.text ~= "" then
        value = tonumber(element.text)
        if not value then
            if point then
                if point[axis] then
                    flow[element.name].text = tostring(point[axis])
                    return
                end
            end
        end
    end

    point[axis] = value

    calc.updateControlPoint(player, idx, point)
    lib.updateControlPointTextfields(idx, point, flow)
end

return lib