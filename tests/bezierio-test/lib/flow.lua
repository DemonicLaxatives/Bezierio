-- Shared pieces of the GUI test scenarios: helpers, a standard curve and layer
-- stack, and the step runner.
--
--   local flow = require("__bezierio-test__/lib/flow")
--   local step, el, check, dev = flow.step, flow.el, flow.check, flow.dev
--   step("name", function(player) ... end, wait)   -- wait: ticks, or "idle"
--   flow.run("scenario-name")
--
-- GUI elements are addressed by name (names are unique within the window), so the
-- tests don't depend on the window layout.
local flow = {}

flow.P = 1 -- player index
local P = flow.P

function flow.dev(fn, ...) return remote.call("bezierio-dev", fn, ...) end
local dev = flow.dev
function flow.controller() return dev("controller", P) end
function flow.layers() return flow.controller().presets[flow.controller().ui.preset_index].layers end
function flow.point_count() return #flow.controller().curve.points end
function flow.check(cond, msg) if not cond then error("CHECK FAILED: " .. msg, 2) end end
local check = flow.check

function flow.find_named(element, name)
  if element.name == name then return element end
  for _, child in pairs(element.children) do
    local found = flow.find_named(child, name)
    if found then return found end
  end
end

--- An element of the main window by name.
function flow.el(player, name)
  return flow.find_named(player.gui.screen.bezierio_window, name)
end

function flow.ghosts(surface, inner)
  return surface.find_entities_filtered { ghost_name = inner }
end

--- Flat grass around the origin, nothing on it.
function flow.prepare_ground(surface)
  surface.request_to_generate_chunks({ 0, 0 }, 4)
  surface.force_generate_chunk_requests()
  -- (as far as the scenarios clear and build: beyond, map generation is random,
  -- and water there blocked a ramp at the end of a track now and then)
  local area = { { -100, -100 }, { 100, 100 } }
  for _, e in pairs(surface.find_entities_filtered { area = area }) do
    if e.type ~= "character" then e.destroy() end
  end
  local tiles = {}
  for x = -100, 99 do for y = -100, 99 do table.insert(tiles, { name = "grass-1", position = { x, y } }) end end
  surface.set_tiles(tiles)
end

--- Remove everything a build placed.
function flow.clear_build(s)
  local area = { { -60, -60 }, { 60, 60 } }
  for _, e in pairs(s.find_entities_filtered { area = area, type = { "entity-ghost", "tile-ghost" } }) do e.destroy() end
  for _, e in pairs(s.find_entities_filtered { area = area, name = { "stone-wall", "small-electric-pole", "laser-turret" } }) do e.destroy() end
  local tiles = {}
  for _, t in pairs(s.find_tiles_filtered { area = area, name = "stone-path" }) do
    table.insert(tiles, { name = "grass-1", position = t.position })
  end
  s.set_tiles(tiles)
end

--- Number of 4-connected pieces of a set of 1x1 entities (anything with .position).
function flow.wall_components(walls)
  local set, keys = {}, {}
  for _, w in pairs(walls) do
    local k = math.floor(w.position.x) .. "," .. math.floor(w.position.y)
    set[k] = { math.floor(w.position.x), math.floor(w.position.y) }
    table.insert(keys, k)
  end
  local seen, components = {}, 0
  for _, start in ipairs(keys) do
    if not seen[start] then
      components = components + 1
      local stack = { start }
      seen[start] = true
      while #stack > 0 do
        local c = set[table.remove(stack)]
        for _, d in pairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local k = (c[1] + d[1]) .. "," .. (c[2] + d[2])
          if set[k] and not seen[k] then
            seen[k] = true; table.insert(stack, k)
          end
        end
      end
    end
  end
  return components
end

function flow.count_planned(plan)
  local n = {}
  for _, e in pairs(plan.entities) do n[e.name] = (n[e.name] or 0) + 1 end
  return n
end

function flow.planned_walls(plan)
  local walls = {}
  for _, e in pairs(plan.entities) do if e.name == "stone-wall" then table.insert(walls, e) end end
  return walls
end

--- Open the window with the mod-gui button.
function flow.open_window(player)
  local button = flow.find_named(player.gui.top, "bezierio_button")
  check(button, "mod-gui button exists")
  dev("click", P, button)
  check(player.gui.screen.bezierio_window, "window opened")
end

--- The test curve: P1 (-30.3, 5), P2 (0, -40), P3 (30, 5), placed with the pointer,
--- which is put away again.
function flow.standard_curve()
  dev("click", P, "pointer_button")
  dev("pointer", P, { x = -30.3, y = 5 })
  dev("pointer", P, { x = 0, y = -40 })
  dev("pointer", P, { x = 30, y = 5 })
  dev("click", P, "pointer_button")
end

--- The test layer stack: L0 stone wall, L1 small poles with circuit wires,
--- L-1 stone path (width 3, checkerboard -2), L2 laser turrets (offset 1, spacing 6).
--- Ends with layer 0 selected.
function flow.standard_layers()
  dev("click", P, "layer_select_0")
  dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
  dev("click", P, "add_layer_above")
  dev("set_elem", P, "layer_type", { name = "small-electric-pole", quality = "normal" })
  dev("set_checked", P, "red_wire", true)
  dev("set_checked", P, "green_wire", true)
  dev("click", P, "add_layer_below")
  dev("set_elem", P, "layer_type", { name = "stone-brick", quality = "normal" })
  dev("set_value", P, "radius_slider", 3)
  dev("set_value", P, "checkerboard_slider", -2)
  dev("click", P, "add_layer_above")
  dev("set_elem", P, "layer_type", { name = "laser-turret", quality = "normal" })
  dev("set_value", P, "offset_slider", 1)
  dev("set_value", P, "spacing_slider", 6)
  dev("click", P, "layer_select_0")
end

local steps = {}

--- Add a step. wait: ticks to wait after it, or "idle" = until the mod's planning,
--- drawing and building have caught up (they run spread over ticks).
function flow.step(name, fn, wait) table.insert(steps, { name = name, fn = fn, wait = wait or 1 }) end

local IDLE_TIMEOUT = 1200

--- Run the steps, one per tick (or after their wait), then finish the test.
--- @param scenario string
function flow.run(scenario)
  local current, wait_until, waiting_idle_since = 1, 30, nil
  script.on_event(defines.events.on_tick, function(e)
    if waiting_idle_since then
      if dev("idle", P) then
        waiting_idle_since = nil
      elseif e.tick - waiting_idle_since > IDLE_TIMEOUT then
        log("TEST FAIL: still busy " .. IDLE_TIMEOUT .. " ticks after step '" .. steps[current - 1].name .. "'")
        script.finish_test(false)
        waiting_idle_since, wait_until = nil, math.huge
        return
      else
        return
      end
    end
    if e.tick < wait_until then return end
    local s = steps[current]
    if not s then
      log("TEST PASS: " .. scenario .. " (" .. #steps .. " steps)")
      script.finish_test(true)
      wait_until = math.huge
      return
    end
    local player = game.get_player(P)
    local ok, err = pcall(s.fn, player)
    if not ok then
      log("TEST FAIL in step '" .. s.name .. "': " .. tostring(err))
      script.finish_test(false)
      wait_until = math.huge
      return
    end
    log("step ok: " .. s.name)
    current = current + 1
    if s.wait == "idle" then
      waiting_idle_since = e.tick
      wait_until = e.tick + 1
    else
      wait_until = e.tick + s.wait
    end
  end)
end

return flow
