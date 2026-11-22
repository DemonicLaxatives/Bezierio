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

-- 2 -> 3 -> 4 -> 5
storage = v2_storage()
state.ensure()
local c = storage.controllers[1]
check(storage.schema_version == state.SCHEMA_VERSION, "schema version bumped")
check(c.ui.preset_index == 1 and c.ui.draw_curve == true, "ui state carried over")
check(c.ui.active_control_point == nil and c.ui.held_point == nil and c.ui.selected_point == nil, "numbered pointer state dropped")
check(c.view and c.view.curve_color == "blue" and c.view.preview_opacity == 30, "view settings added")
check(c.state == nil and c.curve_cache == nil, "old fields gone")
check(c.curve.kind == "catmull_rom" and c.curve.closed == false, "curve kind")
check(#c.curve.points == 2, "complete points kept as a list, gaps and half points dropped")
check(c.curve.points[1].x == -30.3 and c.curve.points[2].x == 30 and c.curve.points[2].y == 5, "point order kept")
local layers = c.presets[1].layers
check(layers[0].type == "wall" and layers[0].radius == 2 and layers[0].priority == nil, "wall layer kept, priority dropped")
check(layers[1].type == "empty", "nil layer -> empty")
check(type(c.revision) == "number" and c.redraw == true and type(c.work) == "table", "job fields added")
check(next(storage.sprites) == nil, "stale sprite references dropped")
check(storage.item_filter ~= nil, "item filter kept")

-- 3 -> 4 on its own: sparse slots with a gap
storage = { schema_version = 3, sprites = {}, controllers = { [2] = {
    ui = { preset_index = 1, draw_curve = false, preview_build = true, active_control_point = 2 },
    curve = { kind = "bezier", points = { [2] = { x = 1, y = 2 }, [7] = { x = 3, y = 4 }, [4] = { x = 9 } } },
    presets = { { name = "Default", layers = { [0] = { idx = 0, type = "empty", size = 1, offset = 0 } } } },
    revision = 5, redraw = false, work = {},
} } }
state.ensure()
local c2 = storage.controllers[2]
check(#c2.curve.points == 2 and c2.curve.points[1].y == 2 and c2.curve.points[2].x == 3, "3->4: slots in order")
check(c2.revision == 6 and c2.redraw == true and c2.work.draw ~= nil, "3->4: replan and redraw")
check(c2.ui.preview_build == true, "3->4: toggles kept")

-- 4 -> 5 on its own: a held point becomes the selected point
storage = { schema_version = 4, sprites = {}, controllers = { [3] = {
    ui = { preset_index = 1, draw_curve = true, preview_build = false, held_point = 2, selected_layer = 0 },
    curve = { kind = "catmull_rom", points = { { x = 0, y = 0 }, { x = 5, y = 5 } }, closed = false },
    presets = { { name = "Default", layers = { [0] = { idx = 0, type = "empty", size = 1, offset = 0 } } } },
    revision = 2, redraw = false, work = {},
} } }
state.ensure()
local c3 = storage.controllers[3]
check(c3.ui.selected_point == 2 and c3.ui.held_point == nil, "4->5: held point selected")
check(c3.view.selected_color == "amber" and c3.redraw == true, "4->5: view settings, redraw")

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
