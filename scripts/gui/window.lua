--- Finding things in the main window. Element names are unique within the window,
--- so code (and tests) can find elements by name regardless of layout.
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

--- @param player LuaPlayer
--- @param name string
--- @return LuaGuiElement|nil
function lib.find(player, name)
    local window = lib.get(player)
    if not window then return nil end
    return find_in(window, name)
end

return lib
