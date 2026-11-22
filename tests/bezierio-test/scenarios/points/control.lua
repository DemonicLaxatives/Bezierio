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

step("draw curve", function(player)
  dev("click", P, "draw_curve")
  check(controller().ui.draw_curve, "draw toggled on")
end, "idle")

step("curve rendered", function(player)
  check(dev("render_count") > 10, "curve sprites drawn: " .. dev("render_count"))
end)

step("closed loop", function(player)
  dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
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

flow.run("points")
