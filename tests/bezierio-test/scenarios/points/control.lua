-- Editing the curve: the pointer in the world, the point list, closed loops.
-- tests/run.sh points
local flow = require("__bezierio-test__/lib/flow")
local P, dev, check, el, step = flow.P, flow.dev, flow.check, flow.el, flow.step
local controller, point_count = flow.controller, flow.point_count

step("setup + open window", function(player)
  flow.prepare_ground(player.surface)
  flow.open_window(player)
  check(el(player, "no_points"), "empty point list shows a hint")
end)

step("pointer puts the hand away first", function(player)
  local inventory = player.get_main_inventory()
  player.cursor_stack.set_stack { name = "iron-plate", count = 10 }
  dev("click", P, "pointer_button")
  check(player.cursor_stack.valid_for_read and player.cursor_stack.name == "bezierio-pointer"
    and inventory.get_item_count("iron-plate") == 10, "pointer in the cursor, plates in the inventory")
  dev("click", P, "pointer_button")
  inventory.clear()
  -- a full inventory: the hand is kept, no pointer
  while inventory.insert { name = "stone", count = 1000 } > 0 do end
  player.cursor_stack.set_stack { name = "iron-plate", count = 10 }
  dev("click", P, "pointer_button")
  check(player.cursor_stack.valid_for_read and player.cursor_stack.name == "iron-plate"
    and player.cursor_stack.count == 10 and not el(player, "pointer_button").toggled, "full inventory: hand kept, button off")
  player.cursor_stack.clear()
  inventory.clear()
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
  check(points[1].x == -30.3 and points[3].x == 30 and controller().ui.selected_point == 3, "reversed: points and selection unchanged")
  check(controller().curve.reversed.catmull_rom == true and el(player, "reverse_points").toggled, "reversed, button shows it")
  dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
  local plan = dev("plan", P)
  check(plan.entities[1] and math.abs(plan.entities[1].position.x - 30) < 3, "the curve now starts at P3")
  dev("click", P, "reverse_points")
  check(not controller().curve.reversed.catmull_rom and not el(player, "reverse_points").toggled, "reversed back")
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

step("draw curve", function(player)
  dev("click", P, "draw_curve")
  check(controller().ui.draw_curve, "draw toggled on")
end, "idle")

step("curve rendered", function(player)
  check(dev("render_count") > 10, "curve sprites drawn: " .. dev("render_count"))
end)

step("closed loop", function(player)
  dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
  dev("click", P, "closed_loop")
  check(controller().curve.closed == true and el(player, "closed_loop").toggled, "closed loop toggled on")
  local plan = dev("plan", P)
  check(plan.closed and #plan.entities > 100, "closed loop planned: " .. #plan.entities)
  dev("click", P, "closed_loop")
  check(controller().curve.closed == false, "and off")
end)

step("shapes with the pointer", function(player)
  local function active() return controller().curve.handles[controller().curve.kind] end
  local spline = controller().curve.points
  dev("select", P, "curve_kind", 2) -- circle
  check(controller().curve.kind == "circle" and not el(player, "closed_loop").visible, "circle selected, no closed toggle")
  check(el(player, "no_points").caption[1] == "label.next-handle", "says what to click next")
  dev("click", P, "pointer_button")
  dev("pointer", P, { x = 0.5, y = 0.5 })      -- centre
  dev("pointer", P, { x = 0.5, y = -9.5 })     -- radius 10
  dev("pointer", P, { x = 30, y = 30 })        -- a third handle: refused
  check(#active() == 2 and not el(player, "no_points"), "two handles, list complete")
  local plan = dev("plan", P)
  check(plan.closed and #plan.entities > 40, "circle planned: " .. #plan.entities)
  for _, e in pairs(plan.entities) do
    local d = math.sqrt((e.position.x - 0.5) ^ 2 + (e.position.y - 0.5) ^ 2)
    check(d > 8.5 and d < 11.5, "wall on the circle")
  end

  -- the centre moves the whole circle
  dev("pointer", P, { x = 0.5, y = 0.5 })      -- select C
  dev("pointer", P, { x = 20.5, y = 0.5 })     -- move it
  check(active()[1].x == 20.5 and active()[2].x == 20.5 and active()[2].y == -9.5, "circle moved with its centre")
  dev("pointer_remove", P, { x = 0, y = 0 })   -- deselect
  dev("click", P, "reverse_points")
  check(controller().curve.reversed.circle == true and el(player, "reverse_points").toggled, "reverse flips the circle's direction")

  -- move mode: clicks move the centre there; right-click ends it
  dev("click", P, "move_curve")
  check(controller().ui.pointer_mode == "move", "move mode on")
  dev("pointer", P, { x = -10.5, y = 5.5 })
  check(active()[1].x == -10.5 and active()[1].y == 5.5 and active()[2].y == -4.5, "moved to the click")
  dev("pointer_remove", P, { x = 0, y = 0 })
  check(controller().ui.pointer_mode == nil and not el(player, "move_curve").toggled, "right-click ends move mode")

  check(el(player, "shape_info").caption[1] == "label.shape-info-circle" and el(player, "shape_info").caption[2] == "10.0", "radius shown")

  -- an ellipse: its width handle only counts by its distance from the first axis
  dev("select", P, "curve_kind", 3)
  dev("pointer", P, { x = 0, y = 0 })
  dev("pointer", P, { x = 20, y = 0 })
  dev("pointer", P, { x = 12, y = 6 })
  check(el(player, "shape_info").caption[2] == "20.0" and el(player, "shape_info").caption[3] == "6.0", "radii shown: 20 x 6")

  -- an arc: centre, start, end; then back to the curve, its points untouched
  dev("select", P, "curve_kind", 4)
  dev("pointer", P, { x = 0, y = 0 })
  dev("pointer", P, { x = 0, y = -15 })
  dev("pointer", P, { x = 30, y = 0 })
  check(#active() == 3 and not dev("plan", P).closed and #dev("plan", P).entities > 10, "arc planned")
  local info = el(player, "shape_info").caption
  check(info[2] == "15.0" and info[3] == "90", "arc shown as radius 15, 90 degrees (the end handle's distance doesn't count)")
  dev("select", P, "curve_kind", 1)
  check(controller().curve.kind == "catmull_rom" and el(player, "closed_loop").visible
    and #controller().curve.points == #spline and el(player, "cp_label_1").caption == "P1", "back to the curve, points kept")

  dev("click", P, "move_curve")
  dev("pointer", P, { x = 100, y = 100 })
  local p = controller().curve.points
  check(math.abs((p[1].x + p[3].x) / 2 - 100) < 0.01, "spline moved by its middle")
  dev("pointer", P, { x = 0, y = -17.5 })      -- back roughly where it was
  dev("pointer_remove", P, { x = 0, y = 0 })
  dev("click", P, "pointer_button")
end, "idle")

step("export and import the curve", function(player)
  local before = helpers.table_to_json(controller().curve)
  dev("click", P, "curve_export")
  local text = el(player, "curve_string").text
  check(#text > 20 and player.gui.screen.bezierio_string_window and player.opened == player.gui.screen.bezierio_string_window, "export string shown in its own window")
  player.opened = nil -- (Esc)
  check(not player.gui.screen.bezierio_string_window and player.gui.screen.bezierio_window, "Esc closes it, the main window stays")
  dev("click", P, "control_points_clear")
  check(point_count() == 0, "cleared")
  dev("click", P, "curve_import")
  check(not el(player, "curve_string") and el(player, "curve_import_text"), "import box replaces the export")
  el(player, "curve_import_text").text = "nonsense"
  dev("click", P, "curve_import_confirm")
  check(point_count() == 0, "bad string refused")
  el(player, "curve_import_text").text = text
  dev("click", P, "curve_import_confirm")
  check(point_count() == 3 and not player.gui.screen.bezierio_string_window and not el(player, "curve_import").toggled, "curve back, window closed")
  check(player.opened == player.gui.screen.bezierio_window, "the main window is the opened GUI again")
  check(helpers.table_to_json(controller().curve) == before, "exactly the same curve")
end)

step("clear points", function(player)
  dev("click", P, "control_points_clear")
  check(point_count() == 0, "cleared")
end, "idle")

step("cleared curve leaves nothing rendered", function(player)
  check(dev("render_count") == 0, "no sprites after clear: " .. dev("render_count"))
end)

flow.run("points")
