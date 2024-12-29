local util = require('__core__/lualib/util')
local calc = require('scripts.calc')
local draw = require('scripts.draw')
local build = require('scripts.builder')
local mod_gui = require("mod-gui")

--- @class QualityItem
--- @field name string
--- @field quality string

--- @class CurveParameters
--- @field raw_control_points table<integer, Vector|nil>
--- @field p0 Vector|nil
--- @field control_points table<integer, Vector>|nil
--- @field degree integer
--- @field parameters_changed boolean

--- @class InterfaceState
--- @field draw_curve boolean
--- @field buildable QualityItem|nil
--- @field build_thickness integer
--- @field build_spacing integer
--- @field active_control_point integer|nil

--- @class BezierioController
--- @field state InterfaceState
--- @field curve_params CurveParameters

--- @class SpriteCache
--- @field curve LuaRenderObject[]
--- @field control_points LuaRenderObject[]

local function initilize_global(player)
    if not player then return end 
    if not storage.controllers[player.index] then

        --- @type InterfaceState
        local InterfaceState = {
            draw_curve = false,
            buildable = nil,
            build_thickness = 1,
            build_spacing = 1,
            active_control_point = nil,
            parameters_changed = false,
        }

        --- @type CurveParameters
        local CurveParameters = {
            raw_control_points = {},
            p0 = nil,
            control_points = {},
            degree = -1,
            parameters_changed = false,
        }
    
        --- @type BezierioController
        local controller = {
            state = InterfaceState,
            curve_params = CurveParameters,
        }

        storage.controllers[player.index] = controller
    end 
    if not storage.sprites[player.index] then
        storage.sprites[player.index] = {
            curve = {},
            control_points = {},
        }
    end
end

local function create_button(player)
    if not player then return end
    local button_flow = mod_gui.get_button_flow(player)
    if not button_flow.railbow_button then
        button_flow.add{
            type = "sprite-button",
            name = "bezierio_button",
            sprite = "utility/check_mark",
            tooltip = {"tooltips.bezierio-open-gui"},
            style=mod_gui.button_style
        }
    end
end

--- @class EntityFilter
--- @field filter string
--- @field name string[]

script.on_init(function()
    --- @type table<integer, BezierioController>
    storage.controllers = {}
    --- @type table<integer, SpriteCache>
    storage.sprites = {}

    for _, player in pairs(game.players) do
        initilize_global(player)
        create_button(player)
    end

    --- @type EntityFilter
    storage.item_filter = {filter = "name", name = {}}
end)

script.on_event(defines.events.on_player_created,
function(e)
    local player = game.get_player(e.player_index)
    initilize_global(player)
    create_button(player)
end)

script.on_event(defines.events.on_player_removed,
function(e)
    storage.controllers[e.player_index] = nil
end)