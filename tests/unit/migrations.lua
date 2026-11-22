---@diagnostic disable: undefined-global, lowercase-global
-- Storage migrations (scripts/state.lua), run outside Factorio on hand-made storage.
--   lua5.4 tests/unit/migrations.lua
local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")
local state = require("scripts.state")

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

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
                } } },
            },
        },
        sprites = { [1] = { curve = {}, control_points = {}, preview = {} } },
        item_filter = { { filter = "name", name = { "stone-wall" } } },
    }
end

-- 2 -> 3
storage = v2_storage()
state.ensure()
local c = storage.controllers[1]
check(storage.schema_version == state.SCHEMA_VERSION, "schema version bumped")
check(c.ui.preset_index == 1 and c.ui.draw_curve == true and c.ui.active_control_point == 3, "ui state carried over")
check(c.state == nil and c.curve_cache == nil, "old fields gone")
check(c.curve.kind == "bezier", "curve kind")
check(c.curve.points[1].x == -30.3 and c.curve.points[3].y == 5, "control points carried over")
check(c.curve.points[5].x == 7 and c.curve.points[5].y == nil, "half-entered point kept")
check(c.curve.points[2] == nil, "unset slot stays unset")
local layers = c.presets[1].layers
check(layers[0].type == "wall" and layers[0].radius == 2 and layers[0].priority == nil, "wall layer kept, priority dropped")
check(layers[1].type == "empty", "nil layer -> empty")
check(type(c.revision) == "number" and c.redraw == true and type(c.work) == "table", "job fields added")
check(next(storage.sprites) == nil, "stale sprite references dropped")
check(storage.item_filter ~= nil, "item filter kept")

-- The migrated controller works with the current code.
local planner = require("scripts.build.planner")
local plan = planner.plan(c.curve, layers)
check(#plan.entities > 0, "migrated data plans a build")

-- Fresh game
storage = {}
state.ensure()
check(storage.schema_version == state.SCHEMA_VERSION and next(storage.controllers) == nil, "fresh storage initialised")

-- 0.1.x data (no schema version, old shape) is discarded
storage = { controllers = { [1] = { foo = 1 } }, curve_projectors = {} }
state.ensure()
check(storage.schema_version == state.SCHEMA_VERSION and next(storage.controllers) == nil, "unversioned data discarded")

-- Data from a newer version is discarded rather than misread
storage = { schema_version = state.SCHEMA_VERSION + 1, controllers = { [1] = { x = 1 } } }
state.ensure()
check(next(storage.controllers) == nil, "newer data discarded")

-- Current version is left alone
storage = { schema_version = state.SCHEMA_VERSION, controllers = { [7] = state.new_controller() }, sprites = {} }
state.ensure()
check(storage.controllers[7] ~= nil, "current data untouched")

print(string.format("%d/%d migration checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
