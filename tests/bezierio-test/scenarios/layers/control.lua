-- The layer list and detail pane, the view settings, and window state.
-- tests/run.sh layers
local flow = require("__bezierio-test__/lib/flow")
local P, dev, check, el, step = flow.P, flow.dev, flow.check, flow.el, flow.step
local controller, layers = flow.controller, flow.layers

step("setup + open window", function(player)
  flow.prepare_ground(player.surface)
  flow.open_window(player)
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
  check(offered["stone-wall"] and offered["small-electric-pole"] and offered["rail"], "walls, poles and rails offered in the picker")

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
  dev("set_checked", P, "red_wire", true)
  check(layers()[1].red_wire == true and not layers()[1].green_wire, "red wire on, green off")
  dev("set_checked", P, "green_wire", true)

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

step("mirror layers", function(player)
  local before = {}
  for k, layer in pairs(layers()) do before[k] = layer.type end
  dev("click", P, "layer_select_2")
  dev("click", P, "layer_mirror")
  for k, t in pairs(before) do
    check(layers()[-k].type == t and layers()[-k].idx == -k, "layer " .. k .. " is now layer " .. -k)
  end
  check(controller().ui.selected_layer == -2 and el(player, "layer_row_-2"), "selection follows")
  dev("click", P, "layer_mirror")
  check(layers()[2].type == "electric-turret" and controller().ui.selected_layer == 2, "mirrored back")
  dev("click", P, "layer_select_0")
end)

step("underlay option", function(player)
  dev("click", P, "layer_select_-1")
  dev("set_checked", P, "under", true)
  check(layers()[-1].under == true and el(player, "layer_label_-1").caption[1] == "label.layer-row-under", "tiles under")
  dev("set_checked", P, "under", false)
  check(layers()[-1].under == false and el(player, "layer_label_-1").caption[1] == "label.layer-row", "back beside")
  dev("click", P, "layer_select_0")
end)

step("presets", function(player)
  local function presets() return controller().presets end
  check(#presets() == 1 and el(player, "preset_delete").enabled == false, "one preset, can't be deleted")

  dev("click", P, "preset_copy")
  check(#presets() == 2 and controller().ui.preset_index == 2 and presets()[2].name == "Default 2", "copied and selected")
  dev("click", P, "preset_rename")
  dev("set_text", P, "preset_name", "Light")
  check(presets()[2].name == "Light" and el(player, "preset_select").get_item(2) == "Light", "renamed")
  dev("click", P, "layer_delete_2")
  dev("click", P, "layer_delete_1")
  check(layers()[1] == nil and presets()[1].layers[2].type == "electric-turret", "edits only change the selected preset")

  dev("select", P, "preset_select", 1)
  check(controller().ui.preset_index == 1 and el(player, "layer_row_2"), "switched back, its layers shown")

  -- export, then import the string as a new preset
  dev("click", P, "preset_export")
  local text = el(player, "preset_string").text
  check(#text > 20, "export string shown")
  dev("click", P, "preset_import")
  check(not el(player, "preset_string") and el(player, "preset_import_text"), "import box replaces export box")
  el(player, "preset_import_text").text = "not a preset"
  dev("click", P, "preset_import_confirm")
  check(#presets() == 2, "bad string refused")
  el(player, "preset_import_text").text = text
  dev("click", P, "preset_import_confirm")
  check(#presets() == 3 and controller().ui.preset_index == 3 and presets()[3].name == "Default 2", "imported and selected")
  local a, b = presets()[1].layers, presets()[3].layers
  check(b[2].type == "electric-turret" and b[2].spacing == a[2].spacing and b[-1].radius == a[-1].radius
    and b[1].red_wire == true and b[1].green_wire == true, "import matches the export")

  dev("click", P, "preset_delete")
  dev("click", P, "preset_delete")
  check(#presets() == 1 and presets()[1].name == "Default" and controller().ui.preset_index == 1, "deleted back to one")
  check(el(player, "preset_select").selected_index == 1, "bar shows it")
end, "idle")

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

step("close and reopen keeps state", function(player)
  dev("click", P, "draw_curve")
  player.opened = nil
  check(not player.gui.screen.bezierio_window, "window closed via on_gui_closed")
  flow.open_window(player)
  check(el(player, "draw_curve").toggled, "draw toggle restored")
  check(el(player, "layer_type").elem_value.name == "stone-wall", "layer type restored")
  check(el(player, "layer_row_2") and el(player, "layer_row_-1"), "layer rows restored")
end)

flow.run("layers")
