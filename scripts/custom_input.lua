--- The curve pointer in the world.
---
--- Left click: on empty ground add a point at the end; on a point pick it up;
--- with a point held, drop it there. Right click: on a point remove it; with a
--- point held, put it back where it was.
local curve_lib = require("scripts.curve.curve")
local curve_control = require("scripts.gui.curve_control")
local state = require("scripts.state")

local lib = {}

--- How close (in tiles) a click must be to a point to pick it up or remove it.
lib.PICK_RADIUS = 1

--- Clicks on any GUI are not meant as world positions. Check both: `element` is
--- not reported for every part of a widget (e.g. slider clicks), `in_gui` is.
--- @param e EventData.CustomInputEvent
local function on_gui(e)
    return e.in_gui or e.element ~= nil
end

--- @param e EventData.CustomInputEvent
function lib.on_pointer(e)
    local player = game.get_player(e.player_index)
    if not player or on_gui(e) or not curve_control.holds_pointer(player) then return end

    local ui, curve = state.ui(player.index), state.curve(player.index)
    local position = e.cursor_position --[[@as Vector]]
    if ui.held_point and curve.points[ui.held_point] then
        curve_lib.set_point(curve, ui.held_point, position)
        ui.held_point = nil
        curve_control.points_changed(player)
        return
    end
    local near = curve_lib.point_near(curve, position, lib.PICK_RADIUS)
    if near then
        ui.held_point = near
        state.request_redraw(player.index)
        curve_control.refresh_points(player)
    else
        curve_lib.append(curve, position)
        curve_control.points_changed(player)
    end
end

--- @param e EventData.CustomInputEvent
function lib.on_pointer_remove(e)
    local player = game.get_player(e.player_index)
    if not player or on_gui(e) or not curve_control.holds_pointer(player) then return end

    local ui = state.ui(player.index)
    if ui.held_point then
        ui.held_point = nil
        state.request_redraw(player.index)
        curve_control.refresh_points(player)
        return
    end
    local near = curve_lib.point_near(state.curve(player.index), e.cursor_position --[[@as Vector]], lib.PICK_RADIUS)
    if near then curve_control.remove_point(player, near) end
end

--- Keep the pointer button in sync; putting the pointer away drops nothing.
--- @param e EventData.on_player_cursor_stack_changed
function lib.on_cursor_changed(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    curve_control.sync_pointer_button(player)
    local ui = state.ui(player.index)
    if ui.held_point and not curve_control.holds_pointer(player) then
        ui.held_point = nil
        state.request_redraw(player.index)
        curve_control.refresh_points(player)
    end
end

script.on_event("bezierio-pointer", lib.on_pointer)
script.on_event("bezierio-pointer-remove", lib.on_pointer_remove)
script.on_event(defines.events.on_player_cursor_stack_changed, lib.on_cursor_changed)

return lib
