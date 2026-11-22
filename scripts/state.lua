--- Single source of truth for the shape of `storage`.
--- Every other module should go through these accessors instead of indexing `storage` directly.
local buildable_types = require("scripts.build.buildable_types")
local build_utils = require("scripts.build.utils")

local lib = {}

--- Bump this whenever the layout of `storage` changes incompatibly.
--- Old data is then discarded (see `lib.ensure`).
lib.SCHEMA_VERSION = 2

--- @class InterfaceState
--- @field draw_curve boolean
--- @field preview_build boolean
--- @field active_control_point integer|nil
--- @field preset_indx integer
--- @field dirty boolean                       # something changed that needs a redraw

--- @class BezierCurve
--- @field raw_control_points table<integer, Vector|nil>  # sparse, keys 1..9
--- @field p0 Vector|nil                                   # first defined control point
--- @field control_points Vector[]                         # defined points, relative to p0, in order
--- @field degree integer                                  # #control_points - 1, -1 if none
--- @field parameters_changed boolean
--- @field resolution number

--- @class Preset
--- @field name string
--- @field layers table<integer, Buildable>   # layer index (… -1, 0, 1 …) -> buildable

--- @class BezierioController
--- @field state InterfaceState
--- @field curve_cache table<integer, BezierCurve>  # only [0] is used for now
--- @field presets table<integer, Preset>

--- @class SpriteCache
--- @field curve LuaRenderObject[]
--- @field control_points LuaRenderObject[]
--- @field preview LuaRenderObject[]

lib.MAX_CONTROL_POINTS = 9

--- @return BezierCurve
function lib.new_curve()
    return {
        raw_control_points = {},
        p0 = nil,
        control_points = {},
        degree = -1,
        parameters_changed = true,
        resolution = 0.5,
    }
end

--- @return BezierioController
function lib.new_controller()
    return {
        state = {
            preset_indx = 1,
            draw_curve = false,
            preview_build = false,
            active_control_point = nil,
            dirty = true,
        },
        curve_cache = { [0] = lib.new_curve() },
        presets = {
            { name = "Default", layers = { [0] = buildable_types.contructNilBuildable(0) } },
        },
    }
end

--- Make sure `storage` has the current layout. Safe to call from any event (not from on_load).
function lib.ensure()
    if storage.schema_version == lib.SCHEMA_VERSION then return end

    -- Unknown/old layout: throw it away. Nothing in it is worth migrating yet.
    rendering.clear(script.mod_name)
    for _, player in pairs(game.players) do
        if player.gui.screen.bezierio_window then
            player.gui.screen.bezierio_window.destroy()
        end
    end

    storage.controllers = {}
    storage.sprites = {}
    storage.item_filter = build_utils.build_item_filter()
    storage.schema_version = lib.SCHEMA_VERSION
end

--- @param player_index integer
--- @return BezierioController
function lib.get(player_index)
    lib.ensure()
    local controller = storage.controllers[player_index]
    if not controller then
        controller = lib.new_controller()
        storage.controllers[player_index] = controller
    end
    return controller
end

--- @param player_index integer
--- @return InterfaceState
function lib.ui(player_index)
    return lib.get(player_index).state
end

--- @param player_index integer
--- @return BezierCurve
function lib.curve(player_index)
    return lib.get(player_index).curve_cache[0]
end

--- @param player_index integer
--- @return table<integer, Buildable>
function lib.layers(player_index)
    local controller = lib.get(player_index)
    return controller.presets[controller.state.preset_indx].layers
end

--- @param player_index integer
--- @return SpriteCache
function lib.sprites(player_index)
    lib.ensure()
    local sprites = storage.sprites[player_index]
    if not sprites then
        sprites = { curve = {}, control_points = {}, preview = {} }
        storage.sprites[player_index] = sprites
    end
    return sprites
end

--- Request a redraw of curve / preview on the next render tick.
--- @param player_index integer
function lib.mark_dirty(player_index)
    lib.ui(player_index).dirty = true
end

--- @return ItemPrototypeFilter[]
function lib.item_filter()
    lib.ensure()
    return storage.item_filter
end

--- Rebuild data that depends on prototypes (call from on_configuration_changed).
function lib.refresh_prototype_data()
    lib.ensure()
    storage.item_filter = build_utils.build_item_filter()
end

--- @param player_index integer
function lib.remove_player(player_index)
    lib.ensure()
    local sprites = storage.sprites[player_index]
    if sprites then
        for _, cache in pairs(sprites) do
            for _, obj in pairs(cache) do
                if obj.valid then obj.destroy() end
            end
        end
    end
    storage.sprites[player_index] = nil
    storage.controllers[player_index] = nil
end

return lib
