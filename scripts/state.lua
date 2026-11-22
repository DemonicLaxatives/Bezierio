--- Single source of truth for the shape of `storage`.
--- Every other module goes through these accessors instead of indexing `storage`.
---
--- storage.schema_version   integer, see MIGRATIONS
--- storage.controllers[i]   per-player Controller
--- storage.sprites[i]       per-player render objects (SpriteCache)
--- storage.item_filter      filter for the layer item pickers
local registry = require("scripts.layers.registry")
local curve_lib = require("scripts.curve.curve")

local lib = {}

--- @class InterfaceState
--- @field preset_index integer
--- @field draw_curve boolean
--- @field preview_build boolean
--- @field held_point integer|nil       # control point picked up by the pointer, to be dropped
--- @field selected_layer integer        # layer shown in the detail pane

--- @class Preset
--- @field name string
--- @field layers table<integer, Layer>   # layer index (… -1, 0, 1 …) -> layer

--- @class DrawProgress
--- @field curve_cursor integer           # next curve sample to draw
--- @field curve_last Vector|nil          # end of the last drawn curve segment
--- @field curve_finished boolean
--- @field preview_tiles integer          # planned tiles drawn so far
--- @field preview_entities integer
--- @field preview_warnings integer
--- @field preview_count integer

--- @class Work
--- @field revision integer               # controller.revision the jobs belong to
--- @field plan PlannerJob|nil
--- @field draw DrawProgress
--- @field pending_build BezierioBuildMode|nil    # build requested, waiting for the plan
--- @field build BuildJob|nil
--- @field status string|nil              # last status line shown (to update only on change)
--- @field totals_revision integer|nil    # revision whose totals are shown

--- @class Controller
--- @field ui InterfaceState
--- @field curve Curve
--- @field presets Preset[]
--- @field revision integer               # bumped whenever the curve or layers change
--- @field changed_tick integer|nil        # tick of the last change (planning waits a moment)
--- @field redraw boolean                 # view settings changed; redraw from scratch
--- @field work Work

--- @class SpriteCache
--- @field curve LuaRenderObject[]
--- @field control_points LuaRenderObject[]
--- @field preview LuaRenderObject[]
--- @field trash LuaRenderObject[]|nil   # retired, destroyed a few per tick

--- @return DrawProgress
function lib.new_draw_progress()
    return {
        curve_cursor = 1, curve_last = nil, curve_finished = false,
        preview_tiles = 0, preview_entities = 0, preview_warnings = 0, preview_count = 0,
    }
end

--- @return Work
function lib.new_work()
    return { revision = 0, plan = nil, draw = lib.new_draw_progress(), pending_build = nil, build = nil }
end

--- @return Controller
function lib.new_controller()
    return {
        ui = { preset_index = 1, draw_curve = false, preview_build = false, held_point = nil, selected_layer = 0 },
        curve = curve_lib.new(),
        presets = { { name = "Default", layers = { [0] = registry.new_empty(0) } } },
        revision = 1,
        redraw = true,
        work = lib.new_work(),
    }
end

-- Migrations ------------------------------------------------------------------

lib.SCHEMA_VERSION = 4

