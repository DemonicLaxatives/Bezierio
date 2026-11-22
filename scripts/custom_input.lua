--- The curve pointer in the world. It edits the active kind's points: the spline's
--- control points, or a shape's handles.
---
--- Left click: on a point, select it; with a point selected, move it there (it
--- stays selected); otherwise add a point at the end (shapes: until they have all
--- their handles). Shift + left click: add a spline point into the nearest stretch
--- of curve (and select it). Right click: with a point selected, deselect it;
--- otherwise remove the point under the cursor. Shift + mouse wheel: select the
--- next / previous point.
---
--- In move mode (the move button), left click moves the curve's centre there and
--- right click leaves move mode.
local curve_lib = require("scripts.curve.curve")
local curve_control = require("scripts.gui.curve_control")
local state = require("scripts.state")

local lib = {}

--- How close (in tiles) a click must be to a point to select or remove it.
lib.PICK_RADIUS = 1

--- Clicks on any GUI are not meant as world positions. Check both: `element` is
--- not reported for every part of a widget (e.g. slider clicks), `in_gui` is.
--- @param e EventData.CustomInputEvent
local function on_gui(e)
    return e.in_gui or e.element ~= nil
end

--- The player, if this input is a world action with the pointer in hand.
--- @param e EventData.CustomInputEvent
--- @return LuaPlayer|nil
local function pointer_player(e)
    local player = game.get_player(e.player_index)
    if not player or on_gui(e) or not curve_control.holds_pointer(player) then return nil end
    return player
end

--- @param e EventData.CustomInputEvent
function lib.on_pointer(e)
    local player = pointer_player(e)
    if not player then return end

    local ui, curve = state.ui(player.index), state.curve(player.index)
    local position = e.cursor_position --[[@as Vector]]
    if ui.pointer_mode == "move" then
        curve_lib.move_to(curve, position)
        state.request_point_redraw(player.index)
        curve_control.points_changed(player)
        return
    end
    local near = curve_lib.point_near(curve, position, lib.PICK_RADIUS)
    if near then
        if near ~= ui.selected_point then curve_control.select_point(player, near) end
    elseif ui.selected_point and curve_lib.active(curve)[ui.selected_point] then
        curve_lib.set_point(curve, ui.selected_point, position)
        curve_control.points_changed(player)
    elseif curve_lib.append(curve, position) then
        curve_control.points_changed(player)
    end
end

--- @param e EventData.CustomInputEvent
function lib.on_pointer_insert(e)
    local player = pointer_player(e)
    if not player then return end

    local curve = state.curve(player.index)
    local position = e.cursor_position --[[@as Vector]]
    if state.ui(player.index).pointer_mode == "move" or not curve_lib.is_spline(curve) then
        lib.on_pointer(e)
        return
    end
    local idx = curve_lib.insert(curve, curve_lib.insertion_index(curve, position), position)
    state.ui(player.index).selected_point = idx
    state.request_redraw(player.index)
    curve_control.points_changed(player)
end

--- @param e EventData.CustomInputEvent
function lib.on_pointer_remove(e)
    local player = pointer_player(e)
    if not player then return end

    local ui = state.ui(player.index)
    if ui.pointer_mode == "move" then
        curve_control.set_move_mode(player, false)
        return
    end
    if ui.selected_point then
        curve_control.select_point(player, nil)
        return
    end
    local near = curve_lib.point_near(state.curve(player.index), e.cursor_position --[[@as Vector]], lib.PICK_RADIUS)
    if near then curve_control.remove_point(player, near) end
end

--- @param e EventData.CustomInputEvent
--- @param step integer  # +1 next, -1 previous
local function cycle(e, step)
    local player = pointer_player(e)
    if not player then return end
    local selected = state.ui(player.index).selected_point
    local count = #curve_lib.active(state.curve(player.index))
    if not selected or count == 0 then return end
    curve_control.select_point(player, (selected - 1 + step) % count + 1)
end

--- @param e EventData.CustomInputEvent
function lib.on_select_next(e) cycle(e, 1) end

--- @param e EventData.CustomInputEvent
function lib.on_select_previous(e) cycle(e, -1) end

--- Keep the pointer button in sync. The selection stays when the pointer is put away.
--- @param e EventData.on_player_cursor_stack_changed
function lib.on_cursor_changed(e)
    local player = game.get_player(e.player_index)
    if player then curve_control.sync_pointer_button(player) end
end

script.on_event("bezierio-pointer", lib.on_pointer)
script.on_event("bezierio-pointer-insert", lib.on_pointer_insert)
script.on_event("bezierio-pointer-remove", lib.on_pointer_remove)
script.on_event("bezierio-select-next", lib.on_select_next)
script.on_event("bezierio-select-previous", lib.on_select_previous)
script.on_event(defines.events.on_player_cursor_stack_changed, lib.on_cursor_changed)

return lib
