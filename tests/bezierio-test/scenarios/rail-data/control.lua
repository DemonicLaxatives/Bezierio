-- Generates scripts/build/rail_data.lua: for each rail end direction (0..15), the
-- rail pieces the rail planner can attach (relative to the end) and the signal
-- locations at such an end. Run: tests/run.sh rail-data, then copy the RAILDATA
-- lines (tests/gen-rail-data.sh does both).
local PLANNER = "rail"
local SPACING = 64 -- each test rail in its own spot (a multiple of the rail grid)

local function rel(loc, origin)
  return { x = loc.position.x - origin.x, y = loc.position.y - origin.y, direction = loc.direction }
end

script.on_event(defines.events.on_tick, function(e)
  if e.tick ~= 5 then return end
  local s, force = game.surfaces[1], game.forces["player"]
  s.request_to_generate_chunks({ 0, 0 }, 12); s.force_generate_chunk_requests()
  for _, ent in pairs(s.find_entities_filtered { area = { { -400, -400 }, { 400, 400 } } }) do
    if ent.type ~= "character" then ent.destroy() end
  end
  local tiles = {}
  for x = -400, 399 do for y = -400, 399 do tiles[#tiles + 1] = { name = "grass-1", position = { x, y } } end end
  s.set_tiles(tiles)

  local slot = 0
  local function fresh_spot()
    slot = slot + 1
    return { x = (slot % 10) * SPACING - 300, y = math.floor(slot / 10) * SPACING - 300 }
  end
  --- Build a rail at a fresh spot, translated by a multiple of the grid; return it and the shift.
  local function build(name, position, direction)
    local spot = fresh_spot()
    local shift = { x = spot.x - math.floor(position.x / 2) * 2, y = spot.y - math.floor(position.y / 2) * 2 }
    local rail = s.create_entity { name = name, position = { position.x + shift.x, position.y + shift.y }, direction = direction, force = force }
    return rail, shift
  end

  local data = { ends = {}, cells = {}, ramps = { up = {}, down = {} } }
  local GROUND = { ["straight-rail"] = true, ["half-diagonal-rail"] = true, ["curved-rail-a"] = true, ["curved-rail-b"] = true }
  --- The tiles a rail covers (where a 1x1 wall no longer fits), relative to its position.
  local function record_cells(rail)
    local key = rail.name .. "/" .. rail.direction
    if data.cells[key] then return end
    local box, out = rail.bounding_box, {}
    for x = math.floor(box.left_top.x) - 1, math.ceil(box.right_bottom.x) do
      for y = math.floor(box.left_top.y) - 1, math.ceil(box.right_bottom.y) do
        if not s.can_place_entity { name = "stone-wall", position = { x + 0.5, y + 0.5 }, force = force } then
          out[#out + 1] = { x - rail.position.x, y - rail.position.y }
        end
      end
    end
    data.cells[key] = out
  end
  local queue = {}
  local first = build("straight-rail", { x = 0, y = 0 }, defines.direction.north)
  queue[#queue + 1] = first
  local head = 1
  local seen_rails = 0
  while queue[head] and seen_rails < 400 do
    local rail = queue[head]
    head = head + 1
    seen_rails = seen_rails + 1
    record_cells(rail)
    for _, which in ipairs({ defines.rail_direction.front, defines.rail_direction.back }) do
      local rail_end = rail.get_rail_end(which)
      local loc = rail_end.location
      local d = loc.direction
      local parity = (loc.position.x % 2) .. "," .. (loc.position.y % 2)
      data.ends[d] = data.ends[d] or {}
      if not data.ends[d][parity] then
        local entry = { extensions = {}, signals = {} }
        for _, ext in ipairs(rail_end.get_rail_extensions(PLANNER)) do
          if GROUND[ext.name] then
          entry.extensions[#entry.extensions + 1] = {
            name = ext.name, x = ext.position.x - loc.position.x, y = ext.position.y - loc.position.y,
            direction = ext.direction, goal = rel(ext.goal, loc.position),
          }
          local built = build(ext.name, ext.position, ext.direction)
          if built then queue[#queue + 1] = built end
          end
        end
        for _, key in ipairs({ "in_signal_location", "out_signal_location", "alternative_in_signal_location", "alternative_out_signal_location" }) do
          local ok, sl = pcall(function() return rail_end[key] end)
          if ok and sl then entry.signals[key] = rel(sl, loc.position) end
        end
        data.ends[d][parity] = entry
      end
    end
  end
  -- Ramps (elevated-rails mod): up from a ground end facing straight, and down
  -- from an elevated end (the ramp's top) facing straight.
  if prototypes.entity["rail-ramp"] then
    for _, d in ipairs({ 0, 4, 8, 12 }) do
      local _, entry = next(data.ends[d])
      -- a ground rail whose end faces d
      local rail, shift
      for _, ext in ipairs(data.ends[(d + 8) % 16][next(data.ends[(d + 8) % 16])].extensions) do
        if ext.name == "straight-rail" then
          local spot = fresh_spot()
          rail = s.create_entity { name = "straight-rail", position = { spot.x + 1, spot.y + 1 }, direction = d, force = force }
        end
      end
      for _, which in ipairs({ defines.rail_direction.front, defines.rail_direction.back }) do
        local en = rail.get_rail_end(which)
        if en.location.direction == d then
          for _, ext in ipairs(en.get_rail_extensions("rail-ramp")) do
            if ext.name == "rail-ramp" then
              local loc = en.location
              data.ramps.up[d] = { name = ext.name, x = ext.position.x - loc.position.x, y = ext.position.y - loc.position.y,
                direction = ext.direction, goal = rel(ext.goal, loc.position) }
              local ramp = s.create_entity { name = "rail-ramp", position = ext.position, direction = ext.direction, force = force }
              record_cells(ramp)
              for _, w2 in ipairs({ defines.rail_direction.front, defines.rail_direction.back }) do
                local top = ramp.get_rail_end(w2)
                if top.location.rail_layer == defines.rail_layer.elevated then
                  -- the top, facing d; going down from an elevated end facing the other way
                  for _, down in ipairs(top.get_rail_extensions(PLANNER)) do
                    if down.name == "rail-ramp" then
                      local tl = top.location
                      data.ramps.down[tl.direction] = { name = down.name, x = down.position.x - tl.position.x, y = down.position.y - tl.position.y,
                        direction = down.direction, goal = rel(down.goal, tl.position) }
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
    local support = prototypes.entity["rail-support"]
    data.support = { name = "rail-support", range = support and support.support_range, ramp_range = prototypes.entity["rail-ramp"].support_range }
  end
  local count = 0
  for d in pairs(data.ends) do count = count + 1 end
  log("RAILDATA-DIRECTIONS " .. count)
  for d = 0, 15 do
    local parities = {}
    for p in pairs(data.ends[d] or {}) do parities[#parities + 1] = p end
    table.sort(parities)
    log("RAILDATA-PARITY " .. d .. " " .. table.concat(parities, " "))
  end
  log("RAILDATA " .. serpent.line(data, { comment = false, sortkeys = true }))
  script.finish_test(true)
end)
