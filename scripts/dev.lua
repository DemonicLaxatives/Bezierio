---@diagnostic disable: missing-fields
--- Test hooks. Only registered when the `bezierio-test` mod is active, so normal
--- games never expose them.
---
--- Scripts cannot click GUI elements or fire custom inputs, so the test scenarios
--- call these instead. They imitate what the engine does before raising the event
--- (e.g. flipping an auto_toggle button) and then run the real handler.
if not script.active_mods["bezierio-test"] then return end

local interactions = require("scripts.gui.interactions")
local window = require("scripts.gui.window")
local custom_input = require("scripts.custom_input")
local state = require("scripts.state")
local planner = require("scripts.build.planner")
local jobs = require("scripts.jobs")
local layer_view = require("scripts.gui.layer_view")
local presets = require("scripts.presets")
local rails = require("scripts.build.rails")

-- (the scenarios count presets: test players start with "Default" only)
state.with_builtin_presets = false

--- @param player_index integer
--- @param path string[]|LuaGuiElement  # element names, starting from player.gui
--- @return LuaGuiElement
local function find(player_index, path)
    if type(path) == "string" then -- an element name in the main window
        local player = game.get_player(player_index) --[[@as LuaPlayer]]
        local element = window.find(player, path)
        if not element and not state.ui(player_index).editing and window.get(player) then
            -- (a layer setting, after the hooks pressed OK: open the selected layer's
            -- settings again, as the player would)
            layer_view.open_settings(player, state.ui(player_index).selected_layer)
            element = window.find(player, path)
            if not element then layer_view.accept(player) end
        end
        if not element then error("No GUI element named " .. path) end
        return element
    end
    if type(path) ~= "table" then return path end -- already an element
    local element = game.get_player(player_index).gui
    for _, name in ipairs(path) do
        element = element[name]
        if not element then error("No GUI element at " .. table.concat(path, "/")) end
    end
    return element --[[@as LuaGuiElement]]
end

--- The main window is locked while a layer's settings are open (its events are
--- ignored). A player would press OK first; so do the test hooks, unless `raw`.
--- @param player_index integer
--- @param element LuaGuiElement
local function as_player(player_index, element)
    local root = element
    while root.parent and root.parent.parent do root = root.parent end
    local player = game.get_player(player_index)
    if player and root.name == "bezierio_window" and state.ui(player_index).editing then
        layer_view.accept(player)
    end
    return element
end

local function event(name, player_index, element, extra)
    local e = { name = defines.events[name], player_index = player_index, element = element, tick = game.tick }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

remote.add_interface("bezierio-dev", {
    --- A click exactly as the player makes it, locks included.
    click_raw = function(player_index, path)
        local element = find(player_index, path)
        if not element.enabled then return end -- (the engine doesn't let the player use it)
        if element.auto_toggle then element.toggled = not element.toggled end
        interactions.handle_event(event("on_gui_click", player_index, element, {
            button = defines.mouse_button_type.left, alt = false, control = false, shift = false,
        }))
    end,
    click = function(player_index, path, button)
        local element = as_player(player_index, find(player_index, path))
        if element.type == "button" or element.type == "sprite-button" then
            if element.auto_toggle then element.toggled = not element.toggled end
        end
        interactions.handle_event(event("on_gui_click", player_index, element, {
            button = button or defines.mouse_button_type.left, alt = false, control = false, shift = false,
        }))
    end,
    set_value = function(player_index, path, value)
        local element = as_player(player_index, find(player_index, path))
        element.slider_value = value
        interactions.handle_event(event("on_gui_value_changed", player_index, element))
    end,
    set_text = function(player_index, path, text)
        local element = as_player(player_index, find(player_index, path))
        element.text = text
        interactions.handle_event(event("on_gui_confirmed", player_index, element, { text = text }))
    end,
    set_elem = function(player_index, path, value)
        local element = as_player(player_index, find(player_index, path))
        element.elem_value = value
        interactions.handle_event(event("on_gui_elem_changed", player_index, element))
    end,
    set_checked = function(player_index, path, checked)
        local element = as_player(player_index, find(player_index, path))
        element.state = checked
        interactions.handle_event(event("on_gui_checked_state_changed", player_index, element))
    end,
    --- A drop-down choice as the player makes it, locks included (nothing on a
    --- disabled one).
    --- The tiles a rail piece needs under it on water (build/rails.lua).
    rail_cover = function(name, direction)
        return rails.cover_cells(name, direction)
    end,
    --- Add the built-in presets to this player's, as a new player gets them.
    add_builtin_presets = function(player_index)
        local list = state.get(player_index).presets
        for _, preset in ipairs(presets.builtin()) do
            preset.name = presets.unique_name(list, preset.name)
            list[#list + 1] = preset
        end
        local player = game.get_player(player_index)
        if player then interactions["preset"].refresh(player) end
    end,
    select_raw = function(player_index, path, index)
        local element = find(player_index, path)
        if not element.enabled then return end -- (the engine doesn't let the player use it)
        element.selected_index = index
        interactions.handle_event(event("on_gui_selection_state_changed", player_index, element))
    end,
    select = function(player_index, path, index)
        local element = as_player(player_index, find(player_index, path))
        element.selected_index = index
        interactions.handle_event(event("on_gui_selection_state_changed", player_index, element))
    end,
    --- over: nil = world click; a path/element = click on that element;
    --- true = over a GUI without an element reported (as for slider clicks)
    pointer = function(player_index, position, over)
        local element = (over and over ~= true) and find(player_index, over) or nil
        custom_input.on_pointer({
            player_index = player_index, cursor_position = position,
            input_name = "bezierio-pointer", in_gui = over ~= nil, element = element,
        })
    end,
    pointer_insert = function(player_index, position)
        custom_input.on_pointer_insert({
            player_index = player_index, cursor_position = position,
            input_name = "bezierio-pointer-insert", in_gui = false,
        })
    end,
    pointer_remove = function(player_index, position)
        custom_input.on_pointer_remove({
            player_index = player_index, cursor_position = position,
            input_name = "bezierio-pointer-remove", in_gui = false,
        })
    end,
    --- step: 1 = next point (alt + wheel down), -1 = previous
    select_step = function(player_index, step)
        local e = { player_index = player_index, in_gui = false }
        if step > 0 then custom_input.on_select_next(e) else custom_input.on_select_previous(e) end
    end,
    controller = function(player_index)
        return state.get(player_index)
    end,
    --- The plan for the current curve and layers, computed in one go.
    plan = function(player_index)
        return planner.plan(state.curve(player_index), state.layers(player_index))
    end,
    --- True when this player's planning, drawing and building have caught up.
    idle = function(player_index)
        return jobs.is_idle(player_index, state.get(player_index))
    end,
    item_filter = function()
        return state.item_filter()
    end,
    --- Replace Bézierio's storage (migration test fixture).
    set_storage = function(data)
        for key in pairs(storage) do storage[key] = nil end
        for key, value in pairs(data) do storage[key] = value end
    end,
    storage = function()
        return storage
    end,
    schema_version = function()
        return state.SCHEMA_VERSION
    end,
    --- The work budget map setting (the mod's own, so it may change it).
    set_budget = function(value)
        settings.global["bezierio-work-budget"] = { value = value }
    end,
    --- A per-player setting (as the settings window sets it).
    set_setting = function(player_index, name, value)
        state.set_setting(player_index, name, value)
    end,
    render_count = function()
        return #rendering.get_all_objects(script.mod_name)
    end,
})
