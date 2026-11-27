-- Belts and pipes: continuous lines, undergrounds, pumps, ghosts and real
-- entities, blueprints. tests/run.sh paths
local flow = require("__bezierio-test__/lib/flow")
local P, dev, check, el, step = flow.P, flow.dev, flow.check, flow.el, flow.step
local layers = flow.layers

local function clear_all(s)
  for _, e in pairs(s.find_entities_filtered { area = { { -80, -80 }, { 80, 80 } } }) do
    if e.type ~= "character" then e.destroy() end
  end
end

step("setup: belts and pipes along a bend", function(player)
  flow.prepare_ground(player.surface)
  flow.open_window(player)
  dev("click", P, "pointer_button")
  dev("pointer", P, { x = -50.5, y = -30.5 })
  dev("pointer", P, { x = 10.5, y = -20.5 })
  dev("pointer", P, { x = 40.5, y = 30.5 })
  dev("click", P, "pointer_button")
  dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })

  dev("click", P, "add_layer_above")
  dev("set_elem", P, "layer_type", { name = "transport-belt", quality = "normal" })
  check(layers()[1].type == "belt" and layers()[1].underground_name == "underground-belt", "belt layer, knows its underground")
  check(el(player, "lines_slider") and el(player, "flow") and el(player, "undergrounds"), "belt settings shown")
  dev("set_value", P, "lines_slider", 2)
  dev("set_checked", P, "undergrounds", true)

  dev("click", P, "add_layer_below")
  dev("set_elem", P, "layer_type", { name = "pipe", quality = "normal" })
  check(layers()[-1].type == "pipe" and layers()[-1].underground_name == "pipe-to-ground" and layers()[-1].pump_name == "pump", "pipe layer")
  check(not el(player, "pump_spacing_slider") and not el(player, "pump"), "pump spacing and pump picker hidden until pumps are on")
  check(layers()[-1].pipeline_extent == 320, "pipeline extent from the pipe's fluidbox: " .. tostring(layers()[-1].pipeline_extent))
  dev("set_value", P, "lines_slider", 2)
  dev("set_checked", P, "undergrounds", true)
  dev("set_checked", P, "pumps", true)
  -- The pump picker: the base game's pump by default; one that doesn't fit in a
  -- pipe line (a test 2x2) is refused
  check(el(player, "pump") and el(player, "pump").elem_value == "pump" and layers()[-1].pump == "pump"
    and layers()[-1].pump_length == 2, "pump picker shows the base pump, 1x2: " .. tostring(layers()[-1].pump_length))
  dev("set_elem", P, "pump", "bezierio-test-wide-pump")
  check(layers()[-1].pump == "pump" and el(player, "pump").elem_value == "pump", "a 2x2 pump refused")
  check(layers()[-1].pump_spacing == 318 and el(player, "pump_spacing_slider").get_slider_maximum() == 318,
    "pump spacing defaults to and stops at the extent less the pump: " .. layers()[-1].pump_spacing)
  dev("set_value", P, "pump_spacing_slider", 40)
  dev("click", P, "layer_select_0")
  dev("click", P, "preview_build")
end, "idle")

