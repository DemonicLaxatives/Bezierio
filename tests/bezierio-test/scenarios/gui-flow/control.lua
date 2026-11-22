-- End-to-end test of the Bézierio window: points, drawing, layers, preview, building.
-- Runs headless with one player: tests/run.sh gui-flow
--
-- GUI elements are addressed by name (names are unique within the window), so the
-- test doesn't depend on the window layout.
local P = 1 -- player index

local function dev(fn, ...) return remote.call("bezierio-dev", fn, ...) end
local function controller() return dev("controller", P) end
local function layers() return controller().presets[1].layers end
local function check(cond, msg) if not cond then error("CHECK FAILED: " .. msg, 2) end end

local function find_named(element, name)
  if element.name == name then return element end
  for _, child in pairs(element.children) do
    local found = find_named(child, name)
    if found then return found end
  end
end

--- An element of the main window by name.
local function el(player, name)
  return find_named(player.gui.screen.bezierio_window, name)
end

local function ghosts(surface, inner)
  return surface.find_entities_filtered { ghost_name = inner }
end

local function point_count() return #controller().curve.points end

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

-- Number of 4-connected pieces of a set of 1x1 entities (anything with .position).
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

local function count_planned(plan)
  local n = {}
  for _, e in pairs(plan.entities) do n[e.name] = (n[e.name] or 0) + 1 end
  return n
end

local function planned_walls(plan)
  local walls = {}
  for _, e in pairs(plan.entities) do if e.name == "stone-wall" then table.insert(walls, e) end end
  return walls
end

--- The first two poles of the pole chain, as built (ghost or real).
local function first_pole_pair(surface, plan)
  local chain = plan.chains[1]
  local function at(i)
    local e = plan.entities[chain.members[i]]
    return surface.find_entity(e.name, e.position)
        or surface.find_entities_filtered { ghost_name = e.name, position = e.position, limit = 1 }[1]
  end
  return at(1), at(2)
end

--- Whether a and b are connected by the given wire.
local function wired(a, b, connector_id)
  local connector = a.get_wire_connector(connector_id, false)
  if not connector then return false end
  for _, connection in pairs(connector.connections) do
    if connection.target.owner == b then return true end
  end
  return false
end

local steps = {}
-- wait: ticks to wait after the step, or "idle" = until the mod's planning, drawing
-- and building have caught up (they run spread over ticks).
local function step(name, fn, wait) table.insert(steps, { name = name, fn = fn, wait = wait or 1 }) end

step("setup + open window", function(player)
  prepare_ground(player.surface)
  local button = find_named(player.gui.top, "bezierio_button")
  check(button, "mod-gui button exists")
  dev("click", P, button)
  check(player.gui.screen.bezierio_window, "window opened")
  check(el(player, "no_points"), "empty point list shows a hint")
end)

step("pointer adds points", function(player)
  dev("click", P, "pointer_button")
  check(player.cursor_stack.valid_for_read and player.cursor_stack.name == "bezierio-pointer", "pointer in cursor")
  dev("pointer", P, { x = -30.3, y = 5 })
  dev("pointer", P, { x = 0, y = -40 })
  dev("pointer", P, { x = 99, y = 99 }, "cp_x_1") -- click on a GUI element: ignored
  dev("pointer", P, { x = 98, y = 98 }, true)     -- over a GUI, no element reported: ignored
  dev("pointer", P, { x = 30, y = 5 })
  check(point_count() == 3, "3 points: " .. point_count())
  check(el(player, "cp_x_1").text == "-30.3" and el(player, "cp_y_3").text == "5", "point list shows coordinates")
end)

step("pointer selects, moves and removes points", function(player)
  local function selected() return controller().ui.selected_point end
  dev("pointer", P, { x = 0.4, y = -39.5 })        -- near P2: select it
  check(selected() == 2 and el(player, "cp_label_2").toggled, "P2 selected, list shows it")
  dev("pointer", P, { x = 0, y = -35 })            -- move it
  local p2 = controller().curve.points[2]
  check(selected() == 2 and p2.x == 0 and p2.y == -35, "P2 moved and still selected")
  dev("pointer", P, { x = 0, y = -40 })            -- move it back
  check(controller().curve.points[2].y == -40 and point_count() == 3, "moved back, nothing added")
  dev("select_step", P, 1)
  check(selected() == 3, "shift+wheel: next point")
  dev("select_step", P, 1)
  check(selected() == 1, "shift+wheel: wraps to P1")
  dev("select_step", P, -1)
  check(selected() == 3 and el(player, "cp_label_3").toggled and not el(player, "cp_label_1").toggled, "shift+wheel: previous")
  dev("pointer_remove", P, { x = 0, y = 0 })       -- right-click: deselect
  check(selected() == nil and point_count() == 3, "deselected, nothing removed")
  dev("select_step", P, 1)
  check(selected() == nil, "no cycling without a selection")
  dev("pointer", P, { x = 20, y = 20 })            -- nothing selected: P4 added
  check(point_count() == 4, "P4 added")
  dev("pointer_remove", P, { x = 20.5, y = 19.5 }) -- right-click near P4
  check(point_count() == 3, "P4 removed")
end)

