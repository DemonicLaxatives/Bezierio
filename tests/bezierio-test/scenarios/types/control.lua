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

local function clear_all(s)
  for _, e in pairs(s.find_entities_filtered { area = { { -80, -80 }, { 80, 80 } } }) do
    if e.type ~= "character" then e.destroy() end
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
  dev("set_elem", P, "ammo", "rocket")
  check(layers()[-1].ammo == nil and el(player, "ammo").elem_value == nil, "rockets refused for a gun turret")
  dev("set_elem", P, "ammo", "firearm-magazine")
  check(layers()[-1].ammo == "firearm-magazine" and el(player, "ammo_count_slider"), "magazines accepted, count shown")
  dev("set_value", P, "ammo_count_slider", 25)
  dev("set_value", P, "spacing_slider", 6)

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
  clear_all(s)
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("instant: loaded turrets, red lamps", function(player)
  local s = player.surface
  local guns = s.find_entities_filtered { name = "gun-turret" }
  check(#guns > 5, "gun turrets built")
  for _, t in pairs(guns) do
    check(t.get_item_count("firearm-magazine") == 25, "loaded with 25 magazines: " .. t.get_item_count("firearm-magazine"))
  end
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

flow.run("types")
