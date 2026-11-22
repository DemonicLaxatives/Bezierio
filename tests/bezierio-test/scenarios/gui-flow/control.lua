-- End-to-end test of the Bézierio window: points, drawing, layers, preview, building.
-- Runs headless with one player: tests/run.sh gui-flow
local P = 1 -- player index
local WIN = { "screen", "bezierio_window", "main" }

local function path(...)
  local p = { table.unpack(WIN) }
  for _, name in ipairs({ ... }) do table.insert(p, name) end
  return p
end
local function dev(fn, ...) return remote.call("bezierio-dev", fn, ...) end
local function controller() return dev("controller", P) end
local function check(cond, msg) if not cond then error("CHECK FAILED: " .. msg, 2) end end

local function find_named(element, name)
  if element.name == name then return element end
  for _, child in pairs(element.children) do
    local found = find_named(child, name)
    if found then return found end
  end
end

local function ghosts(surface, inner)
  return surface.find_entities_filtered { ghost_name = inner }
end

local function prepare_ground(surface)
  surface.request_to_generate_chunks({ 0, 0 }, 4)
  surface.force_generate_chunk_requests()
  local area = { { -60, -60 }, { 60, 60 } }
  for _, e in pairs(surface.find_entities_filtered { area = area }) do
    if e.type ~= "character" then e.destroy() end
  end
  local tiles = {}
  for x = -60, 59 do for y = -60, 59 do table.insert(tiles, { name = "grass-1", position = { x, y } }) end end
  surface.set_tiles(tiles)
end

-- Every wall ghost must be reachable from every other through 4-neighbours.
local function wall_components(walls)
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

local steps = {}
local function step(name, fn, wait) table.insert(steps, { name = name, fn = fn, wait = wait or 1 }) end

step("setup + open window", function(player)
  prepare_ground(player.surface)
  local button = find_named(player.gui.top, "bezierio_button")
  check(button, "mod-gui button exists")
  dev("click", P, button)
  check(player.gui.screen.bezierio_window, "window opened")
end)

step("place P1, P2 with pointer", function(player)
  dev("click", P, path("button_flow", "cp_table", "cp_button_1"))
  check(player.cursor_stack.valid_for_read and player.cursor_stack.name == "bezierio-pointer-1", "pointer 1 in cursor")
  dev("pointer", P, { x = -30.3, y = 5 })
  dev("click", P, path("button_flow", "cp_table", "cp_button_2"))
  check(player.cursor_stack.name == "bezierio-pointer-2", "pointer 2 in cursor")
  dev("pointer", P, { x = 0, y = -40 })
  -- a click over a GUI with the pointer in hand must not move the point
  dev("pointer", P, { x = 99, y = 99 }, path("button_flow", "cp_table", "cp_x_1"))
  dev("pointer", P, { x = 98, y = 98 }, true) -- over a GUI, no element reported (slider)
  local p2 = controller().curve_cache[0].raw_control_points[2]
  check(p2.x == 0 and p2.y == -40, "pointer click over GUI ignored")
end)

step("pointer buttons follow cursor; P3 via textfields", function(player)
  local cp = player.gui.screen.bezierio_window.main.button_flow.cp_table
  check(cp.cp_button_2.toggled and not cp.cp_button_1.toggled,
    "only P2 toggled (1=" ..
    tostring(cp.cp_button_1.toggled) ..
    " 2=" .. tostring(cp.cp_button_2.toggled) .. " active=" .. tostring(controller().state.active_control_point) .. ")")
  check(cp.cp_x_1.text == "-30.3", "P1 x textfield = " .. cp.cp_x_1.text)
  dev("set_text", P, path("button_flow", "cp_table", "cp_x_3"), "30")
  check(controller().curve_cache[0].degree == 1, "half-entered P3 is ignored")
  dev("set_text", P, path("button_flow", "cp_table", "cp_y_3"), "5")
  check(controller().curve_cache[0].degree == 2, "degree 2 after P3")
  dev("set_text", P, path("button_flow", "cp_table", "cp_y_3"), "abc")
  check(cp.cp_y_3.text == "5", "invalid input reverted")
  player.cursor_stack.clear()
end)

step("draw curve", function(player)
  dev("click", P, path("control_flow", "draw_curve"))
  check(controller().state.draw_curve, "draw toggled on")
end, 10)

