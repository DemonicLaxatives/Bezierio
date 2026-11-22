---@diagnostic disable: undefined-global, lowercase-global
-- Storage migrations: runs the files in migrations/ the way the game does (each
-- file once, in lexicographic file name order, then on_configuration_changed) on
-- hand-made storage, outside Factorio.
--   lua5.4 tests/unit/migrations.lua
local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")
local state = require("scripts.state")

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

-- The parts of the game API that migrations and state.lua use.
local cleared, destroyed = 0, 0
script = { mod_name = "Bezierio" }
rendering = { clear = function() cleared = cleared + 1 end }
game = { players = { { gui = { screen = { bezierio_window = { destroy = function() destroyed = destroyed + 1 end } } } } } }
prototypes = {
    entity = {
        ["stone-wall"] = { type = "wall", tile_width = 1, tile_height = 1 },
        ["small-electric-pole"] = {
            type = "electric-pole", tile_width = 1, tile_height = 1,
            get_max_wire_distance = function() return 7.5 end,
            get_supply_area_distance = function() return 2.5 end,
        },
        ["laser-turret"] = { type = "electric-turret", tile_width = 2, tile_height = 2, electric_energy_source_prototype = {} },
    },
    tile = {},
    get_item_filtered = function() return { ["stone-wall"] = true } end,
}

