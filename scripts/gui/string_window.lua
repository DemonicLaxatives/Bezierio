--- The import / export window (group = "strings"): a curve or preset string to
--- copy, or a box to paste one into. One at a time: opening another replaces it.
--- It becomes the opened GUI, so Esc closes it; the main window stays usable.
---
--- Element names: curve_string / preset_string (export), curve_import_text /
--- preset_import_text and curve_import_confirm / preset_import_confirm (import, run
--- by the curve and preset groups).
local curve_lib = require("scripts.curve.curve")
local presets = require("scripts.presets")
local state = require("scripts.state")
local window = require("scripts.gui.window")

local lib = {}

lib.NAME = "bezierio_string_window"

--- @alias StringKind "curve"|"preset"
--- @alias StringMode "export"|"import"

--- @param player LuaPlayer
--- @return LuaGuiElement|nil
function lib.get(player)
    return player.gui.screen[lib.NAME]
end

--- Show which one is open on the toolbar buttons (curve_export, preset_import, ...).
--- @param player LuaPlayer
local function sync_buttons(player)
    local frame = lib.get(player)
    local open = frame and frame.tags.kind .. "_" .. frame.tags.mode
    for _, name in ipairs({ "curve_export", "curve_import", "preset_export", "preset_import" }) do
        local button = window.find(player, name)
        if button then button.toggled = name == open end
    end
end

--- @param player LuaPlayer
--- @param kind StringKind
--- @return string
local function export_string(player, kind)
    local controller = state.get(player.index)
    if kind == "curve" then
        return helpers.encode_string(helpers.table_to_json(curve_lib.to_data(controller.curve))) --[[@as string]]
    end
    return presets.export(controller.presets[controller.ui.preset_index])
end

--- @param player LuaPlayer
function lib.close_window(player)
    local frame = lib.get(player)
    if not frame then return end
    frame.destroy()
    sync_buttons(player)
    local ui = state.ui(player.index)
    local main = window.get(player)
    if main and not ui.pinned and not ui.editing then player.opened = main end
end

--- @param player LuaPlayer
--- @param kind StringKind
--- @param mode StringMode
function lib.open(player, kind, mode)
    if lib.get(player) then lib.get(player).destroy() end
    local frame = player.gui.screen.add {
        type = "frame", name = lib.NAME, direction = "vertical", tags = { kind = kind, mode = mode },
    }
    local title_bar = frame.add { type = "flow", direction = "horizontal" }
    title_bar.style.horizontal_spacing = 6
    title_bar.add { type = "label", style = "frame_title", caption = { "titles." .. kind .. "-" .. mode }, ignored_by_interaction = true }
    local dragger = title_bar.add { type = "empty-widget", style = "draggable_space_header" }
    dragger.style.horizontally_stretchable = true
    dragger.style.height = 24
    dragger.style.minimal_width = 16
    dragger.drag_target = frame
    title_bar.add {
        type = "sprite-button",
        name = "string_close_button",
        style = "frame_action_button",
        sprite = "utility/close",
        tooltip = { "tooltip.close-window" },
        tags = { group = "strings", action = "close" },
        mouse_button_filter = { "left" },
    }

    local content = frame.add { type = "frame", direction = "vertical", style = "inside_shallow_frame_with_padding" }
    content.add { type = "label", caption = { "label." .. kind .. "-" .. mode } }
    local box = content.add {
        type = "text-box",
        name = kind .. (mode == "export" and "_string" or "_import_text"),
        text = mode == "export" and export_string(player, kind) or "",
    }
    box.word_wrap = true
    box.style.width = 420
    box.style.height = 160
    box.style.top_margin = 4

    local buttons = frame.add { type = "flow", direction = "horizontal", style = "dialog_buttons_horizontal_flow" }
    buttons.add {
        type = "button",
        name = "string_cancel",
        caption = { mode == "export" and "button.string-close" or "button.layer-cancel" },
        style = "back_button",
        tags = { group = "strings", action = "close" },
    }
    local filler = buttons.add { type = "empty-widget", style = "draggable_space" }
    filler.style.horizontally_stretchable = true
    filler.style.height = 32
    filler.drag_target = frame
    if mode == "import" then
        buttons.add {
            type = "button",
            name = kind .. "_import_confirm",
            caption = { "button." .. kind .. "-import" },
            tooltip = kind == "curve" and { "tooltip.curve-import-confirm" } or nil,
            style = "confirm_button",
            tags = { group = kind, action = "import" },
        }
    end

    frame.force_auto_center()
    player.opened = frame
    box.focus()
    if mode == "export" then box.select_all() end
    sync_buttons(player)
end

--- Open it, or close it if this one is already open (the toolbar button again).
--- @param player LuaPlayer
--- @param kind StringKind
--- @param mode StringMode
function lib.toggle(player, kind, mode)
    local frame = lib.get(player)
    if frame and frame.tags.kind == kind and frame.tags.mode == mode then
        lib.close_window(player)
    else
        lib.open(player, kind, mode)
    end
end

--- The close button, or Cancel.
--- @param e EventData.on_gui_click
lib["close"] = function(e)
    local player = game.get_player(e.player_index)
    if player then lib.close_window(player) end
end

return lib
