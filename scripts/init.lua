local buildable_types = require('scripts.build.buildable_types')

local mod_gui = require("mod-gui")
require("scripts.build.buildable_types")

--- @class InterfaceState
--- @field draw_curve boolean
--- @field preview_build boolean
--- @field active_control_point integer|nil
--- @field preset_indx integer

--- @class BezierCurve
--- @field raw_control_points table<integer, Vector|nil>
--- @field p0 Vector|nil
--- @field control_points table<integer, Vector>|nil
--- @field degree integer
--- @field parameters_changed boolean
--- @field layer_refrence_counter integer
--- @field resolution number
--- @field points Vector[]|nil
--- @field render_cache LuaRenderObject[]|nil
--- @field cp_render_cache LuaRenderObject[]|nil

--- @class BuildState
--- @field ocupancy table<integer, table<integer, table<integer, integer>>>|nil
--- @field build_cache table<integer, LuaEntity>

--- @class Preset
--- @field name string
--- @field layers table<integer, Buildable>

--- @class BezierioController
--- @field state InterfaceState                    # player -> state
--- @field curve_cache table<integer, BezierCurve> # layer -> curve
--- @field presets table<integer, Preset>          # preset_indx -> Preset
--- @field build_cache BuildState                  # layer -> build_cache

local function initilize_global(player)
    if not player then return end 
    if not storage.controllers[player.index] then
        
        --- @class InterfaceState
        local state = {
            preset_indx = 1,
            draw_curve = false,
            preview_build = false,
            active_control_point = nil,
        }

        --- @class BezierCurve
        local curve_0 = {
            raw_control_points = {},
            p0 = nil,
            control_points = {},
            degree = -1,
            parameters_changed = false,
            layer_refrence_counter = 1,
            resolution = 0.5,
        }

        --- @class BuildState
        local build_cache = {
            preset_indx = 1,
            ocupancy = nil,
            build_cache = {}
        }

        --- @class Preset
        local preset = {
            name = "Default",
            layers = {buildable_types.contructNilBuildable(1)}
        }

        --- @class BezierioController
        local controller = {
            state = state,
            curve_cache = {[0] = curve_0},
            presets = {preset},
            build_cache = build_cache
        }

        storage.controllers[player.index] = controller
    end

end

local function create_button(player)
    if not player then return end
    local button_flow = mod_gui.get_button_flow(player)
    if not button_flow.railbow_button then
        button_flow.add{
            type = "sprite-button",
            name = "bezierio_button",
            tags = {group = "main", action = "toggle"},
            sprite = "utility/check_mark",
            tooltip = {"tooltip.bezierio-open-gui"},
            style=mod_gui.button_style
        }
    end
end

--- @class EntityFilter
--- @field filter string
--- @field name string[]

script.on_init(
function()
    --- @type table<integer, BezierioController>
    storage.controllers = {}

    for _, player in pairs(game.players) do
        initilize_global(player)
        create_button(player)
    end

    --- @type EntityFilter
    storage.item_filter = {filter = "name", name = {}}
end)

script.on_event(defines.events.on_player_created,
--- @param e EventData.on_player_created
function(e)
    local player = game.get_player(e.player_index)
    initilize_global(player)
    create_button(player)
end)

script.on_event(defines.events.on_player_removed,
--- @param e EventData.on_player_removed
function(e)
    storage.controllers[e.player_index] = nil
end)