--- migrations/*.lua in the game's order.
local function migration_files()
    local files = {}
    local list = io.popen('ls "' .. helpers.repo .. '/migrations"')
    for name in list:lines() do
        if name:match("%.lua$") then table.insert(files, name) end
    end
    list:close()
    table.sort(files) -- byte-wise, as the game does
    return files
end
local FILES = migration_files()

--- Load a save: apply every migration file; the next tick or event finishes the
--- upgrade (the game doesn't raise on_configuration_changed for migrations alone).
local function load_save()
    for _, name in ipairs(FILES) do dofile(helpers.repo .. "/migrations/" .. name) end
    state.ensure_rebuilt()
    check(storage.rebuild_needed == nil, "rebuilt once")
end

check(FILES[#FILES] == "0.2.0.lua" and FILES[1] == "0.2.0-dev-1.lua", "dev upgrades sort before 0.2.0.lua: " .. table.concat(FILES, " "))

-- Storage as written by schema 2 (the first 2.1 layout).
local function v2_storage()
    return {
        schema_version = 2,
        controllers = {
            [1] = {
                state = { preset_indx = 1, draw_curve = true, preview_build = false, active_control_point = 3, dirty = false },
                curve_cache = { [0] = {
                    raw_control_points = { [1] = { x = -30.3, y = 5 }, [3] = { x = 30, y = 5 }, [5] = { x = 7 } },
                    p0 = { x = -30.3, y = 5 }, control_points = {}, degree = 1, parameters_changed = false, resolution = 0.5,
                } },
                presets = { { name = "Default", layers = {
                    [0] = { idx = 0, priority = 100, placed_by = "stone-wall", name = "stone-wall", quality = "normal", size = 1, offset = 0, type = "wall", checkerboard = 0, radius = 2 },
                    [1] = { idx = 1, priority = 0, size = 1, offset = 0, type = "nil" },
                    [2] = { idx = 2, priority = 10, placed_by = "small-electric-pole", name = "small-electric-pole", quality = "normal", size = 2, offset = 0, type = "electric-pole", spacing = 1 },
                } } },
            },
        },
        sprites = { [1] = { curve = {}, control_points = {}, preview = {} } },
        item_filter = { { filter = "name", name = { "stone-wall" } } },
    }
end

-- 2 -> 3 -> 4 -> 5
storage = v2_storage()
load_save()
local c = storage.controllers[1]
check(storage.schema_version == state.SCHEMA_VERSION, "schema version bumped")
check(c.ui.preset_index == 1 and c.ui.draw_curve == true, "ui state carried over")
check(c.ui.active_control_point == nil and c.ui.held_point == nil and c.ui.selected_point == nil, "numbered pointer state dropped")
check(c.view and c.view.curve_color == "blue" and c.view.preview_opacity == 30, "view settings added")
check(c.state == nil and c.curve_cache == nil, "old fields gone")
check(c.curve.kind == "catmull_rom" and c.curve.closed == false, "curve kind")
check(c.curve.handles and c.curve.handles.circle and type(c.curve.reversed) == "table" and next(c.curve.reversed) == nil, "shape handles and direction flags added")
check(#c.curve.points == 2, "complete points kept as a list, gaps and half points dropped")
check(c.curve.points[1].x == -30.3 and c.curve.points[2].x == 30 and c.curve.points[2].y == 5, "point order kept")
local layers = c.presets[1].layers
check(layers[0].type == "wall" and layers[0].radius == 2 and layers[0].priority == nil, "wall layer kept, priority dropped")
check(layers[1].type == "empty", "nil layer -> empty")
check(layers[2].size == 1 and layers[2].spacing == 1, "small pole resized to 1x1 from the prototype")
check(type(c.revision) == "number" and c.redraw == true and type(c.work) == "table" and c.work.draw, "jobs rebuilt")
check(next(storage.sprites) == nil, "stale sprite references dropped")
check(storage.item_filter[1].name[1] == "stone-wall", "item filter rebuilt")
check(layers[2].wire_distance == 7 and layers[2].reach == 2.5 and layers[2].needs_power == nil, "pole values derived from its prototype")
check(layers[0].needs_power == nil, "walls need no power")

-- 3 -> 4 on its own: sparse slots with a gap
storage = { schema_version = 3, sprites = {}, controllers = { [2] = {
    ui = { preset_index = 1, draw_curve = false, preview_build = true, active_control_point = 2 },
    curve = { kind = "bezier", points = { [2] = { x = 1, y = 2 }, [7] = { x = 3.456, y = 4 }, [4] = { x = 9 } } },
    presets = { { name = "Default", layers = { [0] = { idx = 0, type = "empty", size = 1, offset = 0 } } } },
    revision = 5, redraw = false, work = {},
} } }
load_save()
local c2 = storage.controllers[2]
check(#c2.curve.points == 2 and c2.curve.points[1].y == 2 and c2.curve.points[2].x == 3.46, "3->4: slots in order, rounded")
check(c2.revision > 5 and c2.redraw == true and c2.work.draw ~= nil, "3->4: replan and redraw")
check(c2.ui.preview_build == true, "3->4: toggles kept")

-- 4 -> 5 on its own: a held point becomes the selected point
storage = { schema_version = 4, sprites = {}, controllers = { [3] = {
    ui = { preset_index = 1, draw_curve = true, preview_build = false, held_point = 2, selected_layer = 0 },
    curve = { kind = "catmull_rom", points = { { x = 0, y = 0 }, { x = 5, y = 5 } }, closed = false },
    presets = { { name = "Default", layers = { [0] = { idx = 0, type = "empty", size = 1, offset = 0 } } } },
    revision = 2, redraw = false, work = {},
} } }
load_save()
local c3 = storage.controllers[3]
check(c3.ui.selected_point == 2 and c3.ui.held_point == nil, "4->5: held point selected")
check(c3.view.selected_color == "amber" and c3.redraw == true, "4->5: view settings, redraw")

-- 7 -> 8: one reversed flag for all shapes becomes a flag per kind
storage = { schema_version = 7, sprites = {}, controllers = { [5] = {
    ui = { preset_index = 1, draw_curve = false, preview_build = false, selected_layer = 0 },
    curve = { kind = "circle", points = {}, closed = false, handles = { circle = {}, ellipse = {}, arc = {} }, reversed = true },
    presets = { { name = "Default", layers = { [0] = { idx = 0, type = "empty", size = 1, offset = 0 } } } },
    revision = 2, redraw = false, work = {},
} } }
load_save()
local r5 = storage.controllers[5].curve.reversed
check(r5.circle == true and r5.arc == true and r5.catmull_rom == nil, "7->8: shapes stay reversed, the spline doesn't")

-- 8 -> 9: one circuit wire setting becomes red and green
storage = { schema_version = 8, sprites = {}, controllers = { [6] = {
    ui = { preset_index = 1, draw_curve = false, preview_build = false, selected_layer = 0 },
    curve = { kind = "catmull_rom", points = {}, closed = false, handles = { circle = {}, ellipse = {}, arc = {} }, reversed = {} },
    presets = { { name = "Default", layers = {
        [0] = { idx = 0, type = "empty", size = 1, offset = 0 },
        [1] = { idx = 1, type = "electric-pole", name = "small-electric-pole", placed_by = "small-electric-pole", quality = "normal", size = 1, offset = 0, spacing = 6, connect_with_circuit_wires = true },
    } } },
    revision = 2, redraw = false, work = {},
} } }
load_save()
local pole6 = storage.controllers[6].presets[1].layers[1]
check(pole6.red_wire == true and pole6.green_wire == true and pole6.connect_with_circuit_wires == nil, "8->9: circuit wires -> red and green")

-- The migrated controller works with the current code.
local planner = require("scripts.build.planner")
storage = v2_storage()
load_save()
local plan = planner.plan(storage.controllers[1].curve, storage.controllers[1].presets[1].layers)
check(#plan.entities > 0, "migrated data plans a build")

-- 0.1.x data (no schema version, old shape) is discarded
cleared, destroyed = 0, 0
storage = { controllers = { [1] = { foo = 1 } }, curve_projectors = { 1, 2 } }
load_save()
check(storage.schema_version == state.SCHEMA_VERSION and next(storage.controllers) == nil, "0.1 data discarded")
check(storage.curve_projectors == nil, "0.1 tables removed")
check(cleared > 0 and destroyed == 1, "0.1 drawings and window removed")

-- New game: on_init, then the game runs every migration file. Nothing may change.
storage = {}
state.init()
storage.controllers[4] = state.new_controller()
storage.controllers[4].curve.points = { { x = 1, y = 1 }, { x = 2, y = 2 } }
storage.controllers[4].ui.selected_point = 2
local before = helpers.canonical_table(storage)
for _, name in ipairs(FILES) do dofile(helpers.repo .. "/migrations/" .. name) end
check(helpers.canonical_table(storage) == before, "migrations do nothing on current data")
check(storage.schema_version == state.SCHEMA_VERSION, "fresh storage at the current version")

-- Current data keeps its contents through a configuration change
state.on_configuration_changed()
check(storage.controllers[4].curve.points[2].x == 2 and storage.controllers[4].ui.selected_point == 2, "current data kept")

-- Data from a newer version is discarded rather than misread. (Going back to an
-- older mod version changes the mod version, so the game raises on_configuration_changed.)
storage = { schema_version = state.SCHEMA_VERSION + 1, controllers = { [1] = { x = 1 } }, sprites = {} }
for _, name in ipairs(FILES) do dofile(helpers.repo .. "/migrations/" .. name) end
state.on_configuration_changed()
check(next(storage.controllers) == nil and storage.schema_version == state.SCHEMA_VERSION, "newer data discarded")

print(string.format("%d/%d migration checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
