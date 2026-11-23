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

--- @param player LuaPlayer
--- @param name string
--- @return LuaGuiElement|nil
function lib.find(player, name)
    for _, window_name in ipairs(lib.WINDOWS) do
        local window = player.gui.screen[window_name]
        if window then
            if window.name == name then return window end
            local found = find_in(window, name)
            if found then return found end
        end
    end
    return nil
end

return lib
