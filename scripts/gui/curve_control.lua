--- The curve panel (group = "curve"): pointer button, curve kind (spline, circle,
--- ellipse, arc), closed-loop toggle, reverse, move, clear, and the list of the
--- active kind's points.
local curve_lib = require("scripts.curve.curve")
local shapes = require("scripts.curve.shapes")
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

--- A point's short name in the list and on the map: P1, P2, ... for a spline;
--- C, R, ... for a shape's handles.
--- @param curve Curve
--- @param i integer
--- @return string|LocalisedString caption, LocalisedString tooltip
function lib.point_name(curve, i)
    local names = shapes.HANDLES[curve.kind]
    if not names then return "P" .. i, { "tooltip.select-point" } end
    local name = names[i] or "?"
    return { "bezierio-handle-short." .. name }, { "", { "bezierio-handle." .. name }, "\n", { "tooltip.select-point" } }
end

--- @param pane LuaGuiElement
--- @param player_index integer
local function fill_points(pane, player_index)
    pane.clear()
    local curve = state.curve(player_index)
    local list = curve_lib.active(curve)
    local selected = state.ui(player_index).selected_point
    local names = shapes.HANDLES[curve.kind]
    if names and #list < #names then
        -- What to click next
        pane.add { type = "label", name = "no_points", caption = { "label.next-handle", { "bezierio-handle." .. names[#list + 1] } } }
    elseif #list == 0 then
        pane.add { type = "label", name = "no_points", caption = { "label.no-points" } }
    end
    if #list == 0 then return end
    local cp_table = pane.add { type = "table", name = "cp_table", column_count = 4 }
    cp_table.style.vertical_align = "center"
    for i, point in ipairs(list) do
        local caption, tooltip = lib.point_name(curve, i)
        local select = cp_table.add {
            type = "button",
            name = "cp_label_" .. i,
            caption = caption,
            tooltip = tooltip,
            tags = { group = "curve", action = "select", idx = i },
            toggled = i == selected,
            style = "tool_button",
        }
        select.style.width = 40
        select.style.height = 24
        select.style.padding = 0
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
    -- What the handles make (the ellipse's width and the arc's end are only
    -- partly used; the drawing shows how).
    local shape = curve_lib.shape(curve)
    if shape then
        local caption
        if curve.kind == "ellipse" then
            caption = { "label.shape-info-ellipse", string.format("%.1f", shape.a), string.format("%.1f", shape.b) }
        elseif curve.kind == "arc" then
            caption = { "label.shape-info-arc", string.format("%.1f", shape.a), string.format("%.0f", math.deg(shape.span)) }
        else
            caption = { "label.shape-info-circle", string.format("%.1f", shape.a) }
        end
        pane.add { type = "label", name = "shape_info", caption = caption }
    end
end

--- @param parent LuaGuiElement
--- @param player LuaPlayer
--- @return LuaGuiElement frame  # header "curve_header", then the point list
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
    local kinds, kind_index = {}, 1
    for i, kind in ipairs(curve_lib.KINDS) do
        kinds[i] = { "bezierio-curve-kind." .. kind }
        if kind == curve.kind then kind_index = i end
    end
    header.add {
        type = "drop-down",
        name = "curve_kind",
        items = kinds,
        selected_index = kind_index,
        tooltip = { "tooltip.curve-kind" },
        tags = { group = "curve", action = "kind" },
    }
    header.add {
        type = "checkbox",
        name = "closed_loop",
        caption = { "checkbox.closed-loop" },
        tooltip = { "tooltip.closed-loop" },
        state = curve.closed,
        visible = curve_lib.is_spline(curve),
        tags = { group = "curve", action = "closed" },
    }
    header.add {
        type = "sprite-button",
        name = "reverse_points",
        tags = { group = "curve", action = "reverse" },
        tooltip = { "tooltip.reverse-points" },
        sprite = "bezierio-reverse",
        toggled = curve_lib.is_reversed(curve),
        style = "tool_button",
    }
    header.add {
        type = "sprite-button",
        name = "move_curve",
        tags = { group = "curve", action = "move_mode" },
        tooltip = { "tooltip.move-curve" },
        sprite = "utility/move_tag",
        auto_toggle = true,
        toggled = state.ui(player.index).pointer_mode == "move",
        style = "tool_button",
    }
    header.add {
        type = "sprite-button",
        name = "control_points_clear",
        tags = { group = "curve", action = "clear" },
        tooltip = { "button.clear-all" },
        sprite = "utility/trash",
        style = "tool_button",
    }
    for _, io in ipairs({ "export", "import" }) do
        header.add {
            type = "sprite-button",
            name = "curve_" .. io,
            tags = { group = "curve", action = "toggle_" .. io },
            tooltip = { "tooltip.curve-" .. io },
            sprite = "utility/" .. io,
            auto_toggle = true,
            style = "tool_button",
        }
    end
    frame.add { type = "flow", name = "curve_io", direction = "vertical", visible = false }

    local pane = frame.add {
        type = "scroll-pane",
        name = "points_pane",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy = "auto-and-reserve-space",
    }
    pane.style.maximal_height = 300
    fill_points(pane, player.index)
    return frame
end

--- Show the export string, the import box, or neither.
--- @param player LuaPlayer
--- @param mode "export"|"import"|nil
local function show_io(player, mode)
    local io = window.find(player, "curve_io")
    if not io then return end
    io.clear()
    io.visible = mode ~= nil
    for _, other in ipairs({ "export", "import" }) do
        local button = window.find(player, "curve_" .. other)
        if button then button.toggled = other == mode end
    end
    if not mode then return end
    io.add { type = "label", caption = { "label.curve-" .. mode } }
    local box = io.add {
        type = "text-box",
        name = mode == "export" and "curve_string" or "curve_import_text",
        text = mode == "export" and helpers.encode_string(helpers.table_to_json(curve_lib.to_data(state.curve(player.index)))) or "",
    }
    box.word_wrap = true
    box.style.width = 300
    box.style.height = 80
    box.focus()
    if mode == "export" then
        box.select_all()
    else
        io.add {
            type = "button", name = "curve_import_confirm", caption = { "button.curve-import" },
            tooltip = { "tooltip.curve-import-confirm" }, tags = { group = "curve", action = "import" },
        }
    end
end

--- @param e EventData.on_gui_click
lib["toggle_export"] = function(e)
    local player = game.get_player(e.player_index)
    if player then show_io(player, e.element.toggled and "export" or nil) end
end

--- @param e EventData.on_gui_click
lib["toggle_import"] = function(e)
    local player = game.get_player(e.player_index)
    if player then show_io(player, e.element.toggled and "import" or nil) end
end

--- Replace the whole curve (every kind's points) with one from an export string.
--- @param player LuaPlayer
--- @param text string
--- @return boolean ok  # (otherwise the player was told why)
function lib.load(player, text)
    text = tostring(text or ""):gsub("%s", "")
    local json = text ~= "" and helpers.decode_string(text)
    local curve, err = curve_lib.from_data(json and helpers.json_to_table(json))
    if not curve then
        player.print({ "bezierio-message.curve-" .. (err or "not-a-curve") })
        return false
    end
    local controller = state.get(player.index)
    controller.curve = curve
    controller.ui.selected_point = nil
    show_io(player, nil)
    local kind = window.find(player, "curve_kind")
    if kind then
        for i, k in ipairs(curve_lib.KINDS) do if k == curve.kind then kind.selected_index = i end end
    end
    local closed = window.find(player, "closed_loop")
    if closed then
        closed.state = curve.closed
        closed.visible = curve_lib.is_spline(curve)
    end
    local reverse = window.find(player, "reverse_points")
    if reverse then reverse.toggled = curve_lib.is_reversed(curve) end
    state.request_point_redraw(player.index)
    lib.points_changed(player)
    return true
end

--- The pasted curve.
--- @param e EventData.on_gui_click
lib["import"] = function(e)
    local player = game.get_player(e.player_index)
    local box = player and window.find(player, "curve_import_text")
    if not (player and box) then return end
    lib.load(player, box.text)
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
    state.ui(e.player_index).selected_point = nil
    lib.points_changed(player)
end

--- Reverse the direction of travel. The points (and the selection) stay as they are.
--- @param e EventData.on_gui_click
lib["reverse"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local curve = state.curve(e.player_index)
    curve_lib.reverse(curve)
    e.element.toggled = curve_lib.is_reversed(curve)
    lib.points_changed(player)
end

--- Switch between the spline and the shapes; each keeps its own points.
--- @param e EventData.on_gui_selection_state_changed
lib["kind"] = function(e)
    local player = game.get_player(e.player_index)
    local kind = curve_lib.KINDS[e.element.selected_index]
    if not (player and kind) then return end
    local curve = state.curve(e.player_index)
    if curve.kind == kind then return end
    curve.kind = kind
    state.ui(e.player_index).selected_point = nil
    local closed = window.find(player, "closed_loop")
    if closed then closed.visible = curve_lib.is_spline(curve) end
    local reverse = window.find(player, "reverse_points")
    if reverse then reverse.toggled = curve_lib.is_reversed(curve) end
    state.request_point_redraw(e.player_index)
    lib.points_changed(player)
end

--- Move mode: the next clicks with the pointer move the curve's centre there.
--- Takes the pointer if the hand is empty.
--- @param e EventData.on_gui_click
lib["move_mode"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    lib.set_move_mode(player, e.element.toggled)
    if e.element.toggled then lib.take_pointer(player) end
end

--- @param player LuaPlayer
--- @param on boolean
function lib.set_move_mode(player, on)
    state.ui(player.index).pointer_mode = on and "move" or nil
    local button = window.find(player, "move_curve")
    if button then button.toggled = on end
    state.request_point_redraw(player.index)
end

--- Put the pointer in the cursor if the hand is empty.
--- @param player LuaPlayer
function lib.take_pointer(player)
    local cursor = player.cursor_stack
    if cursor and not cursor.valid_for_read and player.clear_cursor() then
        cursor.set_stack { name = lib.POINTER, count = 1 }
        lib.sync_pointer_button(player)
    end
end

--- Select a point (nil deselects): the pointer then moves it. Only the point
--- markers are redrawn.
--- @param player LuaPlayer
--- @param idx integer|nil
function lib.select_point(player, idx)
    local ui = state.ui(player.index)
    if idx and not curve_lib.active(state.curve(player.index))[idx] then idx = nil end
    ui.selected_point = idx
    state.request_point_redraw(player.index)
    local pane = window.find(player, "cp_table")
    if not pane then return end
    for _, child in pairs(pane.children) do
        if child.tags.action == "select" then child.toggled = child.tags.idx == idx end
    end
    local button = idx and window.find(player, "cp_label_" .. idx)
    if button then pane.parent.scroll_to_element(button) end
end

--- A point button in the list: select it (and take the pointer if the hand is
--- empty), or deselect it if it is already selected.
--- @param e EventData.on_gui_click
lib["select"] = function(e)
    local player = game.get_player(e.player_index)
    local idx = tonumber(e.element.tags.idx)
    if not player or not idx then return end
    if state.ui(e.player_index).selected_point == idx then
        lib.select_point(player, nil)
        return
    end
    lib.select_point(player, idx)
    lib.take_pointer(player)
end

--- @param e EventData.on_gui_click
lib["delete"] = function(e)
    local player = game.get_player(e.player_index)
    local idx = tonumber(e.element.tags.idx)
    if not player or not idx then return end
    lib.remove_point(player, idx)
end

--- Remove a point, keeping the selected point selected.
--- @param player LuaPlayer
--- @param idx integer
function lib.remove_point(player, idx)
    local ui = state.ui(player.index)
    curve_lib.remove(state.curve(player.index), idx)
    if ui.selected_point == idx then
        ui.selected_point = nil
    elseif ui.selected_point and ui.selected_point > idx then
        ui.selected_point = ui.selected_point - 1
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
    local list = curve_lib.active(curve)
    local old = list[idx]
    if not old then return end
    local value = tonumber(element.text)
    if not value then
        element.text = tostring(old[axis])
        return
    end
    local point = { x = old.x, y = old.y }
    point[axis] = value
    curve_lib.set_point(curve, idx, point)
    element.text = tostring(list[idx][axis])
    -- A shape's centre moves the other handles too.
    if idx == 1 and not curve_lib.is_spline(curve) then
        lib.points_changed(player)
    else
        state.changed(e.player_index)
    end
end

return lib
