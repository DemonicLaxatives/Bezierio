--- Routes GUI events to handlers by element tags: lib[tags.group][tags.action](event).
local debug    = require("scripts.debug")

local lib      = {}

lib["main"]    = require("scripts.gui.layout")
lib["control"] = require("scripts.gui.control")
lib["curve"]   = require("scripts.gui.curve_control")
lib["layer"]   = require("scripts.gui.layer_control")
lib["view"]    = require("scripts.gui.view_settings")
lib["preset"]  = require("scripts.gui.preset_control")

--- Which element types each event is routed for. Every element raises on_gui_click,
--- but e.g. a click on a choose-elem-button must not run its "value changed" action
--- (that rebuilt the row and destroyed the picker before it could open).
lib.routed_types = {
    [defines.events.on_gui_click] = {["button"] = true, ["sprite-button"] = true, ["label"] = true},
    [defines.events.on_gui_elem_changed] = {["choose-elem-button"] = true},
    [defines.events.on_gui_confirmed] = {["textfield"] = true},
    [defines.events.on_gui_value_changed] = {["slider"] = true},
    [defines.events.on_gui_checked_state_changed] = {["checkbox"] = true},
    [defines.events.on_gui_selection_state_changed] = {["drop-down"] = true},
}

--- @param e {name: defines.events, element: LuaGuiElement, player_index: integer}
function lib.handle_event(e)
    local element = e.element
    if not (element and element.valid) then return end
    if element.get_mod() ~= script.mod_name then return end
    local routed = lib.routed_types[e.name]
    if not (routed and routed[element.type]) then return end

    local group_tag = element.tags.group
    if not group_tag then return end -- passive element (labels, frames, ...)

    local group = lib[group_tag]
    if not group then
        debug.print("No group declared: " .. tostring(group_tag))
        return
    end

    local action_tag = element.tags.action
    local action = action_tag and group[action_tag]
    if not action then
        debug.print("No action declared: " .. tostring(group_tag) .. "." .. tostring(action_tag))
        return
    end

    action(e)
end

script.on_event(defines.events.on_gui_click, lib.handle_event)
script.on_event(defines.events.on_gui_elem_changed, lib.handle_event)
script.on_event(defines.events.on_gui_confirmed, lib.handle_event)
script.on_event(defines.events.on_gui_value_changed, lib.handle_event)
script.on_event(defines.events.on_gui_checked_state_changed, lib.handle_event)
script.on_event(defines.events.on_gui_selection_state_changed, lib.handle_event)

script.on_event(defines.events.on_gui_closed,
    --- @param e EventData.on_gui_closed
    function(e)
        if e.element and e.element.valid and e.element.name == "bezierio_window" then
            lib["main"]["close"](e)
        end
    end)

return lib
