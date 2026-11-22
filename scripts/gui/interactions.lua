local debug = require("scripts.debug")

local lib = {}

lib["main"]     = require("scripts.gui.layout")
lib["control"]  = require("scripts.gui.control")
lib["curve"]    = require("scripts.gui.curve_control")
lib["layer"]    = require("scripts.gui.layer_control")

function lib.handle_event (e)
    local player = game.get_player(e.player_index)
    if not player then return end

    local element = e.element
    if element.get_mod() ~= "Bezierio" then return end

    local group_tag = element.tags.group
    if not group_tag then
        debug.print("No group tag defined: "..element.name)
        return
    end

    local group = lib[group_tag]
    if not group then
        debug.print("No group declared: "..group_tag)
        return
    end

    local action_tag = element.tags.action
    if not action_tag then
        debug.print("No action tag defined: "..element.name)
        return
    end

    local action = group[action_tag]
    if not action then
        debug.print("No action declared: "..group_tag.."."..action_tag)
        return
    end

    action(e)
end

script.on_event(
defines.events.on_gui_click,
--- @param e EventData.on_gui_click
function (e)
    local type = e.element.type
    if type == "button" or type == "sprite-button" then
        lib.handle_event(e)
    else
        debug.print("Unhandled click event: "..e.element.name)
    end
end
)


script.on_event(
    defines.events.on_gui_elem_changed,
function (e)
    local type = e.element.type
    if type == "choose-elem-button" then
        lib.handle_event(e)
    else
        debug.print("Unhandled elem changed event: "..e.element.name)
    end
end
)

script.on_event(
    defines.events.on_gui_confirmed,
    function (e)
        local type = e.element.type
        if type == "textfield" then
            lib.handle_event(e)
        else
            debug.print("Unhandled confirmed event: "..e.element.name)
        end
    end
)

script.on_event(defines.events.on_gui_closed,
--- @param e EventData.on_gui_closed
function (e)
    if e.element and e.element.name == "bezierio_window" then
        lib["main"]["close"](e)
    end
end)

return lib