step("totals list undergrounds and pumps, arrows show the way", function(player)
  local arrows = 0
  for _, o in pairs(rendering.get_all_objects("Bezierio")) do if o.type == "polygon" then arrows = arrows + 1 end end
  check(arrows > 20, "direction arrows in the preview: " .. arrows)
  local caption = el(player, "totals_items").caption
  check(caption:find("[item=underground-belt]", 1, true) and caption:find("[item=pipe-to-ground]", 1, true)
    and caption:find("[item=pump]", 1, true), "totals: " .. caption)
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("real belts flow, undergrounds pair up", function(player)
  local s = player.surface
  local plan = dev("plan", P)
  local belts = s.find_entities_filtered { name = "transport-belt" }
  local undergrounds = s.find_entities_filtered { name = "underground-belt" }
  check(#belts > 50 and #undergrounds >= 4, "belts " .. #belts .. ", undergrounds " .. #undergrounds)
  for _, u in pairs(undergrounds) do
    local partner = u.underground_belt_neighbour
    check(partner and partner.valid and partner.belt_to_ground_type ~= u.belt_to_ground_type, "underground at " .. u.position.x .. "," .. u.position.y .. " is paired")
  end
  -- Follow each line from its start: every belt leads on to the next part of the line.
  local starts = 0
  for _, b in pairs(belts) do
    if #b.belt_neighbours.inputs == 0 then starts = starts + 1 end
  end
  check(starts == 2, "two belt lines, each starting once: " .. starts)
  local planned = 0
  for _, e in pairs(plan.entities) do if e.layer == 1 then planned = planned + 1 end end
  check(#belts + #undergrounds == planned, "everything planned was built: " .. (#belts + #undergrounds) .. "/" .. planned)
end)

step("a belt turned round isn't counted as built", function(player)
  local s = player.surface
  for _, e in pairs(dev("plan", P).entities) do
    if e.name == "transport-belt" then storage.turned = e break end
  end
  local belt = s.find_entity("transport-belt", storage.turned.position)
  belt.direction = (storage.turned.direction + 8) % 16
  storage.belt_count = s.count_entities_filtered { name = "transport-belt" }
  dev("click", P, "build")
end, "idle")

step("... a normal build leaves it", function(player)
  local s = player.surface
  local belt = s.find_entity("transport-belt", storage.turned.position)
  check(belt and belt.direction ~= storage.turned.direction, "left facing the other way")
  check(s.count_entities_filtered { name = "transport-belt" } == storage.belt_count, "nothing else built")
  dev("click", P, "super_build")
end, "idle")

step("... super force turns it back", function(player)
  local s = player.surface
  local belt = s.find_entity("transport-belt", storage.turned.position)
  check(belt and belt.direction == storage.turned.direction, "facing the planned way")
  check(s.count_entities_filtered { name = "transport-belt" } == storage.belt_count, "the same belts")
  -- with ghosts: marked for deconstruction, a ghost facing the planned way
  player.cheat_mode = false
  belt.direction = (storage.turned.direction + 8) % 16
  dev("click", P, "super_build")
end, "idle")

step("... with ghosts: replaced by a ghost", function(player)
  local s = player.surface
  local belt = s.find_entity("transport-belt", storage.turned.position)
  local ghost = s.find_entities_filtered { ghost_name = "transport-belt", position = storage.turned.position, limit = 1 }[1]
  check(belt and belt.to_be_deconstructed(), "the turned belt is marked for deconstruction")
  check(ghost and ghost.direction == storage.turned.direction, "a ghost facing the planned way")
  check(#s.find_entities_filtered { type = "entity-ghost" } == 1, "no other ghosts")
  if ghost then ghost.destroy() end
  belt.cancel_deconstruction(player.force)
  belt.direction = storage.turned.direction
  player.cheat_mode = true
end)

step("real pipes: two networks, split by the pumps", function(player)
  local s = player.surface
  local pumps = s.find_entities_filtered { name = "pump" }
  check(#pumps >= 2, "pumps built: " .. #pumps)
  -- Fluid segments: pumps separate segments; the two lines never share one.
  local segments_by_line = {}
  local pipes = s.find_entities_filtered { name = { "pipe", "pipe-to-ground" } }
  check(#pipes > 40, "pipes built: " .. #pipes)
  local ids = {}
  for _, p in pairs(pipes) do ids[p.get_fluid_segment_id(1)] = true end
  local segments = 0
  for _ in pairs(ids) do segments = segments + 1 end
  check(segments == 2 + #pumps, "pipe segments: 2 lines + 1 per pump = " .. (2 + #pumps) .. ", got " .. segments)
  player.cheat_mode = false
  clear_all(s)
  dev("click", P, "build")
end, "idle")

step("ghosts: underground types and pump directions", function(player)
  local s = player.surface
  local ins, outs = 0, 0
  for _, g in pairs(s.find_entities_filtered { ghost_name = "underground-belt" }) do
    if g.belt_to_ground_type == "input" then ins = ins + 1 else outs = outs + 1 end
  end
  check(ins > 0 and ins == outs, "underground ghosts in pairs: " .. ins .. " in, " .. outs .. " out")
  check(#s.find_entities_filtered { ghost_name = "pump" } >= 2, "pump ghosts")
  clear_all(s)
  dev("click", P, "blueprint_build")
end, "idle")

step("blueprint keeps underground types", function(player)
  local stack = player.cursor_stack
  local ins, outs = 0, 0
  for _, e in pairs(stack.get_blueprint_entities()) do
    if e.name == "underground-belt" then
      if e.type == "input" then ins = ins + 1 elseif e.type == "output" then outs = outs + 1 end
    end
  end
  check(ins > 0 and ins == outs, "blueprint undergrounds: " .. ins .. " in, " .. outs .. " out")
  player.clear_cursor()
end)

step("another pump: a 1x3 one in the lines", function(player)
  clear_all(player.surface)
  dev("click", P, "layer_select_-1")
  dev("set_elem", P, "pump", "bezierio-test-long-pump")
  local layer = layers()[-1]
  check(layer.pump == "bezierio-test-long-pump" and layer.pump_name == "bezierio-test-long-pump" and layer.pump_length == 3,
    "1x3 pump chosen: " .. tostring(layer.pump_length))
  check(el(player, "pump_spacing_slider").get_slider_maximum() == 317, "spacing stops at the extent less the longer pump")
  dev("click", P, "layer_select_0")
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("1x3 pumps join their lines", function(player)
  local s = player.surface
  local pumps = s.find_entities_filtered { name = "bezierio-test-long-pump" }
  check(#pumps >= 2 and s.count_entities_filtered { name = "pump" } == 0, "1x3 pumps built, no base ones: " .. #pumps)
  for _, p in pairs(pumps) do
    local names = {}
    for _, n in pairs(p.get_fluid_box_neighbours(1) or {}) do names[#names + 1] = n.entity.name end
    check(#names == 2, "pump at " .. p.position.x .. "," .. p.position.y .. " connected at both ends: " .. table.concat(names, " "))
  end
  local ids = {}
  for _, p in pairs(s.find_entities_filtered { name = { "pipe", "pipe-to-ground" } }) do ids[p.get_fluid_segment_id(1)] = true end
  local segments = 0
  for _ in pairs(ids) do segments = segments + 1 end
  check(segments == 2 + #pumps, "pipe segments: 2 lines + 1 per pump = " .. (2 + #pumps) .. ", got " .. segments)
  player.cheat_mode = false
end)

flow.run("paths")
