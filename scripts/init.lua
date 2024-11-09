local util = require('__core__/lualib/util')
local calc = require('scripts.calc')
local draw = require('scripts.draw')
local build = require('scripts.builder')

--- @class InterfaceState
--- @field draw_curve boolean
--- @field buildable string|nil
--- @field build_thickness integer
--- @field build_spacing integer
--- @field control_vector_strengh [number, number]
--- @field control_points ControlPoints
--- @field active_control_point string|nil
--- @field parameters_changed boolean

--- @class BezierioController
--- @field state InterfaceState
--- @field curve BezierCurve|nil

--- @class SpriteCache
--- @field curve integer[]
--- @field p1 integer[]
--- @field p2 integer[]
--- @field v1 integer[]
--- @field v2 integer[]

local function initilize_global(player)
    if not player then return end 
    if not global.controllers[player.index] then
        --- @type ControlPoints
        local control_points = {}

        --- @type InterfaceState
        local InterfaceState = {
            draw_curve = false,
            buildable = nil,
            build_thickness = 1,
            build_spacing = 1,
            control_vector_strengh = {100, 100},
            control_points = control_points,
            active_control_point = nil,
            parameters_changed = false,
        }

        --- @type BezierioController
        local controller = {
            state = InterfaceState,
            curve = nil,
        }

        global.controllers[player.index] = controller
    end 
    if not global.sprites[player.index] then
        global.sprites[player.index] = {
            curve = {},
            p1 = {},
            p2 = {},
            v1 = {},
            v2 = {},
        }
    end
end

local function create_button(player)
    if not player then return end
    if player.gui.top.bezierio_button then return end
    player.gui.top.add{
        type = "frame",
        name = "bezierio_frame",
    }

    player.gui.top.bezierio_frame.add{
        type = "sprite-button",
        name = "bezierio_button",
        sprite = "utility/check_mark",
    }
end

--- @class EntityFilter
--- @field filter string
--- @field name string[]

script.on_init(function()
    --- @type table<integer, BezierioController>
    global.controllers = {}
    --- @type table<integer, SpriteCache>
    global.sprites = {}

    for _, player in pairs(game.players) do
        initilize_global(player)
        create_button(player)
    end
    
    --- @type EntityFilter
    -- global.entity_filter = {filter = "name", name = {}}
    --- @type EntityFilter
    global.item_filter = {filter = "name", name = {}}
end)

script.on_event(defines.events.on_player_created,
function(e)
    local player = game.get_player(e.player_index)
    initilize_global(player)
    create_button(player)
end)

script.on_event(defines.events.on_player_removed,
function(e)
    global.controllers[e.player_index] = nil
end)

script.on_event(defines.events.on_console_chat,
function (e)
    local player = game.get_player(e.player_index)
    if not player then return end
    if not player.gui.screen.bezierio_window then return end
    local state = global.controllers[player.index].state
    if not state.active_control_point then return end
    
    local message = e.message
    local x, y = string.match(message, "%[gps=(%-?%d+%.?%d*),(%-?%d+%.?%d*)%]")
    if (not x) or (not y) then return end
    x = tonumber(x)
    y = tonumber(y)
    local position = {x = x, y = y}

    state.control_points[state.active_control_point] = position
    draw.control_point(player, state.active_control_point)

    state.parameters_changed = true
end)