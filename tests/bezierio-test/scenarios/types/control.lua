-- The spaced and scattered layer types: turrets (facing, ammo), lamps, land mines,
-- radars, solar panels, accumulators. tests/run.sh types
local flow = require("__bezierio-test__/lib/flow")
local P, dev, check, el, step = flow.P, flow.dev, flow.check, flow.el, flow.step
local layers = flow.layers

local function on_layer(plan, idx)
  local out = {}
  for _, e in pairs(plan.entities) do if e.layer == idx then table.insert(out, e) end end
  return out
end

local function clear_all(s, keep_ghosts_of)
  for _, e in pairs(s.find_entities_filtered { area = { { -80, -80 }, { 80, 80 } } }) do
    if e.type ~= "character" and not (keep_ghosts_of and e.type == "entity-ghost" and e.ghost_name == keep_ghosts_of) then
      e.destroy()
    end
  end
end

step("setup: a straight curve east", function(player)
  flow.prepare_ground(player.surface)
  flow.open_window(player)
  dev("click", P, "pointer_button")
  dev("pointer", P, { x = -40.5, y = 0.5 })
  dev("pointer", P, { x = 40.5, y = 0.5 })
  dev("click", P, "pointer_button")
  dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
end)

--- The item names a picker offers (its elem_filters, as the game hands them back).
local function picker_offers(player, name)
  local set = {}
  for _, f in pairs(el(player, name).elem_filters or {}) do
    for _, n in pairs(type(f.name) == "table" and f.name or { f.name }) do set[n] = true end
  end
  return set
end

step("the layer item picker offers what the force has unlocked", function(player)
  local artillery = player.force.technologies["artillery"]
  local picker = el(player, "layer_type")
  local offers = picker_offers(player, "layer_type")
  check(offers["transport-belt"] and offers["stone-wall"], "belts, and the wall the layer holds, offered")
  check(not offers["artillery-turret"], "artillery turrets not offered before artillery is researched")
  artillery.researched = true
  check(picker.valid, "the picker is updated in place, not rebuilt")
  check(picker_offers(player, "layer_type")["artillery-turret"], "artillery turrets offered once researched")
  artillery.researched = false
  check(not picker_offers(player, "layer_type")["artillery-turret"], "and gone again when the research is undone")
end)

