--- Single source of truth for the shape of `storage`.
--- Every other module goes through these accessors instead of indexing `storage`.
---
--- storage.schema_version   integer, see MIGRATIONS
--- storage.controllers[i]   per-player Controller
--- storage.sprites[i]       per-player render objects (SpriteCache)
--- storage.item_filter      filter for the layer item pickers
local registry = require("scripts.layers.registry")
local curve_lib = require("scripts.curve.curve")
local palette = require("scripts.palette")

local lib = {}

--- @class InterfaceState
--- @field preset_index integer
--- @field draw_curve boolean
--- @field preview_build boolean
--- @field selected_point integer|nil   # control point the pointer moves (until right-click)
--- @field selected_layer integer        # layer shown in the detail pane
--- @field preset_mode "rename"|"export"|"import"|nil  # what the preset bar shows (window only)
--- @field pointer_mode "move"|nil        # clicks move the curve (until right-click)

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
--- @field pending_build BezierioBuildMode|"blueprint"|nil    # build requested, waiting for the plan
--- @field build BuildJob|BlueprintJob|nil
--- @field status string|nil              # last status line shown (to update only on change)
--- @field totals_revision integer|nil    # revision whose totals are shown

--- @class Controller
--- @field ui InterfaceState
--- @field curve Curve
--- @field presets Preset[]
--- @field view ViewSettings             # how this player's drawing looks
--- @field revision integer               # bumped whenever the curve or layers change
--- @field changed_tick integer|nil        # tick of the last change (planning waits a moment)
--- @field redraw boolean                 # view settings changed; redraw from scratch
--- @field redraw_points boolean|nil       # only the point markers changed (selection)
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
        ui = { preset_index = 1, draw_curve = false, preview_build = false, selected_point = nil, selected_layer = 0 },
        curve = curve_lib.new(),
        view = lib.default_view(),
        presets = { { name = "Default", layers = { [0] = registry.new_empty(0) } } },
        revision = 1,
        redraw = true,
        work = lib.new_work(),
    }
end

--- @return ViewSettings
function lib.default_view()
    local view = {}
    for k, v in pairs(palette.VIEW_DEFAULTS) do view[k] = v end
    return view
end

-- Lifecycle -------------------------------------------------------------------

--- Version of the layout of `storage`. Upgrades are migration files in
--- migrations/, run by the game once per save in file name order when a save is
--- loaded. Each acts only on its own starting version, so they are harmless on new
--- games, which run them all after on_init.
---
--- Changing the layout: bump this, add migrations/<mod version>[-n].lua that
--- upgrades from the previous version, sets the new one and sets
--- `storage.rebuild_needed`, using only `storage`, `game`, `rendering` and
--- `prototypes` (not this code: it will change). Add the case to
--- tests/unit/migrations.lua.
---
--- The game doesn't raise on_configuration_changed when it only applied
--- migrations (2.1.24, mod version unchanged), so `rebuild_needed` makes the next
--- access do what on_configuration_changed does (lib.ensure_rebuilt).
lib.SCHEMA_VERSION = 9

--- Discard everything: a fresh, empty layout.
local function reset()
    if rendering then rendering.clear(script.mod_name) end
    if game then
        for _, player in pairs(game.players) do
            if player.gui.screen.bezierio_window then
                player.gui.screen.bezierio_window.destroy()
            end
        end
    end
    for key in pairs(storage) do storage[key] = nil end
    storage.controllers = {}
    storage.sprites = {}
    storage.schema_version = lib.SCHEMA_VERSION
end

--- New game, or the mod was added to a save (script.on_init).
function lib.init()
    reset()
    if prototypes then storage.item_filter = registry.build_item_filter() end
end

--- Mods, prototypes, startup settings or migrations changed
--- (script.on_configuration_changed). Rebuild everything derived: running jobs
--- refer to plans for prototypes that may be gone, and drawings may be stale. Fill
--- in settings added since the data was saved.
function lib.on_configuration_changed()
    storage.rebuild_needed = nil
    if storage.schema_version ~= lib.SCHEMA_VERSION then
        -- From a newer version of the mod, or not migrated: start over.
        reset()
    end
    if rendering then rendering.clear(script.mod_name) end
    storage.sprites = {}
    for _, controller in pairs(storage.controllers) do
        -- Values layers derive from prototypes (sizes, wire reach, power) may have
        -- changed with the mods; layers whose prototype is gone become empty.
        if prototypes then
            for _, preset in pairs(controller.presets) do
                for idx, layer in pairs(preset.layers) do
                    if not registry.types[layer.type] or not registry.refresh(layer) then
                        local empty = registry.new_empty(idx)
                        empty.offset = layer.offset or 0
                        preset.layers[idx] = empty
                    end
                end
            end
        end
        controller.work = lib.new_work()
        controller.redraw = true
        controller.redraw_points = nil
        controller.revision = (controller.revision or 0) + 1
        controller.view = controller.view or {}
        for key, value in pairs(palette.VIEW_DEFAULTS) do
            if controller.view[key] == nil then controller.view[key] = value end
        end
    end
    if prototypes then storage.item_filter = registry.build_item_filter() end
end

--- After migrations: rebuild once, on whatever touches storage first.
function lib.ensure_rebuilt()
    if storage.rebuild_needed then lib.on_configuration_changed() end
end

-- Accessors -------------------------------------------------------------------

--- @param player_index integer
--- @return Controller
function lib.get(player_index)
    lib.ensure_rebuilt()
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
--- @return ViewSettings
function lib.view(player_index)
    return lib.get(player_index).view
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
    lib.ensure_rebuilt()
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

--- Only the point markers changed (e.g. the selection): redraw just those.
--- @param player_index integer
function lib.request_point_redraw(player_index)
    lib.get(player_index).redraw_points = true
end

--- Build once the plan for the current curve and layers is ready.
--- @param player_index integer
--- @param mode BezierioBuildMode|"blueprint"
function lib.request_build(player_index, mode)
    lib.get(player_index).work.pending_build = mode
end

--- @return ItemPrototypeFilter[]
function lib.item_filter()
    return storage.item_filter
end

--- @param player_index integer
function lib.remove_player(player_index)
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
