local draw = require("scripts.draw")
local vect = require("scripts.vector_math")
local calc = require("scripts.calc")

local lib = {}

--- Filter out points containting nil 
--- @param points Vector[]
--- @return Vector[], Vector|nil
function lib.processControlPoints(points)
    local filtered_points = {}
    local p0 = nil
    for _, point in pairs(points) do
        if point then
            if point.x and point.y then
                if not p0 then
                    p0 = point
                end
                table.insert(filtered_points, vect.sub(point, p0))
            end
        end
    end
    return filtered_points, p0
end

--- @param player LuaPlayer
--- @param idx integer
--- @param point Vector|nil
function lib.updateControlPoint(player, idx, point)
    local curve_params = storage.controllers[player.index].curve_params

    if point then
        if point.x then
            point.x = vect.D1.round(point.x, 2)
        end
        if point.y then
            point.y = vect.D1.round(point.y, 2)
        end
    end

    curve_params.raw_control_points[idx] = point
    local control_points, p0 = lib.processControlPoints(curve_params.raw_control_points)

    curve_params.control_points = control_points
    curve_params.p0 = p0
    curve_params.degree = #control_points - 1
    curve_params.parameters_changed = true

    draw.control_points(player)

    local window = player.gui.screen.bezierio_window
    if not window then return end
    local flow = window.main.button_flow.cp_table
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
function lib.button_clicked(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local flow = player.gui.screen.bezierio_window.main.button_flow.cp_table

    local element = e.element
    local idx = tonumber(element.name:match("cp_button_(.*)"))
    if not idx then return end

    local right_click = e.button == defines.mouse_button_type.right
    local button_state = flow["cp_button_"..idx].toggled

    --- Right click clears the control point and nothing else
    if right_click then
        flow["cp_button_"..idx].toggled = not button_state
        lib.updateControlPoint(player, idx, nil)
        return
    end

    --- Changing the cursor_stack will trigger on_player_cursor_stack_changed event
    --- That is where majority of the logic is
    if button_state then
        player.cursor_stack.set_stack{name = "bezierio-pointer-"..idx, count = 1}
    else
        player.cursor_stack.clear()
    end
end

--- @param player LuaPlayer
function lib.clear_all(player)
    local curve_params = storage.controllers[player.index].curve_params
    curve_params.raw_control_points = {}
    curve_params.control_points = {}
    curve_params.p0 = nil
    curve_params.degree = -1
    curve_params.parameters_changed = true

    draw.control_points(player)

    local window = player.gui.screen.bezierio_window
    if not window then return end
    local flow = window.main.button_flow.cp_table
    for i = 1, 9 do
        flow["cp_x_"..i].text = ""
        flow["cp_y_"..i].text = ""
    end
end

--- @param e EventData.on_gui_confirmed
function lib.new_coordinate_confirmed(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local curve_params = storage.controllers[player.index].curve_params
    
    local flow = player.gui.screen.bezierio_window.main.button_flow.cp_table
    
    local element = e.element
    local axis, idx = element.name:match("^cp_([xy])_(%d)")
    idx = tonumber(idx)
    if not axis or not idx then
        error("Invalid element name")
    end

    local value = nil
    local point = curve_params.raw_control_points[idx]

    if element.text ~= "" then
        value = tonumber(element.text)
        if not value then
            flow[element.name].text = tostring(point[axis])
            return
        end
    end

    point[axis] = value

    lib.updateControlPoint(player, idx, point)
end

return lib