step("pick the new types", function(player)
  local offered = {}
  for _, n in pairs(dev("item_filter")[1].name) do offered[n] = true end
  for _, item in ipairs({ "gun-turret", "flamethrower-turret", "artillery-turret", "small-lamp", "land-mine", "radar", "solar-panel", "accumulator" }) do
    check(offered[item], item .. " offered in the picker")
  end

  -- L1: flamethrowers face outward (south, on this curve)
  dev("click", P, "add_layer_above")
  dev("set_elem", P, "layer_type", { name = "flamethrower-turret", quality = "normal" })
  check(layers()[1].type == "turret" and layers()[1].turn_limited and el(player, "facing") and not el(player, "ammo"), "flamethrower: facing, no ammo")
  dev("set_value", P, "spacing_slider", 8)

  -- L-1: gun turrets with ammo
  dev("click", P, "add_layer_below")
  dev("set_elem", P, "layer_type", { name = "gun-turret", quality = "normal" })
  check(not el(player, "facing") and el(player, "ammo"), "gun turret: ammo, no facing")
  check(picker_offers(player, "ammo")["firearm-magazine"] and not picker_offers(player, "ammo")["rocket"],
    "ammo picker: magazines, no rockets before rocketry")
  dev("set_elem", P, "ammo", "rocket")
  check(layers()[-1].ammo == nil and el(player, "ammo").elem_value == nil, "rockets refused for a gun turret")
  dev("set_elem", P, "ammo", "firearm-magazine")
  check(layers()[-1].ammo == "firearm-magazine" and el(player, "ammo_count_slider"), "magazines accepted, count shown")
  dev("set_value", P, "ammo_count_slider", 25)
  dev("set_value", P, "spacing_slider", 6)
  -- targeting priorities: a slot per entry, one more to add
  check(el(player, "priority_targets_1") and not el(player, "priority_targets_2") and not el(player, "ignore_unprioritised"), "one empty priority slot")
  dev("set_elem", P, "priority_targets_1", "small-biter")
  dev("set_elem", P, "priority_targets_2", "medium-spitter")
  check(layers()[-1].priority_targets[2] == "medium-spitter" and el(player, "priority_targets_3"), "two targets, a third slot")
  dev("set_elem", P, "priority_targets_1", nil)
  check(#layers()[-1].priority_targets == 1 and layers()[-1].priority_targets[1] == "medium-spitter", "clearing a slot closes the gap")
  dev("set_elem", P, "priority_targets_2", "small-biter")
  dev("set_checked", P, "ignore_unprioritised", true)
  check(layers()[-1].ignore_unprioritised == true, "only these targets")

  -- L2: red lamps; L-2: wired mines
  dev("click", P, "add_layer_above")
  dev("set_elem", P, "layer_type", { name = "small-lamp", quality = "normal" })
  check(not el(player, "rainbow_length_slider"), "rainbow length hidden")
  dev("select", P, "color", 5) -- red: default, white, grey, black, red
  check(layers()[2].color == "red", "lamp colour red: " .. tostring(layers()[2].color))
  dev("click", P, "add_layer_below")
  dev("set_elem", P, "layer_type", { name = "land-mine", quality = "normal" })
  check(el(player, "density_slider") and not el(player, "mine_spacing_slider"), "scattered: density shown")
  dev("select", P, "pattern", 2)
  check(layers()[-2].pattern == "grid" and el(player, "mine_spacing_slider") and not el(player, "density_slider"), "grid: spacing shown")
  dev("select", P, "pattern", 1)
  dev("set_value", P, "density_slider", 30)
  dev("set_value", P, "radius_slider", 3)
  dev("set_checked", P, "red_wire", true)
  check(layers()[-2].type == "land-mine" and layers()[-2].circuit_distance > 0, "mines, with wire reach")

  -- radar spacing follows its range
  dev("click", P, "add_layer_above")
  dev("set_elem", P, "layer_type", { name = "radar", quality = "normal" })
  check(layers()[3].spacing == 192, "radar spacing from its range: " .. layers()[3].spacing)
  dev("set_elem", P, "layer_type", { name = "solar-panel", quality = "normal" })
  check(layers()[3].type == "solar-panel", "solar panels")
  dev("click", P, "layer_select_0")
end)

step("force build ghosts", function(player)
  dev("click", P, "preview_build")
  dev("click", P, "build")
end, "idle")

step("ghosts face, request ammo, are wired", function(player)
  local s = player.surface
  local plan = dev("plan", P)
  local guns_planned = #on_layer(plan, -1)
  check(el(player, "totals_items").caption:find("[item=firearm-magazine]×" .. (25 * guns_planned), 1, true),
    "ammo in the totals: " .. el(player, "totals_items").caption)
  local flamers = s.find_entities_filtered { ghost_name = "flamethrower-turret" }
  check(#flamers == #on_layer(plan, 1) and #flamers > 5, "flamethrower ghosts: " .. #flamers)
  for _, g in pairs(flamers) do check(g.direction == defines.direction.south, "flamethrower faces south (outward)") end
  local guns = s.find_entities_filtered { ghost_name = "gun-turret" }
  check(#guns > 5, "gun turret ghosts")
  for _, g in pairs(guns) do
    local req = g.item_requests[1]
    check(req and req.name == "firearm-magazine" and req.count == 25, "gun turret ghost requests 25 magazines")
    local targets = g.priority_targets
    check(#targets == 2 and targets[1].name == "medium-spitter" and targets[2].name == "small-biter" and g.ignore_unprioritised_targets, "ghost has the priorities")
  end
  local mines = s.find_entities_filtered { ghost_name = "land-mine" }
  check(#mines > 20, "mine ghosts: " .. #mines)
  local wired, green = 0, 0
  for _, m in pairs(mines) do
    local c = m.get_wire_connector(defines.wire_connector_id.circuit_red, false)
    if c and c.connection_count > 0 then wired = wired + 1 end
    local g = m.get_wire_connector(defines.wire_connector_id.circuit_green, false)
    if g and g.connection_count > 0 then green = green + 1 end
  end
  check(wired > #mines * 0.8 and green == 0, "mine ghosts wired red only: " .. wired .. "/" .. #mines .. ", green " .. green)
  check(#s.find_entities_filtered { ghost_name = "small-lamp" } == #on_layer(plan, 2), "lamp ghosts")
  check(#s.find_entities_filtered { ghost_name = "solar-panel" } == #on_layer(plan, 3), "solar panel ghosts")
  clear_all(s, "gun-turret") -- (the gun turret ghosts get revived)
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("instant: loaded turrets, red lamps", function(player)
  local s = player.surface
  local guns = s.find_entities_filtered { name = "gun-turret" }
  check(#guns > 5, "gun turrets built")
  for _, t in pairs(guns) do
    check(t.get_item_count("firearm-magazine") == 25, "loaded with 25 magazines: " .. t.get_item_count("firearm-magazine"))
    check(#t.priority_targets == 2 and t.ignore_unprioritised_targets, "built with the priorities")
  end
  check(#s.find_entities_filtered { type = "entity-ghost" } == 0, "the gun turret ghosts were revived")
  check(#s.find_entities_filtered { type = "item-request-proxy" } == 0, "no ammo request left over")
  for _, lamp in pairs(s.find_entities_filtered { name = "small-lamp" }) do
    check(lamp.color and lamp.color.r > 0.9 and lamp.color.g < 0.2, "lamp is red")
  end
  for _, f in pairs(s.find_entities_filtered { name = "flamethrower-turret" }) do
    check(f.direction == defines.direction.south, "flamethrower built facing south")
  end
  player.cheat_mode = false
  clear_all(s)
  dev("click", P, "blueprint_build")
end, "idle")

step("blueprint keeps facing, ammo and colour", function(player)
  local stack = player.cursor_stack
  check(stack.valid_for_read and stack.is_blueprint, "blueprint in cursor")
  local faced, loaded, colored, wired = 0, 0, 0, 0
  for _, e in pairs(stack.get_blueprint_entities()) do
    if e.name == "flamethrower-turret" and e.direction == defines.direction.south then faced = faced + 1 end
    if e.name == "gun-turret" and e.items and e.items[1] and e.items[1].id.name == "firearm-magazine" then loaded = loaded + 1 end
    if e.name == "small-lamp" and e.color and e.color.r > 0.9 then colored = colored + 1 end
    if e.name == "land-mine" and e.wires and #e.wires > 0 then wired = wired + 1 end
    if e.name == "gun-turret" then
      local list = e["priority-list"]
      check(list and #list == 2 and list[1].name == "medium-spitter" and e["ignore-unprioritised"] == true, "priorities in the blueprint")
    end
  end
  check(faced > 5 and loaded > 5 and wired > 10, string.format("facing %d, ammo %d, wired mines %d", faced, loaded, wired))
  log("blueprint lamps with colour: " .. colored)
  check(colored > 0, "lamp colours in the blueprint")
  player.clear_cursor()
end)

step("diagonal flamethrowers", function(player)
  local s = player.surface
  clear_all(s)
  dev("click", P, "control_points_clear")
  dev("click", P, "pointer_button")
  dev("pointer", P, { x = -30.5, y = -30.5 })
  dev("pointer", P, { x = 30.5, y = 30.5 })
  dev("click", P, "pointer_button")
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("diagonal flamethrowers built where planned", function(player)
  local s = player.surface
  local planned = on_layer(dev("plan", P), 1)
  check(#planned > 3, "flamethrowers planned")
  for _, e in pairs(planned) do
    check(e.direction == defines.direction.southwest, "planned facing south-west: " .. tostring(e.direction))
    local built = s.find_entity("flamethrower-turret", e.position)
    check(built and built.direction == defines.direction.southwest, "built at " .. e.position.x .. "," .. e.position.y .. ", facing south-west")
  end
  player.cheat_mode = false
end)

step("a layer that isn't placed keeps its room", function(player)
  local before = dev("plan", P)
  if player.gui.screen.bezierio_layer_window then dev("click", P, "layer_ok") end
  check(el(player, "layer_place_1").toggled and not el(player, "place"), "placed by default, toggled in the list")
  dev("click", P, "layer_place_1")
  local after = dev("plan", P)
  check(#on_layer(before, 1) > 5 and #on_layer(after, 1) == 0, "nothing planned on it")
  local a, b = on_layer(before, 2), on_layer(after, 2)
  local same = #a == #b
  for i = 1, #a do same = same and b[i] and a[i].position.x == b[i].position.x and a[i].position.y == b[i].position.y end
  check(same and #a > 0, "the layer outside it where it was")
  local label = el(player, "layer_label_1")
  check(label.tooltip and label.tooltip[1] == "tooltip.layer-not-placed" and label.style.font_color.r < 0.6, "the list says so: greyed, with a tooltip")
  check(not el(player, "layer_place_1").toggled, "the toggle shows it")
  dev("click", P, "layer_place_1")
  check(layers()[1].place == nil and #on_layer(dev("plan", P), 1) > 5, "placed again")
end)

-- Railguns (Space Age): 3x5 and facing 8 ways, so they don't fill their square;
-- every inserter has to drop into the turret itself (it once never did).
local RAILGUN_PRESET = {
  format = "bezierio-preset", version = 1, name = "railguns",
  layers = {
    { idx = -2, offset = 0, item = "turbo-transport-belt", quality = "normal", lines = 1, line_gap = 0, flow = "forward", undergrounds = false },
    { idx = -1, offset = 0, item = "medium-electric-pole", quality = "normal", spacing = 8, smart = true, red_wire = false, green_wire = false },
    { idx = 0, offset = 0, item = "railgun-turret", quality = "normal", spacing = 5, facing = "outward", inserter = "inserter", pipe_feed = false, ammo_count = 10 },
  },
}

step("railguns: fed from the belt", function(player)
  if not prototypes.entity["railgun-turret"] then return log("railguns: no Space Age, skipped") end
  local s = player.surface
  clear_all(s)
  for _, t in pairs({ "railgun", "turbo-transport-belt" }) do
    if player.force.technologies[t] then player.force.technologies[t].researched = true end
  end
  if player.gui.screen.bezierio_layer_window then dev("click", P, "layer_ok") end
  dev("click", P, "preset_import")
  el(player, "preset_import_text").text = helpers.encode_string(helpers.table_to_json(RAILGUN_PRESET))
  dev("click", P, "preset_import_confirm")
  check(layers()[0].name == "railgun-turret" and layers()[0].inserter == "inserter", "railgun preset imported")
  dev("click", P, "control_points_clear")
  dev("click", P, "pointer_button")
  -- straight, then bending through the diagonals (the curve of the bug report)
  dev("pointer", P, { x = -40.5, y = -30.5 })
  dev("pointer", P, { x = -10.5, y = 12.5 })
  dev("pointer", P, { x = 30.5, y = 20.5 })
  dev("pointer", P, { x = 50.5, y = 50.5 })
  dev("click", P, "pointer_button")
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("railguns: every inserter drops into a railgun", function(player)
  if not prototypes.entity["railgun-turret"] then return end
  local s = player.surface
  local plan = dev("plan", P)
  local guns = s.find_entities_filtered { name = "railgun-turret" }
  local inserters = s.find_entities_filtered { name = "inserter" }
  local facings = {}
  for _, g in pairs(guns) do facings[g.direction] = true end
  local n = 0
  for _ in pairs(facings) do n = n + 1 end
  local fed_by = {}
  for _, ins in pairs(inserters) do if ins.drop_target then fed_by[ins.drop_target.unit_number] = true end end
  local per = {}
  for _, g in pairs(guns) do
    per[g.direction] = per[g.direction] or { 0, 0 }
    per[g.direction][fed_by[g.unit_number] and 1 or 2] = per[g.direction][fed_by[g.unit_number] and 1 or 2] + 1
  end
  log("railguns: (fed, unfed) per facing " .. serpent.line(per) .. " inserters " .. #inserters .. " unfed " .. plan.unfed)
  check(#guns > 8 and n >= 2, "railguns built facing straight and diagonally: " .. #guns .. ", " .. n .. " facings")
  -- Straight, every one is fed; on a diagonal the body leaves a gap to the belt
  -- that a straight inserter can't always bridge (those are counted unfed).
  for d, counts in pairs(per) do
    if d % 4 == 0 then check(counts[2] == 0, "facing " .. d .. ": every railgun fed (" .. counts[1] .. ")") end
  end
  for _, ins in pairs(inserters) do
    check(ins.drop_target and ins.drop_target.name == "railgun-turret",
      "inserter at " .. ins.position.x .. "," .. ins.position.y .. " drops into a railgun")
    check(s.find_entities_filtered { position = ins.pickup_position, name = "turbo-transport-belt", limit = 1 }[1],
      "inserter at " .. ins.position.x .. "," .. ins.position.y .. " picks up from the belt")
  end
  check(#inserters + plan.unfed == #guns and #inserters >= #guns / 2,
    "railguns fed: " .. #inserters .. ", counted unfed: " .. plan.unfed .. ", of " .. #guns)
  player.cheat_mode = false
end)

flow.run("types")
