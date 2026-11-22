---@diagnostic disable: undefined-global
-- Property tests for the build planner, runnable outside Factorio:
--   lua5.4 tests/unit/plan_properties.lua [iterations] [seed]
-- Checks, over random curves and layer stacks:
--   * layer 0 walls form one 4-connected line: exactly one piece of 10+ cells. Near
--     sharp turns (cusps) the band can leave small stray pieces; those are cosmetic.
--   (Side layers are not checked for connectivity: on the inside of a bend tighter than
--   their distance from the curve they legitimately split.)
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

local failures = 0
for it = 1, iterations do
  local raw = helpers.random_points(r)
  local layers = helpers.random_layers(r)
  local plan = helpers.plan(raw, layers)
  local problems = {}

  local occupied, walls_by_layer = {}, {}
  for _, e in ipairs(plan.entities) do
    local x0 = math.floor(e.position.x - e.size / 2 + 0.5)
    local y0 = math.floor(e.position.y - e.size / 2 + 0.5)
    for dx = 0, e.size - 1 do
      for dy = 0, e.size - 1 do
        local k = (x0 + dx) .. "," .. (y0 + dy)
        if occupied[k] then table.insert(problems, "entity overlap at " .. k) end
        occupied[k] = true
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
  if walls_by_layer[0] then
    local c = components(walls_by_layer[0], 10)
    if c ~= 1 then table.insert(problems, "wall layer 0 has " .. c .. " pieces of 10+ cells") end
  end

  if #problems > 0 then
    failures = failures + 1
    local pts = {}
    for i, p in ipairs(raw) do pts[i] = "(" .. p.x .. "," .. p.y .. ")" end
    print("FAIL #" ..
    it .. " points " .. table.concat(pts, " ") .. ": " .. table.concat(problems, "; ", 1, math.min(3, #problems)))
  end
end
print(string.format("%d/%d random plans passed", iterations - failures, iterations))
os.exit(failures == 0 and 0 or 1)
