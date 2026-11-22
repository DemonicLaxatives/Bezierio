-- Used by tests/migrate-save.sh. When the save is created (with a copy of Bézierio
-- that has no migrations/ folder), it overwrites Bézierio's storage with data in
-- an old layout. When the save is loaded with the real mod, the game applies the
-- migration files and then raises on_configuration_changed, where this checks the
-- result on the first tick (the game doesn't raise on_configuration_changed when
-- it only applied migrations; Bézierio's tick handler runs first, as this mod
-- depends on it).
local function dev(fn, ...) return remote.call("bezierio-dev", fn, ...) end

-- Storage as written by schema 2 (the first 2.1 dev layout).
local OLD = {
  schema_version = 2,
  controllers = {
    [1] = {
      state = { preset_indx = 1, draw_curve = true, preview_build = true, active_control_point = 3 },
      curve_cache = { [0] = { raw_control_points = { [1] = { x = -30.3, y = 5 }, [3] = { x = 30, y = 5 }, [5] = { x = 7 } } } },
      presets = { { name = "Default", layers = {
        [0] = { idx = 0, priority = 100, placed_by = "stone-wall", name = "stone-wall", quality = "normal", size = 1, offset = 0, type = "wall", checkerboard = 0, radius = 2 },
        [1] = { idx = 1, priority = 10, placed_by = "small-electric-pole", name = "small-electric-pole", quality = "normal", size = 2, offset = 0, type = "electric-pole", spacing = 6, wire_distance = 7 },
        [-1] = { idx = -1, priority = 0, size = 1, offset = 0, type = "nil" },
      } } },
    },
  },
  sprites = {},
}

script.on_init(function()
  dev("set_storage", OLD)
  log("MIGRATION FIXTURE written, schema " .. dev("storage").schema_version)
end)

local function verify(when)
  local s = dev("storage")
  local problems = {}
  local function check(cond, msg) if not cond then table.insert(problems, msg) end end
  local c = s.controllers[1]
  check(s.schema_version == dev("schema_version"), "schema " .. tostring(s.schema_version))
  check(c and c.curve.kind == "catmull_rom" and #c.curve.points == 2, "curve converted")
  check(c and c.presets[1].layers[1].size == 1, "pole resized from its prototype")
  check(c and c.presets[1].layers[-1].type == "empty", "nil layer -> empty")
  check(c and c.view and c.view.curve_color == "blue", "view settings filled in")
  check(c and c.work and c.work.draw, "jobs rebuilt")
  if #problems == 0 then
    log("MIGRATION PASS (" .. when .. ")")
  else
    log("MIGRATION FAIL (" .. when .. "): " .. table.concat(problems, "; "))
  end
end

script.on_event(defines.events.on_tick, function(e)
  if e.tick > 0 then
    verify("first tick")
    script.on_event(defines.events.on_tick, nil)
  end
end)
