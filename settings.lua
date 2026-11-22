data:extend {
  {
    -- Work units per player per tick for planning, drawing and building (see
    -- scripts/jobs.lua). Higher finishes sooner but costs more time per tick;
    -- 1000 is ~2.5-3 ms per tick per player.
    type = "int-setting",
    name = "bezierio-work-budget",
    setting_type = "runtime-global",
    default_value = 1000,
    minimum_value = 200,
    maximum_value = 100000,
    order = "a",
  },
}
