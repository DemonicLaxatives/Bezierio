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
        sprite = "item/bezierio-pointer-1",
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
    state.ensure()
    for _, player in pairs(game.players) do
        lib.setup_player(player)
    end
end)

script.on_configuration_changed(function()
    state.ensure()
    state.refresh_prototype_data()
    for _, player in pairs(game.players) do
        lib.setup_player(player)
    end
end)

script.on_event(defines.events.on_player_created,
    --- @param e EventData.on_player_created
    function(e)
        lib.setup_player(game.get_player(e.player_index))
    end)

script.on_event(defines.events.on_player_removed,
    --- @param e EventData.on_player_removed
    function(e)
        state.remove_player(e.player_index)
    end)

return lib
