local draw = require("scripts.draw")
local cp = require("scripts.gui.control_points")

script.on_event("bezierio-pointer",
--- @param e EventData.CustomInputEvent
function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local cursor = player.cursor_stack
    if not cursor then return end
    if not cursor.valid_for_read then return end

    if string.find(cursor.name, "bezierio") then
        local control_point = tonumber(string.sub(cursor.name, -1))
        if not control_point then
            error("Invalid control point name")
        end

        local state = storage.controllers[e.player_index].state
        local active_control_point = state.active_control_point
        if active_control_point ~= control_point then
            error("Active control point does not match cursor stack")
        end

        cp.updateControlPoint(player, control_point, e.cursor_position)
        draw.control_points(player)
    end
end)

script.on_event("bezierio-pointer-up",
--- @param e EventData.CustomInputEvent
function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local cursor = player.cursor_stack
    if not cursor then return end
    if not cursor.valid_for_read then return end

    if string.find(cursor.name, "bezierio") then
        local control_point = tonumber(string.sub(cursor.name, -1))
        if not control_point then
            error("Invalid control point name")
        end

        local new_pointer = (control_point % 9) + 1
        player.cursor_stack.set_stack{name = "bezierio-pointer-"..new_pointer, count = 1}
    end
end)

script.on_event("bezierio-pointer-down",
--- @param e EventData.CustomInputEvent
function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local cursor = player.cursor_stack
    if not cursor then return end
    if not cursor.valid_for_read then return end

    if string.find(cursor.name, "bezierio") then
        local control_point = tonumber(string.sub(cursor.name, -1))
        if not control_point then
            error("Invalid control point name")
        end

        local new_pointer = (control_point - 2) % 9 + 1
        player.cursor_stack.set_stack{name = "bezierio-pointer-"..new_pointer, count = 1}
    end
end)

--- @param e EventData.on_player_cursor_stack_changed
script.on_event(defines.events.on_player_cursor_stack_changed, function(e)
    local player = game.get_player(e.player_index)
    if not player then return end

    local state = storage.controllers[e.player_index].state
    local prev_cp = state.active_control_point

    local cursor = player.cursor_stack
    local current_cp = nil
    if cursor then
        if cursor.valid_for_read then
            if string.find(cursor.name, "bezierio") then 
                current_cp = tonumber(string.sub(cursor.name, -1))
                if not current_cp then
                    error("Invalid control point name")
                end
            end
        end
    end

    if not prev_cp and not current_cp then return end
    state.active_control_point = current_cp

    local window = player.gui.screen.bezierio_window
    if not window then return end
    local flow = window.main.button_flow.cp_table
    
    if prev_cp then 
        flow["cp_button_"..prev_cp].toggled = false
    end
    if current_cp then
        flow["cp_button_"..current_cp].toggled = true
    end
end)