step("curve rendered", function(player)
  check(dev("render_count") > 10, "curve sprites drawn: " .. dev("render_count"))
end)

step("configure layers", function(player)
  local L = function(k, ...) return path("layer_flow", "layer_" .. k, ...) end
  -- Clicking the picker (which opens the item chooser in the real game) must not
  -- rebuild the row: that destroyed the picker before it could open.
  local picker = player.gui.screen.bezierio_window.main.layer_flow.layer_0.layer_type
  dev("click", P, picker)
  check(picker.valid, "item picker survives being clicked")
  check(controller().presets[1].layers[0].type == "nil", "click alone changes nothing")
  dev("set_elem", P, L(0, "layer_type"), { name = "stone-wall", quality = "normal" })
  -- clicks on sliders / number boxes are not value changes either
  local radius_box = player.gui.screen.bezierio_window.main.layer_flow.layer_0.radius_frame.radius_labels.slider_indicator
  dev("click", P, radius_box)
  check(radius_box.valid, "number box survives being clicked")
  dev("set_value", P, L(0, "radius_frame", "radius_slider_flow", "radius"), 2)
  check(controller().presets[1].layers[0].radius == 2, "radius from slider")
  dev("set_text", P, L(0, "radius_frame", "radius_labels", "slider_indicator"), "99")
  check(controller().presets[1].layers[0].radius == 10, "radius clamped to 10")
  dev("set_text", P, L(0, "radius_frame", "radius_labels", "slider_indicator"), "1")

  dev("click", P, path("layer_flow", "add_layer_above"))
  dev("set_elem", P, L(1, "layer_type"), { name = "small-electric-pole", quality = "normal" })
  dev("set_checked", P, L(1, "smart_placement"), true)
  check(controller().presets[1].layers[1].smart_placement == true, "checkbox stored")

  dev("click", P, path("layer_flow", "add_layer_below"))
  dev("set_elem", P, L(-1, "layer_type"), { name = "stone-brick", quality = "normal" })
  dev("set_value", P, L(-1, "radius_frame", "radius_slider_flow", "radius"), 3)
  dev("set_value", P, L(-1, "checkerboard_frame", "checkerboard_slider_flow", "checkerboard"), -2)

  dev("click", P, path("layer_flow", "add_layer_above"))
  dev("set_elem", P, L(2, "layer_type"), { name = "laser-turret", quality = "normal" })
  dev("set_value", P, L(2, "offset_frame", "offset_slider_flow", "offset"), 1)
  dev("set_value", P, L(2, "spacing_frame", "spacing_slider_flow", "spacing"), 6)

  dev("click", P, path("layer_flow", "add_layer_above"))
  dev("set_elem", P, L(3, "layer_type"), { name = "rail", quality = "normal" })
  local plan = dev("plan", P)
  check(#plan.unsupported == 1 and plan.unsupported[1] == 3, "rail layer reported unsupported")

  -- move the rail layer down and back up, then delete it
  dev("click", P, L(3, "layer_move_down"))
  check(controller().presets[1].layers[2].type == "straight-rail", "moved down")
  dev("click", P, L(2, "layer_move_up"))
  check(controller().presets[1].layers[3].type == "straight-rail", "moved up")
  dev("click", P, L(3, "layer_delete"))
  check(controller().presets[1].layers[3] == nil, "deleted")
  check(controller().presets[1].layers[2].type == "electric-turret", "turret still layer 2")
end)

step("preview", function(player)
  local before = dev("render_count")
  dev("click", P, path("control_flow", "preview_build"))
  storage.before = before
end, 10)

step("preview rendered", function(player)
  check(dev("render_count") > storage.before + 50, "preview drawn: " .. dev("render_count"))

  -- Layers must not overlap.
  local plan = dev("plan", P)
  local cells = {}
  for _, e in pairs(plan.entities) do
    local half = e.size / 2
    for dx = 0, e.size - 1 do
      for dy = 0, e.size - 1 do
        local k = math.floor(e.position.x - half + 0.5 + dx) .. "," .. math.floor(e.position.y - half + 0.5 + dy)
        check(not cells[k], "entity cells overlap at " .. k)
        cells[k] = true
      end
    end
  end
  local planned_walls = {}
  for _, e in pairs(plan.entities) do if e.name == "stone-wall" then table.insert(planned_walls, e) end end
  check(wall_components(planned_walls) == 1, "planned walls are one 4-connected line")
  log("plan: " .. #plan.entities .. " entities, " .. #plan.tiles .. " tiles, skipped " .. plan.skipped)
end)

step("force build", function(player)
  local s = player.surface
  -- obstacles: a tree and one of our own chests on wall spots
  local plan = dev("plan", P)
  local wall_spots = {}
  for _, e in pairs(plan.entities) do if e.name == "stone-wall" then table.insert(wall_spots, e.position) end end
  storage.tree = s.create_entity { name = "tree-01", position = wall_spots[5] }
  storage.chest = s.create_entity { name = "wooden-chest", position = wall_spots[10], force = player.force }
  check(storage.tree and storage.chest, "obstacles placed")

  dev("click", P, path("control_flow", "build"))
  local walls = ghosts(s, "stone-wall")
  storage.wall_count = #walls
  check(#walls == #wall_spots - 1, "all walls but the chest spot: " .. #walls .. "/" .. #wall_spots)
  check(storage.tree.to_be_deconstructed(), "tree marked for deconstruction")
  check(not storage.chest.to_be_deconstructed(), "chest left alone by forced build")
  check(#ghosts(s, "small-electric-pole") > 5, "poles placed")
  check(#ghosts(s, "laser-turret") > 3, "turrets placed")
  check(#s.find_entities_filtered { type = "tile-ghost" } == #plan.tiles,
    "every planned tile ghost placed: " .. #s.find_entities_filtered { type = "tile-ghost" } .. "/" .. #plan.tiles)
  local poles, turrets = 0, 0
  for _, e in pairs(plan.entities) do
    if e.name == "small-electric-pole" then poles = poles + 1 elseif e.name == "laser-turret" then turrets = turrets + 1 end
  end
  check(#ghosts(s, "small-electric-pole") == poles, "every planned pole placed")
  check(#ghosts(s, "laser-turret") == turrets, "every planned turret placed")

  dev("click", P, path("control_flow", "build"))
  check(#ghosts(s, "stone-wall") == storage.wall_count, "second build adds nothing")
end)

step("superforced build", function(player)
  dev("click", P, path("control_flow", "super_build"))
  check(storage.chest.to_be_deconstructed(), "chest marked for deconstruction")
  check(#ghosts(player.surface, "stone-wall") == storage.wall_count + 1, "wall ghost over chest")
  check(wall_components(ghosts(player.surface, "stone-wall")) == 1, "wall ghosts form one 4-connected line")
end)

local function count_planned(plan)
  local n = {}
  for _, e in pairs(plan.entities) do n[e.name] = (n[e.name] or 0) + 1 end
  return n
end

local function clear_build(s)
  for _, e in pairs(s.find_entities_filtered{area = {{-60, -60}, {60, 60}}, type = {"entity-ghost", "tile-ghost"}}) do e.destroy() end
  for _, e in pairs(s.find_entities_filtered{area = {{-60, -60}, {60, 60}}, name = {"stone-wall", "small-electric-pole", "laser-turret"}}) do e.destroy() end
  local tiles = {}
  for _, t in pairs(s.find_tiles_filtered{area = {{-60, -60}, {60, 60}}, name = "stone-path"}) do
    table.insert(tiles, {name = "grass-1", position = t.position})
  end
  s.set_tiles(tiles)
end

step("instant build in cheat mode", function(player)
  local s = player.surface
  clear_build(s)
  local plan = dev("plan", P)
  local planned = count_planned(plan)
  local wall_spots = {}
  for _, e in pairs(plan.entities) do if e.name == "stone-wall" then table.insert(wall_spots, e.position) end end
  storage.tree2 = s.create_entity{name = "tree-01", position = wall_spots[20]}
  storage.chest2 = s.create_entity{name = "wooden-chest", position = wall_spots[30], force = player.force}

  player.cheat_mode = true
  dev("click", P, path("control_flow", "build"))
  check(#s.find_entities_filtered{type = {"entity-ghost", "tile-ghost"}} == 0, "no ghosts in cheat mode")
  check(s.count_entities_filtered{name = "stone-wall"} == planned["stone-wall"] - 1, "real walls except the chest spot: "
    .. s.count_entities_filtered{name = "stone-wall"} .. "/" .. planned["stone-wall"])
  check(s.count_entities_filtered{name = "small-electric-pole"} == planned["small-electric-pole"], "real poles")
  check(s.count_entities_filtered{name = "laser-turret"} == planned["laser-turret"], "real turrets")
  check(s.count_tiles_filtered{name = "stone-path"} == #plan.tiles, "tiles set: " .. s.count_tiles_filtered{name = "stone-path"} .. "/" .. #plan.tiles)
  check(not storage.tree2.valid, "tree removed, not marked")
  check(storage.chest2.valid, "chest kept by forced build")

  dev("click", P, path("control_flow", "super_build"))
  check(not storage.chest2.valid, "chest removed by superforced build")
  check(s.count_entities_filtered{name = "stone-wall"} == planned["stone-wall"], "wall built where the chest was")
  check(wall_components(s.find_entities_filtered{name = "stone-wall"}) == 1, "built walls are one 4-connected line")
  player.cheat_mode = false
end)

step("instant build in map editor", function(player)
  local s = player.surface
  clear_build(s)
  -- a ghost from an earlier build gets revived instead of skipped
  local plan = dev("plan", P)
  local planned = count_planned(plan)
  for _, e in pairs(plan.entities) do
    if e.name == "stone-wall" then
      s.create_entity{name = "entity-ghost", inner_name = "stone-wall", position = e.position, force = player.force}
      break
    end
  end
  player.toggle_map_editor()
  check(player.controller_type == defines.controllers.editor, "in map editor")
  dev("click", P, path("control_flow", "build"))
  local walls = s.count_entities_filtered{name = "stone-wall"}
  player.toggle_map_editor()
  check(walls == planned["stone-wall"], "real walls in editor (incl. revived ghost): " .. walls .. "/" .. planned["stone-wall"])
  check(#s.find_entities_filtered{type = "entity-ghost"} == 0, "no ghosts left in editor build")
  check(player.controller_type ~= defines.controllers.editor, "left map editor")
end)

step("closed curve does not collapse", function(player)
  dev("set_text", P, path("button_flow", "cp_table", "cp_x_4"), "-30.3")
  dev("set_text", P, path("button_flow", "cp_table", "cp_y_4"), "5")
  local plan = dev("plan", P)
  check(#plan.entities > 100, "closed loop still planned: " .. #plan.entities)
end)

step("remove points, clear", function(player)
  dev("click", P, path("button_flow", "cp_table", "cp_button_4"), defines.mouse_button_type.right)
  check(controller().curve_cache[0].degree == 2, "right click removed P4")
  check(not player.gui.screen.bezierio_window.main.button_flow.cp_table.cp_button_4.toggled, "P4 button not toggled")
  dev("click", P, path("button_flow", "control_point_flow", "control_points_clear"))
  check(controller().curve_cache[0].degree == -1, "cleared")
end, 10)

step("cleared curve leaves only nothing rendered", function(player)
  check(dev("render_count") == 0, "no sprites after clear: " .. dev("render_count"))
end)

step("pointer cycling", function(player)
  player.cursor_stack.set_stack { name = "bezierio-pointer-9", count = 1 }
  dev("pointer_cycle", P, 1)
  check(player.cursor_stack.name == "bezierio-pointer-1", "9 -> 1")
  dev("pointer_cycle", P, -1)
  check(player.cursor_stack.name == "bezierio-pointer-9", "1 -> 9")
  player.cursor_stack.clear()
end)

step("close and reopen keeps state", function(player)
  player.opened = nil
  check(not player.gui.screen.bezierio_window, "window closed via on_gui_closed")
  local button = find_named(player.gui.top, "bezierio_button")
  dev("click", P, button)
  local main = player.gui.screen.bezierio_window.main
  check(main.control_flow.draw_curve.toggled, "draw toggle restored")
  check(main.layer_flow.layer_0.layer_type.elem_value.name == "stone-wall", "layer type restored")
end)

local current, wait_until = 1, 30
script.on_event(defines.events.on_tick, function(e)
  if e.tick < wait_until then return end
  local s = steps[current]
  if not s then
    log("TEST PASS: gui-flow (" .. #steps .. " steps)")
    script.finish_test(true)
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
  wait_until = e.tick + s.wait
end)
