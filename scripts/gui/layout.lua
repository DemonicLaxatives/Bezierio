local lib = {}

--- @param frame LuaGuiElement
function lib.add_title_bar(frame)
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
        name = "main_close_button",
        sprite = "utility/close",
        style = "frame_action_button",
        mouse_button_filter = {"left"}
    }
end


--- @param frame LuaGuiElement
function lib.add_slider_flow(frame)
    local player_index = frame.player_index
    local state = storage.controllers[player_index].state

    local flow = frame.add{
        type = "flow",
        name = "slider_flow",
        direction = "vertical"
    }

    flow.add{
        type = "choose-elem-button",
        name = "buildable",
        elem_type = "item-with-quality" ,
        item_with_quality = state.buildable,
        elem_filters = storage.item_filter,
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
end

--- @param frame LuaGuiElement
function lib.add_control_point_buttons(frame)
    local player_index = frame.player_index
    local controller = storage.controllers[player_index]
    local state = controller.state
    local curve_params = controller.curve_params

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
            caption = i,
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
            text = x
        }
        x_box.style.width = 60
        local y_box = table.add{
            type = "textfield",
            name = "cp_y_"..i,
            text = y
        }
        y_box.style.width = 60
    end
end

--- @param frame LuaGuiElement
function lib.add_controls(frame)
    local player_index = frame.player_index
    local state = storage.controllers[player_index].state

    frame.add{
        type = "button",
        name = "draw_curve",
        caption = {"button.draw-curve"},
        auto_toggle = true,
        toggled = state.draw_curve
    }

    lib.add_slider_flow(frame)
    lib.add_control_point_buttons(frame)
end

function lib.create_main_window(player)
    local frame = player.gui.screen.add{
        type = "frame",
        name = "bezierio_window",
        direction = "vertical"
    }
    frame.location = {75, 75}
    player.opened = frame

    lib.add_title_bar(frame)

    frame.add{
        type = "flow",
        name = "main",
        direction = "horizontal"
    }
    lib.add_controls(frame.main)
end

return lib