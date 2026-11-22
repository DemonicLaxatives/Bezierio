local calc = require("scripts.curve_math.control")
local gui = require("scripts.gui.curve_control")
local state = require("scripts.state")

local lib = {}

--- Control point index of the pointer item in the player's cursor, if any.
--- @param player LuaPlayer
--- @return integer|nil
local function cursor_control_point(player)
    local cursor = player.cursor_stack
    if not (cursor and cursor.valid_for_read) then return nil end
    local idx = string.match(cursor.name, "^bezierio%-pointer%-(%d)$")
    return idx and tonumber(idx) or nil
end
lib.cursor_control_point = cursor_control_point

--- @param player LuaPlayer
--- @return LuaGuiElement|nil
local function cp_table(player)
    local window = player.gui.screen.bezierio_window
    if not window then return nil end
    return window.main.button_flow.cp_table
end

--- Left click with a pointer in hand: move that control point there.
--- @param e EventData.CustomInputEvent
function lib.on_pointer(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local control_point = cursor_control_point(player)
    if not control_point then return end

    -- A click on a GUI is not meant as a world position. Check both: `element` is
    -- not reported for every part of a widget (e.g. slider clicks), `in_gui` covers those.
    if e.in_gui or e.element then return end

    calc.updateControlPoint(player, control_point, e.cursor_position)
    local flow = cp_table(player)
    if flow then
        gui.updateControlPointTextfields(control_point, state.curve(player.index).raw_control_points[control_point], flow)
    end
end

--- Alt + scroll: cycle through pointers 1..9.
--- @param e EventData.CustomInputEvent
--- @param step integer
function lib.on_pointer_cycle(e, step)
    local player = game.get_player(e.player_index)
    if not player then return end
    local control_point = cursor_control_point(player)
    if not control_point then return end
    local new_pointer = (control_point - 1 + step) % state.MAX_CONTROL_POINTS + 1
    player.cursor_stack.set_stack { name = "bezierio-pointer-" .. new_pointer, count = 1 }
end

--- Keep the GUI's point buttons in sync with the pointer in the cursor.
--- (This event arrives later in the same tick, so sync from the cursor itself
--- rather than from what changed.)
--- @param e EventData.on_player_cursor_stack_changed
function lib.on_cursor_changed(e)
    local player = game.get_player(e.player_index)
    if not player then return end

    local current_cp = cursor_control_point(player)
    state.ui(e.player_index).active_control_point = current_cp

    local flow = cp_table(player)
    if not flow then return end
    for i = 1, state.MAX_CONTROL_POINTS do
        flow["cp_button_" .. i].toggled = (i == current_cp)
    end
end

script.on_event("bezierio-pointer", lib.on_pointer)
script.on_event("bezierio-pointer-up", function(e) lib.on_pointer_cycle(e, 1) end)
script.on_event("bezierio-pointer-down", function(e) lib.on_pointer_cycle(e, -1) end)
script.on_event(defines.events.on_player_cursor_stack_changed, lib.on_cursor_changed)

return lib
