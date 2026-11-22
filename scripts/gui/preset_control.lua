--- The preset bar above the layer list (group = "preset"): switch, rename, copy,
--- delete, export and import layer stacks.
local presets = require("scripts.presets")
local state = require("scripts.state")
local window = require("scripts.gui.window")
local layer_view = require("scripts.gui.layer_view")

local lib = {}

--- @param name string
--- @param sprite string
--- @param tooltip string
--- @param action string
--- @param extra table|nil
local function tool_button(parent, name, sprite, tooltip, action, extra)
    local params = {
        type = "sprite-button",
        name = name,
        sprite = sprite,
        tooltip = { "tooltip." .. tooltip },
        tags = { group = "preset", action = action },
        style = "tool_button",
    }
    for k, v in pairs(extra or {}) do params[k] = v end
    return parent.add(params)
end

--- @param frame LuaGuiElement
--- @param player LuaPlayer
local function fill(frame, player)
    frame.clear()
    local controller = state.get(player.index)
    local ui = controller.ui
    local mode = ui.preset_mode

    local bar = frame.add { type = "flow", name = "preset_bar", direction = "horizontal" }
    bar.style.vertical_align = "center"
    if mode == "rename" then
        local field = bar.add {
            type = "textfield",
            name = "preset_name",
            text = controller.presets[ui.preset_index].name,
            tags = { group = "preset", action = "rename" },
            tooltip = { "tooltip.preset-name" },
        }
        field.style.width = 160
        field.focus()
        field.select_all()
    else
        local names = {}
        for i, preset in ipairs(controller.presets) do names[i] = preset.name end
        local select = bar.add {
            type = "drop-down",
            name = "preset_select",
            items = names,
            selected_index = ui.preset_index,
            tags = { group = "preset", action = "switch" },
            tooltip = { "tooltip.preset-select" },
        }
        select.style.width = 160
    end
    tool_button(bar, "preset_rename", "utility/rename_icon", "preset-rename", "toggle_rename",
        { auto_toggle = true, toggled = mode == "rename" })
    tool_button(bar, "preset_copy", "utility/copy", "preset-copy", "copy")
    tool_button(bar, "preset_delete", "utility/trash", #controller.presets > 1 and "preset-delete" or "preset-delete-last",
        "delete", { enabled = #controller.presets > 1 })
    tool_button(bar, "preset_export", "utility/export", "preset-export", "toggle_export",
        { auto_toggle = true, toggled = mode == "export" })
    tool_button(bar, "preset_import", "utility/import", "preset-import", "toggle_import",
        { auto_toggle = true, toggled = mode == "import" })

    if mode == "export" or mode == "import" then
        frame.add { type = "label", caption = { "label.preset-" .. mode } }
        local box = frame.add {
            type = "text-box",
            name = mode == "export" and "preset_string" or "preset_import_text",
            text = mode == "export" and presets.export(controller.presets[ui.preset_index]) or "",
        }
        box.word_wrap = true
        box.style.width = 300
        box.style.height = 80
        box.focus()
        if mode == "export" then
            box.select_all()
        else
            frame.add {
                type = "button",
                name = "preset_import_confirm",
                caption = { "button.preset-import" },
                tags = { group = "preset", action = "import" },
            }
        end
    end
end

--- @param parent LuaGuiElement
--- @param player LuaPlayer
function lib.add(parent, player)
    local frame = parent.add { type = "frame", name = "preset_frame", direction = "vertical", style = "inside_shallow_frame_with_padding" }
    fill(frame, player)
end

--- @param player LuaPlayer
function lib.refresh(player)
    local frame = window.find(player, "preset_frame")
    if frame then fill(frame, player) end
end

--- Another preset is selected (or the list changed): plan again, show its layers.
--- @param player LuaPlayer
local function preset_changed(player)
    local ui = state.ui(player.index)
    ui.selected_layer = 0
    ui.preset_mode = nil
    state.changed(player.index)
    lib.refresh(player)
    layer_view.refresh(player)
end

--- @param e EventData.on_gui_selection_state_changed
lib["switch"] = function(e)
    local player = game.get_player(e.player_index)
    if player and presets.select(state.get(e.player_index), e.element.selected_index) then
        preset_changed(player)
    end
end

--- @param player LuaPlayer
--- @param mode "rename"|"export"|"import"
local function toggle_mode(player, mode)
    local ui = state.ui(player.index)
    ui.preset_mode = ui.preset_mode ~= mode and mode or nil
    lib.refresh(player)
end

--- @param e EventData.on_gui_click
lib["toggle_rename"] = function(e)
    local player = game.get_player(e.player_index)
    if player then toggle_mode(player, "rename") end
end

--- @param e EventData.on_gui_click
lib["toggle_export"] = function(e)
    local player = game.get_player(e.player_index)
    if player then toggle_mode(player, "export") end
end

--- @param e EventData.on_gui_click
lib["toggle_import"] = function(e)
    local player = game.get_player(e.player_index)
    if player then toggle_mode(player, "import") end
end

--- @param e EventData.on_gui_confirmed
lib["rename"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    presets.rename(state.get(e.player_index), e.element.text)
    state.ui(e.player_index).preset_mode = nil
    lib.refresh(player)
end

--- @param e EventData.on_gui_click
lib["copy"] = function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    if presets.duplicate(state.get(e.player_index)) then
        preset_changed(player)
    else
        player.print({ "bezierio-message.preset-too-many" })
    end
end

--- @param e EventData.on_gui_click
lib["delete"] = function(e)
    local player = game.get_player(e.player_index)
    if player and presets.delete(state.get(e.player_index)) then preset_changed(player) end
end

--- @param e EventData.on_gui_click
lib["import"] = function(e)
    local player = game.get_player(e.player_index)
    local box = player and window.find(player, "preset_import_text")
    if not (player and box) then return end
    local ok, result = presets.import(state.get(e.player_index), box.text)
    if not ok then
        player.print({ "bezierio-message.preset-" .. result })
        return
    end
    if #result > 0 then
        player.print({ "bezierio-message.preset-missing-items", table.concat(result, ", ") })
    end
    preset_changed(player)
end

return lib
