local layout = require("scripts.gui.layout")
local control_points = require("scripts.gui.control_points")
local draw = require("scripts.draw")

local lib = {}

function lib.close_main_window(player)
    if player.gui.screen.bezierio_window then
        player.gui.screen.bezierio_window.destroy()
    end
end

function lib.toggle_main_window(player)
    if player.gui.screen.bezierio_window then
        lib.close_main_window(player)
    else
        layout.create_main_window(player)
    end
end

script.on_event(defines.events.on_gui_click,
--- @param e EventData.on_gui_click
function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local element = e.element
    if element.get_mod() ~= "Bezierio" then return end
    if element.name == "bezierio_button" then
        lib.toggle_main_window(player)
    elseif element.name == "main_close_button" then
        lib.close_main_window(player)
    elseif element.name == "draw_curve" then
        state = storage.controllers[player.index].state
        state.draw_curve = element.toggled
        local curve_params = storage.controllers[player.index].curve_params
        if not element.toggled then
            curve_params.parameters_changed = true
            draw.delete_sprites(player)
        end
    elseif string.find(element.name, "cp_button") then
        control_points.button_clicked(e)
    elseif element.name == "control_points_clear" then
        control_points.clear_all(player)
    else
        if element.name:find("cp_x_") then return end
        if element.name:find("cp_y_") then return end
        player.print("Unhandled button event: "..element.name)
    end
end)

script.on_event(defines.events.on_gui_value_changed,
--- @param e EventData.on_gui_value_changed
function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local element = e.element
    if element.get_mod() ~= "Bezierio" then return end
    local state = storage.controllers[player.index].state
    local curve_params = storage.controllers[player.index].curve_params
    if element.name == "build_thickness" then
        state.build_thickness = element.slider_value
    elseif element.name == "build_spacing" then
        state.build_spacing = element.slider_value
        curve_params.parameters_changed = true
    elseif string.find(element.name, "control_vector_strengh_") then
        local index = tonumber(element.name:match("control_vector_strengh_(%d)"))
        if index then
            curve_params.parameters_changed = true
        end
    else
        player.print("Unhandled slider event: "..element.name)
    end
end)

script.on_event(defines.events.on_gui_confirmed,
--- @param e EventData.on_gui_confirmed
function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local element = e.element
    if element.get_mod() ~= "Bezierio" then return end
    if element.name:match("^cp_[xy]_%d$") then
        control_points.new_coordinate_confirmed(e)
    else
        player.print("Unhandled confirmed event: "..element.name)
    end
end)

script.on_event(defines.events.on_gui_elem_changed,
--- @param e EventData.on_gui_elem_changed
function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local element = e.element
    if element.get_mod() ~= "Bezierio" then return end
    local state = storage.controllers[player.index].state
    local curve_params = storage.controllers[player.index].curve_params
    if element.name == "buildable" then
        lib.state.buildable = element.elem_value
        curve_params.parameters_changed = true
    end
end)

script.on_event(defines.events.on_gui_closed,
function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    if player.gui.screen.bezierio_window then
        lib.close_main_window(player)
    end
end)

return lib