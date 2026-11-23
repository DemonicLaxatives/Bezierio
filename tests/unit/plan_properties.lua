---@diagnostic disable: undefined-global
-- Property tests for the build planner, runnable outside Factorio:
--   lua5.4 tests/unit/plan_properties.lua [iterations] [seed]
-- Checks, over random curves and layer stacks:
--   * layer 0 walls form one 4-connected line: exactly one piece of 10+ cells. Near
--     sharp turns (cusps) the band can leave small stray pieces; those are cosmetic.
--   (Side layers are not checked for connectivity: on the inside of a bend tighter than
--   their distance from the curve they legitimately split.)
--   * on closed loops, a 1-wide layer 0 wall line is a ring through the seam (no gap)
--   * no two planned entities share a grid cell
--   * no grid cell gets two tiles
local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")

local iterations = tonumber(arg[1]) or 300
local r = helpers.rng(tonumber(arg[2]) or 12345)

local function components(cells, min_size)
  local seen, count = {}, 0
  for key, c in pairs(cells) do
    if not seen[key] then
      seen[key] = true
      local stack, size = { c }, 0
      while #stack > 0 do
        local p = table.remove(stack)
        size = size + 1
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local k = (p[1] + d[1]) .. "," .. (p[2] + d[2])
          if cells[k] and not seen[k] then
            seen[k] = true; stack[#stack + 1] = cells[k]
          end
        end
      end
      if size >= (min_size or 1) then count = count + 1 end
    end
  end
  return count
end

local curve_lib = require("scripts.curve.curve")
local rails_lib = require("scripts.build.rails")

--- Whether a closed curve comes within 2 tiles of itself between parts that are
--- more than 4 tiles apart along the curve.
local function passes_near_itself(points)
  local c = curve_lib.new()
  for _, p in ipairs(points) do curve_lib.append(c, p) end
  c.closed = true
  local samples = curve_lib.samples(c, 1)
  local n = #samples
  for i = 1, n do
    for j = i + 5, n do
      local along = math.min(j - i, n - (j - i)) -- samples are ~1 tile apart
      if along > 4 then
        local dx, dy = samples[i].x - samples[j].x, samples[i].y - samples[j].y
        if dx * dx + dy * dy < 4 then return true end
      end
    end
  end
  return false
end

local failures = 0
local gap_plans = 0
for it = 1, iterations do
  local raw = helpers.random_points(r)
  local layers = helpers.random_layers(r)
  -- every other curve with 3+ points is a closed loop
  local closed = #raw >= 3 and it % 2 == 0
  local plan = helpers.plan(raw, layers, nil, closed)
  local problems = {}

  local occupied, walls_by_layer = {}, {}
  local has_rails = false
  for _, e in ipairs(plan.entities) do
    local x0 = math.floor(e.position.x - e.size / 2 + 0.5)
    local y0 = math.floor(e.position.y - e.size / 2 + 0.5)
    if e.track then
      -- Rails: their real tiles (neighbouring pieces may share a tile at a joint).
      has_rails = true
      for _, c in ipairs(rails_lib.cells(e.name, e.direction)) do
        local k = math.floor(e.position.x + c[1]) .. "," .. math.floor(e.position.y + c[2])
        if occupied[k] and occupied[k] ~= "rail" then table.insert(problems, "rail over another entity at " .. k) end
        occupied[k] = "rail"
      end
    else
      for dx = 0, e.size - 1 do
        for dy = 0, e.size - 1 do
          local k = (x0 + dx) .. "," .. (y0 + dy)
          if occupied[k] then table.insert(problems, "entity overlap at " .. k) end
          occupied[k] = true
        end
      end
    end
    if e.name == "wall" then
      walls_by_layer[e.layer] = walls_by_layer[e.layer] or {}
      walls_by_layer[e.layer][x0 .. "," .. y0] = { x0, y0 }
    end
  end
  local tiles = {}
  for _, t in ipairs(plan.tiles) do
    local k = t.x .. "," .. t.y
    if tiles[k] then table.insert(problems, "tile overlap at " .. k) end
    tiles[k] = true
  end
  -- Pole chains: consecutive poles within wire reach, except where there was no
  -- room for a pole in between; those gaps must be counted in plan.gaps.
  local out_of_reach = 0
  for idx, chain in pairs(plan.chains) do
    local reach = layers[idx].wire_distance
    local n = #chain.members
    local pairs_to_check = n
    if not closed or n < 2 then pairs_to_check = n - 1 end
    for m = 1, pairs_to_check do
      local pa = plan.entities[chain.members[m]].position
      local pb = plan.entities[chain.members[m % n + 1]].position
      if math.sqrt((pa.x - pb.x) ^ 2 + (pa.y - pb.y) ^ 2) > reach + 1e-9 then out_of_reach = out_of_reach + 1 end
    end
  end
  if out_of_reach ~= plan.gaps then
    table.insert(problems, string.format("%d pole pairs out of reach, but plan.gaps = %d", out_of_reach, plan.gaps))
  end
  if plan.gaps > 0 then gap_plans = gap_plans + 1 end

  -- (Rails claim their tiles first: a rail layer next to the wall can cut it.)
  if walls_by_layer[0] and not has_rails then
    local c = components(walls_by_layer[0], 10)
    if c ~= 1 then table.insert(problems, "wall layer 0 has " .. c .. " pieces of 10+ cells") end
    -- A loop with one gap is still one piece. Prune cells with fewer than two
    -- neighbours until none are left to prune: an intact ring survives (spurs at
    -- hairpin tips are pruned away), a line with a gap disappears completely. The
    -- ring must pass the seam at P1. Only checked when the loop never comes within
    -- 2 tiles of itself: where two arms are closer, a 1-wide wall correctly merges
    -- them into one line (a needle), which isn't a ring.
    if closed and layers[0].radius == 1 and not passes_near_itself(raw) then
      local ring = {}
      for k, cell in pairs(walls_by_layer[0]) do ring[k] = cell end
      local pruned = true
      while pruned do
        pruned = false
        for k, cell in pairs(ring) do
          local n = 0
          for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            if ring[(cell[1] + d[1]) .. "," .. (cell[2] + d[2])] then n = n + 1 end
          end
          if n < 2 then ring[k] = nil; pruned = true end
        end
      end
      local near_seam = false
      for _, cell in pairs(ring) do
        if math.abs(cell[1] + 0.5 - raw[1].x) <= 2 and math.abs(cell[2] + 0.5 - raw[1].y) <= 2 then near_seam = true end
      end
      if not near_seam then table.insert(problems, "closed wall line is not a ring through the seam") end
    end
  end

  if #problems > 0 then
    failures = failures + 1
    local pts = {}
    for i, p in ipairs(raw) do pts[i] = "(" .. p.x .. "," .. p.y .. ")" end
    print("FAIL #" .. it .. (closed and " (closed)" or "") .. " points " .. table.concat(pts, " ") .. ": " .. table.concat(problems, "; ", 1, math.min(3, #problems)))
  end
end
-- Simple loops (points on a circle) never pass near themselves, so the ring check
-- always applies.
local ring_cases, ring_failures = 60, 0
for it = 1, ring_cases do
  local n, radius = r.int(3, 8), r.range(6, 60)
  local cx, cy, phase = r.range(-50, 50), r.range(-50, 50), r.range(0, 2 * math.pi)
  local raw = {}
  for k = 1, n do
    local a = phase + 2 * math.pi * (k - 1) / n
    raw[k] = { x = math.floor((cx + radius * math.cos(a)) * 100) / 100, y = math.floor((cy + radius * math.sin(a)) * 100) / 100 }
  end
  local layers = { [0] = { idx = 0, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0 } }
  local plan = helpers.plan(raw, layers, nil, true)
  local ring = {}
  for _, e in ipairs(plan.entities) do
    local x, y = math.floor(e.position.x), math.floor(e.position.y)
    ring[x .. "," .. y] = { x, y }
  end
  local pruned = true
  while pruned do
    pruned = false
    for k, cell in pairs(ring) do
      local m = 0
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if ring[(cell[1] + d[1]) .. "," .. (cell[2] + d[2])] then m = m + 1 end
      end
      if m < 2 then ring[k] = nil; pruned = true end
    end
  end
  local near_seam = false
  for _, cell in pairs(ring) do
    if math.abs(cell[1] + 0.5 - raw[1].x) <= 2 and math.abs(cell[2] + 0.5 - raw[1].y) <= 2 then near_seam = true end
  end
  if not near_seam then
    ring_failures = ring_failures + 1
    print(string.format("FAIL ring #%d: %d points, radius %.1f: wall is not a ring through the seam", it, n, radius))
  end
end
failures = failures + ring_failures
iterations = iterations + ring_cases

-- Tight-bend warnings: none on a straight line, some on a hairpin with side layers.
local side = { [0] = { idx = 0, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0 },
  [1] = { idx = 1, type = "wall", name = "wall", quality = "normal", radius = 3, checkerboard = 0, size = 1, offset = 2 },
  [-1] = { idx = -1, type = "wall", name = "wall", quality = "normal", radius = 3, checkerboard = 0, size = 1, offset = 2 } }
local straight = helpers.plan({ { x = 0, y = 0 }, { x = 40, y = 13 } }, side)
iterations = iterations + 2
if #straight.warnings ~= 0 then failures = failures + 1; print("FAIL straight line has " .. #straight.warnings .. " bend warnings") end
local hairpin = helpers.plan({ { x = 0, y = 0 }, { x = 30, y = 0 }, { x = 30, y = 3 }, { x = 0, y = 3 } }, side)
if #hairpin.warnings == 0 then failures = failures + 1; print("FAIL hairpin has no bend warnings") end

-- Underlay tile layers take no room: adding one anywhere in the stack leaves every
-- entity where it was, keeps the other tiles, and only adds tiles in free cells.
local underlay_cases, underlay_with_overlap = 60, 0
for it = 1, underlay_cases do
  local raw = helpers.random_points(r)
  local layers = helpers.random_layers(r)
  local closed = #raw >= 3 and it % 2 == 0
  local dir = r.int(0, 1) == 1 and 1 or -1
  local outer = 0
  while layers[outer + dir] do outer = outer + dir end
  local at = dir * r.int(1, math.abs(outer) + 1)
  local with = {}
  for k, layer in pairs(layers) do
    local shifted = helpers.deepcopy(layer)
    if k * dir >= at * dir then shifted.idx = k + dir end
    with[shifted.idx] = shifted
  end
  with[at] = { idx = at, type = "tile", name = "under", quality = "normal", radius = r.int(1, 6), checkerboard = 0, size = 1, offset = r.int(0, 2), under = true }

  local base = helpers.plan(raw, layers, nil, closed)
  local plan = helpers.plan(raw, with, nil, closed)
  local problems = {}
  local function entity_keys(p)
    local keys = {}
    for _, e in ipairs(p.entities) do table.insert(keys, string.format("%s@%g,%g", e.name, e.position.x, e.position.y)) end
    table.sort(keys)
    return table.concat(keys, " ")
  end
  if entity_keys(base) ~= entity_keys(plan) then
    table.insert(problems, "entities moved")
    if os.getenv("DEBUG_UNDERLAY") then
      print(entity_keys(base)); print(entity_keys(plan))
      for k, l in pairs(with) do print(k, l.type, l.radius, l.offset, l.size, l.spacing) end
      for _, p in ipairs(raw) do print(p.x, p.y) end
      print("closed", closed)
    end
  end
  local cells, under_cells = {}, {}
  for _, t in ipairs(plan.tiles) do
    local k = t.x .. "," .. t.y
    if cells[k] then table.insert(problems, "tile overlap at " .. k) end
    cells[k] = t.name
    if t.name == "under" then under_cells[k] = true end
  end
  for _, t in ipairs(base.tiles) do
    if cells[t.x .. "," .. t.y] ~= t.name then table.insert(problems, "tile lost at " .. t.x .. "," .. t.y); break end
  end
  for _, e in ipairs(plan.entities) do
    if under_cells[math.floor(e.position.x) .. "," .. math.floor(e.position.y)] then
      underlay_with_overlap = underlay_with_overlap + 1
      break
    end
  end
  if #problems > 0 then
    failures = failures + 1
    print("FAIL underlay #" .. it .. " at L" .. at .. ": " .. table.concat(problems, "; ", 1, math.min(3, #problems)))
  end
end
iterations = iterations + underlay_cases
if underlay_with_overlap == 0 then
  failures = failures + 1
  print("FAIL no underlay ever lay under an entity")
end

-- Smart poles: every powered entity is in some pole's supply area (or counted as
-- unpowered), consecutive poles stay in reach (or are counted gaps), and without
-- anything to power the poles are about a wire reach apart.
local smart_cases, smart_r = 80, helpers.rng(4242)
local MARGIN = 0.3
local smart_unpowered, smart_consumers = 0, 0
for it = 1, smart_cases do
  local raw = helpers.random_points(smart_r)
  local closed = #raw >= 3 and it % 3 == 0
  local wire = smart_r.int(6, 30)
  local reach = smart_r.range(2, 9)
  local layers = {
    [0] = { idx = 0, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0 },
    [1] = { idx = 1, type = "electric-pole", name = "pole", quality = "normal", size = smart_r.int(1, 2), offset = smart_r.int(0, 2), spacing = 3, wire_distance = wire, reach = reach, smart = true },
  }
  local with_consumers = it % 4 ~= 0
  if with_consumers then
    layers[2] = { idx = 2, type = "electric-turret", name = "turret", quality = "normal", size = 2, offset = smart_r.int(0, 3), spacing = smart_r.int(2, 20), needs_power = true }
    layers[-1] = { idx = -1, type = "roboport", name = "roboport", quality = "normal", size = 4, offset = smart_r.int(0, 8), spacing = smart_r.int(4, 40), needs_power = true }
  end
  local plan = helpers.plan(raw, layers, nil, closed)
  local problems = {}
  local poles, consumers = {}, {}
  for _, e in ipairs(plan.entities) do
    if e.layer == 1 then table.insert(poles, e.position) end
    if e.layer == 2 or e.layer == -1 then table.insert(consumers, e) end
  end
  local uncovered = 0
  for _, c in ipairs(consumers) do
    local d = reach + c.size / 2 - MARGIN
    local ok = false
    for _, p in ipairs(poles) do
      if math.abs(c.position.x - p.x) < d and math.abs(c.position.y - p.y) < d then ok = true; break end
    end
    if not ok then uncovered = uncovered + 1 end
  end
  if uncovered ~= plan.unpowered then
    table.insert(problems, uncovered .. " consumers unpowered, " .. plan.unpowered .. " reported")
  end
  smart_unpowered, smart_consumers = smart_unpowered + uncovered, smart_consumers + #consumers
  local chain = plan.chains[1]
  local out_of_reach = 0
  local n = #chain.members
  for m = 1, (closed and n > 2) and n or n - 1 do
    local pa = plan.entities[chain.members[m]].position
    local pb = plan.entities[chain.members[m % n + 1]].position
    if math.sqrt((pa.x - pb.x) ^ 2 + (pa.y - pb.y) ^ 2) > wire + 1e-9 then out_of_reach = out_of_reach + 1 end
  end
  if out_of_reach ~= plan.gaps then table.insert(problems, out_of_reach .. " pairs out of reach, gaps " .. plan.gaps) end
  if not with_consumers and plan.length > 0 then
    -- The centre line can be longer than the curve on the outside of bends.
    local limit = math.ceil(plan.length * 1.5 / math.max(1, wire - 2)) + 2
    if #poles > limit then table.insert(problems, #poles .. " poles for length " .. string.format("%.0f", plan.length) .. ", reach " .. wire) end
  end
  if #problems > 0 then
    failures = failures + 1
    print("FAIL smart #" .. it .. (closed and " (closed)" or "") .. ": " .. table.concat(problems, "; "))
  end
end
iterations = iterations + smart_cases
print(string.format("(smart poles: %d of %d powered entities out of reach; the test puts some on the far side on purpose)", smart_unpowered, smart_consumers))

-- Shapes: a circle or ellipse of 1-wide wall is one unbroken ring (every cell has
-- two neighbours after pruning spurs); an arc is one piece. Either direction.
local shape_cases, shape_r = 60, helpers.rng(777)
for it = 1, shape_cases do
  local kind = ({ "circle", "ellipse", "arc" })[it % 3 + 1]
  local cx, cy = shape_r.range(-50, 50), shape_r.range(-50, 50)
  local rr = shape_r.range(4, 60)
  local ang = shape_r.range(0, 2 * math.pi)
  local handles = { { x = cx, y = cy }, { x = cx + rr * math.cos(ang), y = cy + rr * math.sin(ang) } }
  if kind == "ellipse" then
    local other = shape_r.range(4, 60)
    handles[3] = { x = cx - other * math.sin(ang), y = cy + other * math.cos(ang) }
  elseif kind == "arc" then
    local to = ang + shape_r.range(0.3, 6)
    handles[3] = { x = cx + math.cos(to), y = cy + math.sin(to) }
  end
  local curve = helpers.shape_curve(kind, handles, it % 2 == 0)
  local plan = helpers.plan_curve(curve, { [0] = { idx = 0, type = "wall", name = "wall", quality = "normal", radius = 1, checkerboard = 0, size = 1, offset = 0 } })
  local walls = {}
  for _, e in ipairs(plan.entities) do
    local x, y = math.floor(e.position.x), math.floor(e.position.y)
    walls[x .. "," .. y] = { x, y }
  end
  local problems = {}
  local pieces = components(walls, 1)
  if pieces ~= 1 then table.insert(problems, pieces .. " pieces") end
  if kind ~= "arc" then
    local ring = {}
    for k, cell in pairs(walls) do ring[k] = cell end
    local pruned = true
    while pruned do
      pruned = false
      for k, cell in pairs(ring) do
        local m = 0
        for _, dd in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          if ring[(cell[1] + dd[1]) .. "," .. (cell[2] + dd[2])] then m = m + 1 end
        end
        if m < 2 then ring[k] = nil; pruned = true end
      end
    end
    if next(ring) == nil then table.insert(problems, "not a closed ring") end
  end
  if #problems > 0 then
    failures = failures + 1
    print(string.format("FAIL shape #%d %s r=%.1f: %s", it, kind, rr, table.concat(problems, "; ")))
  end
end
iterations = iterations + shape_cases

print(string.format("(%d plans had pole gaps where there was no room for a pole)", gap_plans))
print(string.format("%d/%d random plans passed", iterations - failures, iterations))
os.exit(failures == 0 and 0 or 1)
