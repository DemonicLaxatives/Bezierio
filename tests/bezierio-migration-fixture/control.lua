-- Used by tests/migrate-save.sh. When the save is created (with a copy of Bézierio
-- that has no migrations/ folder), it overwrites Bézierio's storage with data in
-- an old layout. When the save is loaded with the real mod, the game applies the
-- migration files and then raises on_configuration_changed, where this checks the
-- result on the first tick (the game doesn't raise on_configuration_changed when
-- it only applied migrations; Bézierio's tick handler runs first, as this mod
-- depends on it).
---@diagnostic disable-next-line: param-type-mismatch
local function dev(fn, ...) return remote.call("bezierio-dev", fn, ...) end

-- Storage as 0.1.x left it (no schema_version; the curve projector building).
-- Add the layout of a schema N here when a release migrates N -> N+1, and check
-- its conversion in verify().
local OLD = {
  controllers = { [1] = { foo = 1 } },
  curve_projectors = { [1] = { unit_number = 1 } },
}

script.on_init(function()
  dev("set_storage", OLD)
  log("MIGRATION FIXTURE written, schema " .. tostring(dev("storage").schema_version))
end)

local function verify(when)
  local s = dev("storage")
  local problems = {}
  local function check(cond, msg) if not cond then table.insert(problems, msg) end end
  check(s.schema_version == dev("schema_version"), "schema " .. tostring(s.schema_version))
  check(s.curve_projectors == nil, "0.1 tables removed")
  check(s.controllers and s.controllers[1] == nil or (s.controllers[1] and s.controllers[1].foo == nil), "0.1 controllers discarded")
  check(s.rebuild_needed == nil, "rebuilt")
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
