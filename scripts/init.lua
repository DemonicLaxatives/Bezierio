--- Lifecycle: storage setup, migrations, per-player setup.
local mod_gui = require("mod-gui")
local state = require("scripts.state")

local lib = {}

--- @param player LuaPlayer|nil
function lib.create_button(player)
    if not player then return end
    local button_flow = mod_gui.get_button_flow(player)
    if button_flow.bezierio_button then return end
    button_flow.add {
        type = "sprite-button",
        name = "bezierio_button",
        tags = { group = "main", action = "toggle" },
        sprite = "item/bezierio-pointer",
        tooltip = { "tooltip.bezierio-open-gui" },
        style = mod_gui.button_style,
    }
end

--- @param player LuaPlayer|nil
function lib.setup_player(player)
    if not player then return end
    state.get(player.index)
    lib.create_button(player)
end

script.on_init(function()
    state.init()
    for _, player in pairs(game.players) do
        lib.setup_player(player)
    end
end)

-- Runs after the game applied any migrations/ files to this save.
script.on_configuration_changed(function()
    state.on_configuration_changed()
    for _, player in pairs(game.players) do
        lib.setup_player(player)
    end
end)

script.on_event(defines.events.on_player_created,
    --- @param e EventData.on_player_created
    function(e)
        lib.setup_player(game.get_player(e.player_index))
    end)

--- Drawings belong to a surface: redraw on the player's new one. A running build
--- continues on the surface it started on.
script.on_event(defines.events.on_player_changed_surface,
    --- @param e EventData.on_player_changed_surface
    function(e)
        state.request_redraw(e.player_index)
    end)

script.on_event(defines.events.on_player_removed,
    --- @param e EventData.on_player_removed
    function(e)
        state.remove_player(e.player_index)
    end)

return lib
