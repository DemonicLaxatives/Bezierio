--- Finding things in Bézierio's windows (the main window, the settings window, the
--- layer settings window, the import / export window). Element names are unique across them, so code (and
--- tests) can find elements by name regardless of layout.
local lib = {}

--- @param player LuaPlayer
--- @return LuaGuiElement|nil
function lib.get(player)
    return player.gui.screen.bezierio_window
end

--- @param element LuaGuiElement
--- @param name string
--- @return LuaGuiElement|nil
local function find_in(element, name)
    for _, child in pairs(element.children) do
        if child.name == name then return child end
        local found = find_in(child, name)
        if found then return found end
    end
    return nil
end
lib.find_in = find_in

--- The windows, searched in this order.
lib.WINDOWS = { "bezierio_window", "bezierio_settings_window", "bezierio_layer_window", "bezierio_string_window" }

--- Elements found before, per player (not saved: names are unique, so a valid
--- element of that name is the one; results never depend on this).
--- @type table<integer, table<string, LuaGuiElement>>
local found_before = {}

--- @param player LuaPlayer
--- @param name string
--- @return LuaGuiElement|nil
function lib.find(player, name)
    local cache = found_before[player.index]
    if not cache then
        cache = {}
        found_before[player.index] = cache
    end
    local hit = cache[name]
    if hit and hit.valid and hit.name == name then return hit end
    cache[name] = nil
    for _, window_name in ipairs(lib.WINDOWS) do
        local window = player.gui.screen[window_name]
        if window then
            local found = window.name == name and window or find_in(window, name)
            if found then
                cache[name] = found
                return found
            end
        end
    end
    return nil
end

--- Element types a player can act on (labels only with an action: the clickable
--- warnings and point chips).
local INTERACTIVE = {
    ["button"] = true, ["sprite-button"] = true, ["drop-down"] = true, ["list-box"] = true,
    ["slider"] = true, ["textfield"] = true, ["text-box"] = true, ["checkbox"] = true,
    ["radiobutton"] = true, ["switch"] = true, ["choose-elem-button"] = true,
}

--- @param element LuaGuiElement
--- @param fn fun(element: LuaGuiElement)
local function walk(element, fn)
    fn(element)
    for _, child in pairs(element.children) do walk(child, fn) end
end

--- While a layer's settings are open, grey out the main window's controls, so
--- nothing there looks usable (interactions.lua ignores its events anyway). The
--- ones greyed out here are remembered (`editing.locked`, by element index), so
--- unlocking leaves those disabled for their own reasons (layer 0's delete)
--- alone. Run again after part of the window was rebuilt meanwhile.
--- @param player LuaPlayer
--- @param ui InterfaceState
function lib.lock_main(player, ui)
    local main = lib.get(player)
    local editing = ui.editing
    if not (main and editing) then return end
    local before, now = editing.locked or {}, {}
    walk(main, function(el)
        local interactive = INTERACTIVE[el.type] or (el.type == "label" and el.tags.action ~= nil)
        if not interactive then return end
        if before[el.index] then
            now[el.index] = true
        elseif el.enabled then
            el.enabled = false
            now[el.index] = true
        end
    end)
    editing.locked = now
end

--- Undo lock_main (the layer settings window closed).
--- @param player LuaPlayer
--- @param locked table<integer, true>|nil
function lib.unlock_main(player, locked)
    local main = lib.get(player)
    if not (main and locked) then return end
    walk(main, function(el)
        if locked[el.index] then el.enabled = true end
    end)
end

--- Set while on_gui_closed runs (interactions.lua).
lib.in_closed_event = false

--- Make the main window the opened GUI again (so Esc closes it), unless it's
--- pinned or another of our windows holds that place. Inside on_gui_closed it
--- waits for the next tick (`ui.reopen_main`, jobs.lua checks it each tick):
--- setting `player.opened` there fights the GUI being opened (a chest clicked
--- while the layer window is open). While another GUI is open it keeps waiting,
--- so the main window gets it back once that one closes.
--- @param player LuaPlayer
--- @param ui InterfaceState
function lib.focus_main(player, ui)
    if lib.in_closed_event then
        ui.reopen_main = true
        return
    end
    ui.reopen_main = nil
    local main = lib.get(player)
    if not main or ui.pinned or ui.editing or player.gui.screen.bezierio_string_window then return end
    if player.opened == nil or player.opened == main then
        player.opened = main
    else
        ui.reopen_main = true
    end
end

return lib
