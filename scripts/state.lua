--- Single source of truth for the shape of `storage`.
--- Every other module goes through these accessors instead of indexing `storage`.
---
--- storage.schema_version   integer, see MIGRATIONS
--- storage.controllers[i]   per-player Controller
--- storage.sprites[i]       per-player render objects (SpriteCache)
---
--- Nothing that can be derived from the mod's code and the prototypes is kept in
--- storage (the item picker filter, layer values like sizes and wire reach are
--- recomputed), so a code update needs no migration for it: a save made before a
--- new layer type was added still offers it.
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
--- @field preset_mode "rename"|nil  # the preset bar shows the rename box (window only)
--- @field pointer_mode "move"|nil        # clicks move the curve (until right-click)
--- @field narrow boolean|nil            # the window is narrowed (everyday controls only)
--- @field pinned boolean|nil            # the window stays open when other GUIs open
--- @field editing {idx: integer, backup: Layer|nil, new: boolean|nil, revision: integer|nil, locked: table<integer, true>|nil}|nil  # layer settings window open (backup: to cancel to; revision: when it opened; locked: main window elements greyed out, window.lock_main)
--- @field reopen_main boolean|nil      # make the main window the opened GUI next tick (window.focus_main)

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
--- @field highlight HighlightQueue|nil    # unpowered / unfed marks being drawn (highlight.lua)

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
--- @field settings PlayerSettings|nil   # (missing fields: SETTING_DEFAULTS)

--- @class SpriteCache
--- @field curve LuaRenderObject[]
--- @field control_points LuaRenderObject[]
--- @field preview LuaRenderObject[]
--- @field highlight_unpowered LuaRenderObject[]|nil  # marks (highlight.lua): kept when the drawing is redone
--- @field highlight_unfed LuaRenderObject[]|nil
--- @field trash (LuaRenderObject[]|LuaRenderObject)[]|nil  # retired caches, destroyed a few objects per tick

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

--- Per-player settings besides the view (the settings window; they were per-user
--- mod settings before). Missing ones read as these.
--- @class PlayerSettings
--- @field highlight_seconds integer   # unpowered / unfed marks fade after this (0: until hidden)
--- @field blueprint_source boolean    # blueprints carry the curve and preset
--- @field cover_tiles string[]|nil    # cover items for force builds, in order (build/cover.lua)
--- (cover_tiles: none set means each tile's own default cover, build/cover.lua)
lib.SETTING_DEFAULTS = { highlight_seconds = 60, blueprint_source = true, cover_tiles = nil }

--- A player's setting (its default if never set).
--- @param player_index integer
--- @param name string
--- @return any
function lib.setting(player_index, name)
    local controller = storage.controllers and storage.controllers[player_index]
    local value = controller and controller.settings and controller.settings[name]
    if value == nil then return lib.SETTING_DEFAULTS[name] end
    return value
end

--- @param player_index integer
--- @param name string
--- @param value any
function lib.set_setting(player_index, name, value)
    local controller = lib.get(player_index)
    controller.settings = controller.settings or {}
    controller.settings[name] = value
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

--- Bézierio's windows (the main one, settings, a layer's settings, import / export).
local WINDOWS = { "bezierio_window", "bezierio_settings_window", "bezierio_layer_window", "bezierio_string_window" }

--- Close every Bézierio window of every player: after a mod change they may be
--- built by older code (other names, tags), and a layer edit can't be cancelled
--- any more (its edits are kept).
local function close_windows()
    if not game then return end
    for _, player in pairs(game.players) do
        for _, name in ipairs(WINDOWS) do
            local window = player.gui.screen[name]
            if window then window.destroy() end
        end
        local controller = storage.controllers and storage.controllers[player.index]
        if controller and controller.ui then controller.ui.editing = nil end
    end
end

--- Discard everything: a fresh, empty layout.
local function reset()
    if rendering then rendering.clear(script.mod_name) end
    close_windows()
    for key in pairs(storage) do storage[key] = nil end
    storage.controllers = {}
    storage.sprites = {}
    storage.schema_version = lib.SCHEMA_VERSION
end

--- New game, or the mod was added to a save (script.on_init).
function lib.init()
    reset()
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
    close_windows()
    storage.sprites = {}
    storage.item_filter = nil -- (kept in storage before schema 9; now derived on use)
    for _, controller in pairs(storage.controllers) do
        for _, preset in pairs(controller.presets) do lib.refresh_layers(preset.layers) end
        controller.work = lib.new_work()
        controller.redraw = true
        controller.redraw_points = nil
        controller.revision = (controller.revision or 0) + 1
        controller.view = controller.view or {}
        for key, value in pairs(palette.VIEW_DEFAULTS) do
            if controller.view[key] == nil then controller.view[key] = value end
        end
    end
end

--- Recompute the values layers derive from their prototypes (sizes, wire reach,
--- power, undergrounds, ...): mods may have changed them, and newer code may derive
--- more. Layers whose prototype or type is gone become empty. Called on
--- configuration changes and before every plan.
--- @param layers table<integer, Layer>
function lib.refresh_layers(layers)
    if not prototypes then return end
    for idx, layer in pairs(layers) do
        if not registry.types[layer.type] or not registry.refresh(layer) then
            local empty = registry.new_empty(idx)
            empty.offset = layer.offset or 0
            layers[idx] = empty
        end
    end
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
--- The layer item pickers' filter: built from the layer types and the prototypes,
--- so it's the same on every machine and kept out of storage (a save made before a
--- layer type existed offers it all the same).
--- @type ItemPrototypeFilter[]|nil
local item_filter_cache = nil

--- @return ItemPrototypeFilter[]
function lib.item_filter()
    if not item_filter_cache then item_filter_cache = registry.build_item_filter() end
    return item_filter_cache
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
