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
local screen = {}
game = { players = { { index = 1, gui = { screen = screen } } } }
-- (a destroyed window is gone from the screen, as in the game)
screen.bezierio_window = { destroy = function() destroyed = destroyed + 1; screen.bezierio_window = nil end }
prototypes = {
    entity = {
        ["stone-wall"] = { type = "wall", tile_width = 1, tile_height = 1 },
        ["small-electric-pole"] = {
            type = "electric-pole", tile_width = 1, tile_height = 1,
            get_max_wire_distance = function() return 7.5 end,
            get_supply_area_distance = function() return 2.5 end,
        },
        ["laser-turret"] = { type = "electric-turret", tile_width = 2, tile_height = 2, electric_energy_source_prototype = {} },
        ["gate"] = { type = "gate", name = "gate", tile_width = 1, tile_height = 1 },
    },
    get_entity_filtered = function() return {} end,
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

check(#FILES == 1 and FILES[1] == "0.2.0.lua", "only the 0.1 -> 0.2 migration ships: " .. table.concat(FILES, " "))

-- When a release changes the storage layout (schema N -> N+1), add its file to
-- migrations/ (named after that release) and a case here:
--   storage = <data as schema N wrote it>
--   load_save()
--   check(storage.schema_version == state.SCHEMA_VERSION and <the converted data>, "N -> N+1: ...")
-- and the same in tests/bezierio-migration-fixture (a real save, tests/migrate-save.sh).

-- 0.1.x data (no schema version, old shape) is discarded
cleared, destroyed = 0, 0
screen.bezierio_window = { destroy = function() destroyed = destroyed + 1; screen.bezierio_window = nil end }
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

-- Saves from before the release (0.2 development builds, older schemas): reset.
storage = { schema_version = 5, controllers = { [1] = { x = 1 } }, sprites = {} }
load_save()
state.on_configuration_changed()
check(next(storage.controllers) == nil and storage.schema_version == state.SCHEMA_VERSION, "pre-release dev data reset")

-- Data from a newer version is discarded rather than misread. (Going back to an
-- older mod version changes the mod version, so the game raises on_configuration_changed.)
storage = { schema_version = state.SCHEMA_VERSION + 1, controllers = { [1] = { x = 1 } }, sprites = {} }
for _, name in ipairs(FILES) do dofile(helpers.repo .. "/migrations/" .. name) end
state.on_configuration_changed()
check(next(storage.controllers) == nil and storage.schema_version == state.SCHEMA_VERSION, "newer data discarded")

print(string.format("%d/%d migration checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
