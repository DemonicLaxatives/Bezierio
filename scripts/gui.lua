local draw = require("scripts.draw")

--- @param frame LuaGuiElement
local function add_title_bar(frame)
    if frame.title_bar then
        frame.title_bar.destroy()
    end
    local title_bar = frame.add{
        type = "flow", 
        name = "title_bar", 
        direction = "horizontal"
    }

    title_bar.add{
        type = "label",
        style = "frame_title",
        caption = {"titles.gui-title"},
        ignored_by_interaction = true
    }

    local dragger = title_bar.add{
        type = "empty-widget",
        style = "draggable_space_header",
    }
    dragger.style.horizontally_stretchable = true
    dragger.style.height = 24
    dragger.style.minimal_width = 24
    dragger.drag_target = frame

    title_bar.add{
        type = "sprite-button",
        name = "bezierio_close_button",
        sprite = "utility/close_white",
        style = "frame_action_button",
        mouse_button_filter = {"left"}
    }
end

--- @param frame LuaGuiElement
local function add_slider_flow(frame)
    local player_index = frame.player_index
    local state = global.controllers[player_index].state

    local flow = frame.add{
        type = "flow",
        name = "slider_flow",
        direction = "vertical"
    }

    flow.add{
        type = "choose-elem-button",
        name = "buildable",
        elem_type = "item",
        item = state.buildable,
        elem_filters = global.item_filter,
    }

    flow.add{
        type = "slider",
        name = "build_thickness",
        minimum_value = 1,
        maximum_value = 10,
        value = state.build_thickness
    }

    flow.add{
        type = "slider",
        name = "build_spacing",
        minimum_value = 1,
        maximum_value = 10,
        value = state.build_spacing
    }

    flow.add{
        type = "slider",
        name = "control_vector_strengh_1",
        minimum_value = 1,
        maximum_value = 1000,
        value = state.control_vector_strengh[1]
    }
    flow.add{
        type = "slider",
        name = "control_vector_strengh_2",
        minimum_value = 1,
        maximum_value = 1000,
        value = state.control_vector_strengh[2]
    }
end

--- @param frame LuaGuiElement
local function add_control_point_buttons(frame)
    local player_index = frame.player_index
    local state = global.controllers[player_index].state

    local flow = frame.add{
        type = "flow",
        name = "button_flow",
        direction = "vertical"
    }

    flow.add{
        type = "button",
        name = "control_point_p1",
        caption = {"button.p1"},
        auto_toggle = true
    }

    flow.add{
        type = "button",
        name = "control_point_p2",
        caption = {"button.p2"},
        auto_toggle = true
    }

    flow.add{
        type = "button",
        name = "control_point_v1",
        caption = {"button.v1"},
        auto_toggle = true
    }

    flow.add{
        type = "button",
        name = "control_point_v2",
        caption = {"button.v2"},
        auto_toggle = true
    }
end

--- @param frame LuaGuiElement
local function add_controls(frame)
    local player_index = frame.player_index
    local state = global.controllers[player_index].state

    frame.add{
        type = "button",
        name = "draw_curve",
        caption = {"button.draw-curve"},
        auto_toggle = true,
        toggled = state.draw_curve
    }

    add_slider_flow(frame)
    add_control_point_buttons(frame)
end

local function open_main_window(player)
    if player.gui.screen.bezierio_window then
        player.gui.screen.bezierio_window.destroy()
    end
    local frame = player.gui.screen.add{
        type = "frame",
        name = "bezierio_window",
        direction = "vertical"
    }
    frame.location = {75, 75}
    player.opened = frame

    add_title_bar(frame)

    frame.add{
        type = "flow",
        name = "main",
        direction = "horizontal"
    }
    add_controls(frame.main)
end

local function close_main_window(player)
    if player.gui.screen.bezierio_window then
        global.controllers[player.index].state.active_control_point = nil
        player.gui.screen.bezierio_window.destroy()
    end
end

--- @param e EventData.on_gui_click
local function active_control_point_changed(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local flow = player.gui.screen.bezierio_window.main.button_flow

    local state = global.controllers[e.player_index].state
    local previous_control_point = state.active_control_point

    --- untoggle the previous control point
    if previous_control_point then
        flow["control_point_"..previous_control_point].toggled = false
    end

    --- set the new active control point
    local element = e.element
    local control_point = element.name:match("control_point_(.*)")

    if element.toggled then
        state.active_control_point = control_point
    else
        state.active_control_point = nil
    end

    --- if it was a right click, reset the control point
    if e.button == defines.mouse_button_type.right then
        state.control_points[control_point] = nil
        state.parameters_changed = true
        draw.control_point(player, control_point)
    end
end

script.on_event(defines.events.on_gui_click,
function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local element = e.element
    if element.name == "bezierio_button" then
        if player.gui.screen.bezierio_window then
            close_main_window(player)
        else
            open_main_window(player)
        end
    elseif element.name == "bezierio_close_button" then
        close_main_window(player)
    elseif element.name == "draw_curve" then
        state = global.controllers[player.index].state
        state.draw_curve = element.toggled
        if not element.toggled then
            state.parameters_changed = true
        end
    elseif string.find(element.name, "control_point_") then
        active_control_point_changed(e)
    end
end)

script.on_event(defines.events.on_gui_value_changed,
function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local element = e.element
    local state = global.controllers[player.index].state
    if element.name == "build_thickness" then
        state.build_thickness = element.slider_value
    elseif element.name == "build_spacing" then
        state.build_spacing = element.slider_value
        state.parameters_changed = true
    elseif string.find(element.name, "control_vector_strengh_") then
        local index = tonumber(element.name:match("control_vector_strengh_(%d)"))
        if index then
            state.control_vector_strengh[index] = element.slider_value
            state.parameters_changed = true
        end
    end
end)


script.on_event(defines.events.on_gui_closed, 
function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    if player.gui.screen.bezierio_window then
        close_main_window(player)
    end
end)