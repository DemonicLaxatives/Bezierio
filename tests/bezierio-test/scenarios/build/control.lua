-- Preview, totals and building: ghosts, superforced, cheat mode, map editor,
-- wiring, undo, underlays, permissions.
-- tests/run.sh build
local flow = require("__bezierio-test__/lib/flow")
local P, dev, check, el, step = flow.P, flow.dev, flow.check, flow.el, flow.step
local controller, layers = flow.controller, flow.layers
local ghosts, planned_walls, count_planned, wall_components = flow.ghosts, flow.planned_walls, flow.count_planned, flow.wall_components

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

step("setup: curve and layers", function(player)
  flow.prepare_ground(player.surface)
  flow.open_window(player)
  flow.standard_curve()
  flow.standard_layers()
  check(flow.point_count() == 3 and layers()[2].type == "electric-turret", "set up")
  storage.before = dev("render_count")
  dev("click", P, "draw_curve")
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

step("instant build in cheat mode", function(player)
  local s = player.surface
  flow.clear_build(s)
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
  flow.clear_build(s)
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
  flow.clear_build(s)
  dev("click", P, "layer_select_-1")
  dev("set_checked", P, "under", true)
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
  flow.clear_build(s)
end)

step("blueprint", function(player)
  flow.clear_build(player.surface)
  dev("click", P, "blueprint_build")
end, "idle")

step("blueprint in the cursor, snaps onto the plan", function(player)
  local stack = player.cursor_stack
  local plan = dev("plan", P)
  check(stack.valid_for_read and stack.is_blueprint and stack.is_blueprint_setup(), "blueprint in cursor")
  check(stack.get_blueprint_entity_count() == #plan.entities, "all entities: " .. stack.get_blueprint_entity_count() .. "/" .. #plan.entities)
  check(#stack.get_blueprint_tiles() == #plan.tiles, "all tiles")
  check(stack.blueprint_absolute_snapping == true and stack.label:find("Default", 1, true), "absolute snapping, labelled")
  local wired_poles = 0
  for _, e in pairs(stack.get_blueprint_entities()) do
    if e.name == "small-electric-pole" and e.wires and #e.wires >= 3 then wired_poles = wired_poles + 1 end
  end
  check(wired_poles > 0, "poles wired copper, red and green")

  -- Stamp it where the preview is: every ghost must land on its planned spot.
  local s = player.surface
  stack.build_blueprint { surface = s, force = player.force, position = plan.entities[1].position, build_mode = defines.build_mode.forced }
  local missing = 0
  for _, e in pairs(plan.entities) do
    if not s.find_entities_filtered { ghost_name = e.name, position = e.position, limit = 1 }[1] then missing = missing + 1 end
  end
  check(missing == 0, "ghosts on the planned spots, missing " .. missing .. "/" .. #plan.entities)
  local tile_ghosts = #s.find_entities_filtered { type = "tile-ghost" }
  check(tile_ghosts == #plan.tiles, "tile ghosts on the plan: " .. tile_ghosts .. "/" .. #plan.tiles)
  player.clear_cursor()
  flow.clear_build(s)
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

flow.run("build")