step("pointer inserts points, reverse", function(player)
  dev("pointer_insert", P, { x = -16, y = -20 })    -- shift+click beside the P1-P2 stretch
  local points = controller().curve.points
  check(#points == 4 and points[2].x == -16 and points[2].y == -20, "inserted as P2")
  check(controller().ui.selected_point == 2, "inserted point selected")
  dev("click", P, "cp_delete_2")
  check(point_count() == 3 and controller().ui.selected_point == nil, "deleted, selection gone")
  dev("pointer_insert", P, { x = 35, y = 8 })      -- past the end: appended
  check(point_count() == 4 and controller().curve.points[4].x == 35, "inserted past the end")
  dev("click", P, "cp_delete_4")

  dev("click", P, "cp_label_3")
  dev("click", P, "reverse_points")
  points = controller().curve.points
  check(points[1].x == 30 and points[3].x == -30.3 and controller().ui.selected_point == 1, "reversed, selection follows")
  dev("click", P, "reverse_points")
  check(controller().curve.points[1].x == -30.3 and controller().ui.selected_point == 3, "reversed back")
  dev("click", P, "cp_label_3")
  check(controller().ui.selected_point == nil, "list button deselects")
end)
step("point list edits", function(player)
  dev("set_text", P, "cp_x_3", "abc")
  check(el(player, "cp_x_3").text == "30", "invalid input reverted")
  dev("pointer", P, { x = 10, y = 10 })
  check(point_count() == 4, "P4 added")
  dev("click", P, "cp_delete_4")
  check(point_count() == 3 and not el(player, "cp_x_4"), "P4 deleted from the list")
  dev("click", P, "pointer_button") -- put the pointer away
  check(not player.cursor_stack.valid_for_read, "pointer put away")
  dev("click", P, "cp_label_2")      -- selecting in the list takes the pointer
  check(controller().ui.selected_point == 2 and player.cursor_stack.valid_for_read
    and el(player, "pointer_button").toggled, "list selection takes the pointer")
  dev("click", P, "cp_label_2")
  dev("click", P, "pointer_button")
  check(not player.cursor_stack.valid_for_read and controller().ui.selected_point == nil, "pointer put away again")
end)

step("view settings", function(player)
  dev("click", P, "view_settings_button")
  check(el(player, "view_settings").visible, "view settings shown")
  dev("select", P, "view_curve_color", 4)
  check(controller().view.curve_color == "red", "curve colour set: " .. controller().view.curve_color)
  dev("set_value", P, "view_preview_opacity", 50)
  check(controller().view.preview_opacity == 50 and el(player, "view_preview_opacity_value").caption == "50", "opacity set")
  dev("click", P, "view_reset")
  check(controller().view.curve_color == "blue" and el(player, "view_preview_opacity").slider_value == 30, "reset")
  dev("click", P, "view_settings_button")
  check(not el(player, "view_settings").visible, "view settings hidden")
end)

step("draw curve", function(player)
  dev("click", P, "draw_curve")
  check(controller().ui.draw_curve, "draw toggled on")
end, "idle")

step("curve rendered", function(player)
  check(dev("render_count") > 10, "curve sprites drawn: " .. dev("render_count"))
end)

step("configure layers", function(player)
  -- Clicking the picker (which opens the item chooser in the real game) must not
  -- rebuild the pane: that destroyed the picker before it could open.
  local picker = el(player, "layer_type")
  dev("click", P, picker)
  check(picker.valid, "item picker survives being clicked")
  check(layers()[0].type == "empty", "click alone changes nothing")

  local offered = {}
  for _, n in pairs(dev("item_filter")[1].name) do offered[n] = true end
  check(offered["stone-wall"] and offered["small-electric-pole"] and not offered["rail"], "rails not offered in the picker")

  dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
  dev("set_value", P, "radius_slider", 2)
  check(layers()[0].radius == 2, "radius from slider")
  local radius_box = el(player, "radius_value")
  dev("click", P, radius_box)
  check(radius_box.valid, "number box survives being clicked")
  dev("set_text", P, "radius_value", "99")
  check(layers()[0].radius == 10, "radius clamped to 10")
  dev("set_text", P, "radius_value", "1")

  dev("click", P, "add_layer_above")
  check(controller().ui.selected_layer == 1, "new layer selected")
  dev("set_elem", P, "layer_type", { name = "small-electric-pole", quality = "normal" })
  check(layers()[1].size == 1, "small pole is 1x1, not 2x2: " .. layers()[1].size)
  check(not el(player, "smart_placement"), "smart placement checkbox gone")
  dev("set_checked", P, "connect_with_circuit_wires", true)
  check(layers()[1].connect_with_circuit_wires == true, "circuit wires on")

  dev("click", P, "add_layer_below")
  dev("set_elem", P, "layer_type", { name = "stone-brick", quality = "normal" })
  dev("set_value", P, "radius_slider", 3)
  dev("set_value", P, "checkerboard_slider", -2)
  check(layers()[-1].type == "tile" and layers()[-1].radius == 3, "tile layer")
  -- another similar item keeps the settings (and so does switching back)
  dev("set_elem", P, "layer_type", { name = "concrete", quality = "normal" })
  check(layers()[-1].name == "concrete" and layers()[-1].radius == 3 and layers()[-1].checkerboard == -2
    and el(player, "radius_slider").slider_value == 3, "settings kept when the item changes")
  dev("set_elem", P, "layer_type", { name = "stone-brick", quality = "normal" })
  check(layers()[-1].radius == 3 and layers()[-1].checkerboard == -2, "settings kept switching back")

  dev("click", P, "add_layer_above")
  dev("set_elem", P, "layer_type", { name = "laser-turret", quality = "normal" })
  dev("set_value", P, "offset_slider", 1)
  dev("set_value", P, "spacing_slider", 6)
  check(layers()[2].size == 2 and layers()[2].offset == 1, "turret layer")

  -- an empty layer 3; move it and the selection follows; delete it
  dev("click", P, "add_layer_above")
  dev("click", P, "layer_move_down_3")
  check(layers()[2].type == "empty" and controller().ui.selected_layer == 2, "moved down, selection follows")
  dev("click", P, "layer_move_up_2")
  dev("click", P, "layer_delete_3")
  check(layers()[3] == nil and layers()[2].type == "electric-turret", "deleted")

  dev("click", P, "layer_select_0")
  check(controller().ui.selected_layer == 0 and el(player, "layer_type").elem_value.name == "stone-wall", "layer 0 selected")
  local delete_0 = el(player, "layer_delete_0")
  check(not delete_0.enabled and delete_0.tooltip[1] == "tooltip.delete-layer-0", "layer 0 can't be deleted, says why")
  check(el(player, "layer_rows").type == "scroll-pane", "layer list scrolls")
end)

step("preview", function(player)
  storage.before = dev("render_count")
  dev("click", P, "preview_build")
end, "idle")

step("preview rendered, totals shown", function(player)
  check(dev("render_count") > storage.before + 50, "preview drawn: " .. dev("render_count"))
  check(el(player, "status").caption == "", "status empty when idle")
  check(type(el(player, "totals_length").caption) == "table", "length shown")
  local items = el(player, "totals_items")
  check(items.caption:find("[item=stone-wall]", 1, true) and items.caption:find("[item=stone-brick]", 1, true),
    "items totalled: " .. items.caption)
  check(type(items.tooltip) == "table" and #items.tooltip >= 5, "per-layer breakdown in the tooltip")

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
  check(wall_components(planned_walls(plan)) == 1, "planned walls are one 4-connected line")
  check(plan.gaps == 0, "poles all within reach")
  log("plan: " .. #plan.entities .. " entities, " .. #plan.tiles .. " tiles, skipped " .. plan.skipped)
end)

step("force build", function(player)
  local s = player.surface
  local walls = planned_walls(dev("plan", P))
  storage.tree = s.create_entity { name = "tree-01", position = walls[5].position }
  storage.chest = s.create_entity { name = "wooden-chest", position = walls[10].position, force = player.force }
  check(storage.tree and storage.chest, "obstacles placed")
  storage.undo_before = player.undo_redo_stack.get_undo_item_count()
  dev("click", P, "build")
  check(#ghosts(s, "stone-wall") == 0, "nothing built inside the click handler")
end, "idle")

step("force build placed ghosts", function(player)
  local s = player.surface
  local plan = dev("plan", P)
  local planned = count_planned(plan)
  local walls = ghosts(s, "stone-wall")
  storage.wall_count = #walls
  check(#walls == planned["stone-wall"] - 1, "all walls but the chest spot: " .. #walls .. "/" .. planned["stone-wall"])
  check(storage.tree.to_be_deconstructed(), "tree marked for deconstruction")
  check(not storage.chest.to_be_deconstructed(), "chest left alone by forced build")
  check(#s.find_entities_filtered { type = "tile-ghost" } == #plan.tiles,
    "every planned tile ghost placed: " .. #s.find_entities_filtered { type = "tile-ghost" } .. "/" .. #plan.tiles)
  check(#ghosts(s, "small-electric-pole") == planned["small-electric-pole"], "every planned pole placed")
  check(#ghosts(s, "laser-turret") == planned["laser-turret"], "every planned turret placed")

  local stack = player.undo_redo_stack
  check(stack.get_undo_item_count() == storage.undo_before + 1, "the whole build is one undo item: "
    .. stack.get_undo_item_count() - storage.undo_before)
  check(#stack.get_undo_item(1) >= #walls, "undo item holds the build's actions: " .. #stack.get_undo_item(1))

  local a, b = first_pole_pair(s, plan)
  check(a and b, "pole ghosts found")
  check(wired(a, b, defines.wire_connector_id.circuit_red) and wired(a, b, defines.wire_connector_id.circuit_green),
    "pole ghosts wired red and green")
  dev("click", P, "build")
end, "idle")

step("second build adds nothing", function(player)
  check(#ghosts(player.surface, "stone-wall") == storage.wall_count, "second build adds nothing")
  dev("click", P, "super_build")
end, "idle")

step("superforced build", function(player)
  check(storage.chest.to_be_deconstructed(), "chest marked for deconstruction")
  check(#ghosts(player.surface, "stone-wall") == storage.wall_count + 1, "wall ghost over chest")
  check(wall_components(ghosts(player.surface, "stone-wall")) == 1, "wall ghosts form one 4-connected line")
end)

local function clear_build(s)
  for _, e in pairs(s.find_entities_filtered { area = { { -60, -60 }, { 60, 60 } }, type = { "entity-ghost", "tile-ghost" } }) do e.destroy() end
  for _, e in pairs(s.find_entities_filtered { area = { { -60, -60 }, { 60, 60 } }, name = { "stone-wall", "small-electric-pole", "laser-turret" } }) do e.destroy() end
  local tiles = {}
  for _, t in pairs(s.find_tiles_filtered { area = { { -60, -60 }, { 60, 60 } }, name = "stone-path" }) do
    table.insert(tiles, { name = "grass-1", position = t.position })
  end
  s.set_tiles(tiles)
end

step("instant build in cheat mode", function(player)
  local s = player.surface
  clear_build(s)
  local walls = planned_walls(dev("plan", P))
  storage.tree2 = s.create_entity { name = "tree-01", position = walls[20].position }
  storage.chest2 = s.create_entity { name = "wooden-chest", position = walls[30].position, force = player.force }
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("cheat mode built real entities", function(player)
  local s = player.surface
  local plan = dev("plan", P)
  local planned = count_planned(plan)
  check(#s.find_entities_filtered { type = { "entity-ghost", "tile-ghost" } } == 0, "no ghosts in cheat mode")
  check(s.count_entities_filtered { name = "stone-wall" } == planned["stone-wall"] - 1, "real walls except the chest spot: "
    .. s.count_entities_filtered { name = "stone-wall" } .. "/" .. planned["stone-wall"])
  check(s.count_entities_filtered { name = "small-electric-pole" } == planned["small-electric-pole"], "real poles")
  check(s.count_entities_filtered { name = "laser-turret" } == planned["laser-turret"], "real turrets")
  check(s.count_tiles_filtered { name = "stone-path" } == #plan.tiles,
    "tiles set: " .. s.count_tiles_filtered { name = "stone-path" } .. "/" .. #plan.tiles)
  check(not storage.tree2.valid, "tree removed, not marked")
  check(storage.chest2.valid, "chest kept by forced build")
  local a, b = first_pole_pair(s, plan)
  check(a and b and a.type == "electric-pole", "real poles found")
  check(wired(a, b, defines.wire_connector_id.pole_copper), "real poles connected with copper")
  check(wired(a, b, defines.wire_connector_id.circuit_red), "real poles wired red")
  dev("click", P, "super_build")
end, "idle")

step("cheat mode superforced", function(player)
  local s = player.surface
  local planned = count_planned(dev("plan", P))
  check(not storage.chest2.valid, "chest removed by superforced build")
  check(s.count_entities_filtered { name = "stone-wall" } == planned["stone-wall"], "wall built where the chest was")
  check(wall_components(s.find_entities_filtered { name = "stone-wall" }) == 1, "built walls are one 4-connected line")
  player.cheat_mode = false
end)

step("instant build in map editor", function(player)
  local s = player.surface
  clear_build(s)
  -- a ghost from an earlier build gets revived instead of skipped
  local wall = planned_walls(dev("plan", P))[1]
  s.create_entity { name = "entity-ghost", inner_name = "stone-wall", position = wall.position, force = player.force }
  player.toggle_map_editor()
  check(player.controller_type == defines.controllers.editor, "in map editor")
  game.tick_paused = false -- builds run in the tick loop
  dev("click", P, "build")
end, "idle")

step("map editor built real entities", function(player)
  local s = player.surface
  local planned = count_planned(dev("plan", P))
  local walls = s.count_entities_filtered { name = "stone-wall" }
  player.toggle_map_editor()
  check(walls == planned["stone-wall"], "real walls in editor (incl. revived ghost): " .. walls .. "/" .. planned["stone-wall"])
  check(#s.find_entities_filtered { type = "entity-ghost" } == 0, "no ghosts left in editor build")
  check(player.controller_type ~= defines.controllers.editor, "left map editor")
end)

step("underlay", function(player)
  local s = player.surface
  clear_build(s)
  dev("click", P, "layer_select_-1")
  dev("set_checked", P, "under", true)
  check(layers()[-1].under == true and el(player, "layer_label_-1").caption[1] == "label.layer-row-under", "tiles under")
  dev("click", P, "add_layer_below")
  dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("underlay built under walls", function(player)
  local s = player.surface
  local plan = dev("plan", P)
  local walls, on_path = 0, 0
  for _, e in pairs(plan.entities) do
    if e.layer == -2 then
      walls = walls + 1
      check(s.find_entity("stone-wall", e.position), "L-2 wall built")
      if s.get_tile(e.position.x, e.position.y).name == "stone-path" then on_path = on_path + 1 end
    end
  end
  -- the tile layer is a checkerboard, so about half the walls stand on path
  check(walls > 20 and on_path > walls / 3, "walls on the tiles: " .. on_path .. "/" .. walls)
  player.cheat_mode = false
  dev("click", P, "layer_delete_-2")
  dev("click", P, "layer_select_-1")
  dev("set_checked", P, "under", false)
  dev("click", P, "layer_select_0")
  clear_build(s)
end)

step("no build without permission", function(player)
  local group = game.permissions.create_group("no-build")
  group.set_allows_action(defines.input_action.build, false)
  local old = player.permission_group
  group.add_player(player)
  dev("click", P, "build")
  check(controller().work.pending_build == nil, "build refused")
  if old then old.add_player(player) end
  group.destroy()
end)

step("closed loop", function(player)
  dev("set_checked", P, "closed_loop", true)
  check(controller().curve.closed == true, "closed flag set")
  local plan = dev("plan", P)
  check(plan.closed and #plan.entities > 100, "closed loop planned: " .. #plan.entities)
  dev("set_checked", P, "closed_loop", false)
end)

step("clear points", function(player)
  dev("click", P, "control_points_clear")
  check(point_count() == 0, "cleared")
end, "idle")

step("cleared curve leaves nothing rendered", function(player)
  check(dev("render_count") == 0, "no sprites after clear: " .. dev("render_count"))
end)

step("close and reopen keeps state", function(player)
  player.opened = nil
  check(not player.gui.screen.bezierio_window, "window closed via on_gui_closed")
  dev("click", P, find_named(player.gui.top, "bezierio_button"))
  check(el(player, "draw_curve").toggled, "draw toggle restored")
  check(el(player, "layer_type").elem_value.name == "stone-wall", "layer type restored")
end)

local IDLE_TIMEOUT = 1200
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
  if s.wait == "idle" then
    waiting_idle_since = e.tick
    wait_until = e.tick + 1
  else
    wait_until = e.tick + s.wait
  end
end)