--- MIGRATIONS[v] upgrades storage from version v to v + 1. Never edit a released
--- migration; add a new one and bump SCHEMA_VERSION.
--- @type table<integer, fun()>
local MIGRATIONS = {
    -- 2 -> 3: groundwork refactor. Curve as {kind, points}; layer type "nil" is now
    -- "empty"; layers no longer store `priority`; UI state renamed; jobs area.
    [2] = function()
        for player_index, old in pairs(storage.controllers or {}) do
            local old_ui = old.state or {}
            local old_curve = (old.curve_cache or {})[0] or {}
            local curve = { points = {} }
            for idx, point in pairs(old_curve.raw_control_points or {}) do
                curve.points[idx] = { x = point.x, y = point.y }
            end
            local presets = {}
            for i, preset in pairs(old.presets or {}) do
                local layers = {}
                for k, layer in pairs(preset.layers or {}) do
                    if layer.type == "nil" then layer.type = "empty" end
                    layer.priority = nil
                    layers[k] = layer
                end
                if not layers[0] then layers[0] = registry.new_empty(0) end
                presets[i] = { name = preset.name or "Default", layers = layers }
            end
            if not presets[1] then presets[1] = { name = "Default", layers = { [0] = registry.new_empty(0) } } end

            storage.controllers[player_index] = {
                ui = {
                    preset_index = old_ui.preset_indx or 1,
                    draw_curve = old_ui.draw_curve or false,
                    preview_build = old_ui.preview_build or false,
                    active_control_point = old_ui.active_control_point,
                },
                curve = { kind = "bezier", points = curve.points },
                presets = presets,
                revision = 1,
                redraw = true,
                work = lib.new_work(),
            }
        end
    end,

    -- 3 -> 4: Catmull-Rom curves. Control points become a plain list (unset and
    -- half-entered slots are dropped), curves get a `closed` flag, and the numbered
    -- pointers are replaced by one pointer that can hold a point.
    [3] = function()
        for _, controller in pairs(storage.controllers or {}) do
            local old = controller.curve or {}
            local slots = {}
            for idx, point in pairs(old.points or {}) do
                if point.x and point.y then table.insert(slots, idx) end
            end
            table.sort(slots)
            local curve = curve_lib.new()
            for _, idx in ipairs(slots) do curve_lib.append(curve, old.points[idx]) end
            controller.curve = curve
            controller.ui.active_control_point = nil
            controller.ui.held_point = nil
            controller.ui.selected_layer = 0
            -- Layer sizes were taken from rounded collision boxes, which made 1x1
            -- entities (e.g. small poles) 2x2. Recompute from the prototypes.
            if prototypes then
                for _, preset in pairs(controller.presets or {}) do
                    for _, layer in pairs(preset.layers or {}) do
                        local prototype = layer.name and prototypes.entity[layer.name]
                        if prototype and layer.type ~= "tile" then
                            layer.size = math.max(1, prototype.tile_width, prototype.tile_height)
                            if type(layer.spacing) == "number" then layer.spacing = math.max(layer.size, layer.spacing) end
                        end
                    end
                end
            end
            controller.revision = (controller.revision or 0) + 1
            controller.redraw = true
            controller.work = lib.new_work()
        end
    end,
}
lib.MIGRATIONS = MIGRATIONS

--- Discard everything (unknown or too old data).
local function reset()
    if rendering then rendering.clear(script.mod_name) end
    if game then
        for _, player in pairs(game.players) do
            if player.gui.screen.bezierio_window then
                player.gui.screen.bezierio_window.destroy()
            end
        end
    end
    storage.controllers = {}
    storage.sprites = {}
end

--- Bring `storage` to the current layout. Safe to call from any event (not on_load).
function lib.ensure()
    local version = storage.schema_version
    if version == lib.SCHEMA_VERSION then return end

    if version == nil or version < 2 or version > lib.SCHEMA_VERSION or not MIGRATIONS[version] then
        -- Fresh game, 0.1.x data, or data from a newer version: start over.
        reset()
    else
        while version < lib.SCHEMA_VERSION do
            MIGRATIONS[version]()
            version = version + 1
        end
        -- Anything drawn under the old layout is stale.
        if rendering then rendering.clear(script.mod_name) end
        storage.sprites = {}
    end
    storage.controllers = storage.controllers or {}
    storage.sprites = storage.sprites or {}
    if prototypes then storage.item_filter = registry.build_item_filter() end
    storage.schema_version = lib.SCHEMA_VERSION
end

-- Accessors -------------------------------------------------------------------

--- @param player_index integer
--- @return Controller
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
    return lib.get(player_index).ui
end

--- @param player_index integer
--- @return Curve
function lib.curve(player_index)
    return lib.get(player_index).curve
end

--- @param controller Controller
--- @return table<integer, Layer>
function lib.layers_of(controller)
    return controller.presets[controller.ui.preset_index].layers
end

--- @param player_index integer
--- @return table<integer, Layer>
function lib.layers(player_index)
    return lib.layers_of(lib.get(player_index))
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

--- The curve or the layers changed: plan again (in the tick loop).
--- @param player_index integer
function lib.changed(player_index)
    local controller = lib.get(player_index)
    controller.revision = controller.revision + 1
    controller.changed_tick = game and game.tick or 0
end

--- Only the view changed (toggles): redraw from the current plan.
--- @param player_index integer
function lib.request_redraw(player_index)
    lib.get(player_index).redraw = true
end

--- Build once the plan for the current curve and layers is ready.
--- @param player_index integer
--- @param mode BezierioBuildMode
function lib.request_build(player_index, mode)
    lib.get(player_index).work.pending_build = mode
end

--- @return ItemPrototypeFilter[]
function lib.item_filter()
    lib.ensure()
    return storage.item_filter
end

--- Rebuild data that depends on prototypes (call from on_configuration_changed).
function lib.refresh_prototype_data()
    lib.ensure()
    storage.item_filter = registry.build_item_filter()
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
