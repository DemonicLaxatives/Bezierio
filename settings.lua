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
  {
    -- How long unpowered and unfed entities stay marked after a build (0: until
    -- their warning in the window is clicked).
    type = "int-setting",
    name = "bezierio-highlight-seconds",
    setting_type = "runtime-per-user",
    default_value = 60,
    minimum_value = 0,
    maximum_value = 3600,
    order = "b",
  },
  {
    -- Blueprints made by Bezierio carry the curve and preset they were made from.
    type = "bool-setting",
    name = "bezierio-blueprint-source",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "c",
  },
}
