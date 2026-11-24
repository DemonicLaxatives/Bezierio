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

step("planning shows progress in the summary pane", function(player)
  dev("set_value", P, "radius_slider", layers()[0].radius)
end)

step("... a progress line and bar, no summary", function(player)
  local length, bar = el(player, "totals_length"), el(player, "totals_progress")
  check(el(player, "totals").visible and bar.visible, "pane and bar shown while planning")
  check(type(length.caption) == "table" and length.caption[1] == "label.status-planning", "says planning")
  check(not el(player, "totals_items").visible and not el(player, "status").visible, "no summary, no separate status line")
end, "idle")

step("preview rendered, totals shown", function(player)
  check(not el(player, "totals_progress").visible and el(player, "totals_length").caption[1] == "label.totals", "summary back")
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

step("hide a layer in the preview", function(player)
  storage.shown = dev("render_count")
  check(el(player, "layer_preview_-1").toggled, "the eye is pressed: shown")
  dev("click", P, "layer_preview_-1")
  check(layers()[-1].preview == false and not el(player, "layer_preview_-1").toggled and controller().work.plan ~= nil, "hidden, no replanning")
end, "idle")

step("hidden layer not drawn, shown again", function(player)
  local now = dev("render_count")
  check(now < storage.shown - 20, "fewer objects with the tiles hidden: " .. now .. " < " .. storage.shown)
  dev("click", P, "layer_preview_-1")
  check(layers()[-1].preview == nil, "shown again")
  -- With the quality mod, the layer button shows the layer's quality.
  if prototypes.quality["rare"] then
    dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "rare" })
    local button = el(player, "layer_select_0")
    check(button.quality and button.quality.name == "rare", "quality shown on the layer button")
    dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
  end
end, "idle")

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
  -- super force clears what's in the way, but not items on the ground or corpses
  local spot = s.find_entities_filtered { name = "stone-wall", limit = 40 }[40].position
  storage.wall_spot = spot
  storage.dropped = s.create_entity { name = "item-on-ground", position = spot, stack = { name = "iron-plate", count = 5 } }
  storage.corpse = s.create_entity { name = "character-corpse", position = spot, inventory_size = 10 }
  storage.corpse.get_inventory(defines.inventory.character_corpse).insert { name = "iron-plate", count = 5 }
  check(storage.dropped and storage.corpse, "item on the ground and a corpse placed")
  dev("click", P, "super_build")
end, "idle")

step("cheat mode superforced", function(player)
  local s = player.surface
  local planned = count_planned(dev("plan", P))
  check(not storage.chest2.valid, "chest removed by superforced build")
  check(storage.dropped.valid, "item on the ground left alone")
  check(storage.corpse.valid, "corpse left alone")
  storage.dropped.destroy()
  storage.corpse.destroy()
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

step("smart poles", function(player)
  flow.clear_build(player.surface)
  storage.spaced_poles = flow.count_planned(dev("plan", P))["small-electric-pole"]
  dev("click", P, "layer_select_1")
  dev("set_checked", P, "smart", true)
  check(layers()[1].smart == true and not el(player, "spacing_slider").enabled, "smart on, spacing greyed out")
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("smart poles power every turret", function(player)
  local s = player.surface
  local plan = dev("plan", P)
  check(plan.unpowered == 0, "nothing reported unpowered: " .. plan.unpowered)
  local turrets = s.find_entities_filtered { name = "laser-turret" }
  check(#turrets > 0, "turrets built")
  -- In some pole's supply area (is_connected_to_electric_network also wants a
  -- power source, and this map has none).
  for _, t in pairs(turrets) do
    check(t.electric_network_id ~= nil, "turret at " .. t.position.x .. "," .. t.position.y .. " is on the network")
  end
  local poles = s.count_entities_filtered { name = "small-electric-pole" }
  log("smart poles: " .. poles .. " (spacing 6: " .. storage.spaced_poles .. ") for " .. #turrets .. " turrets")
  player.cheat_mode = false
  dev("set_checked", P, "smart", false)
  dev("click", P, "layer_select_0")
  flow.clear_build(s)
end)

step("queue: a command waits for the running build", function(player)
  flow.clear_build(player.surface)
  dev("set_budget", 200) -- (a build over several ticks)
end, "idle")

step("... force build", function(player)
  dev("click", P, "build")
end)

step("... a build running, Blueprint queued behind it", function(player)
  local w = controller().work
  check(w.build ~= nil, "build running: pending " .. tostring(w.pending_build) .. " plan " .. tostring(w.plan and w.plan.plan.done) .. " preview " .. tostring(controller().ui.preview_build))
  dev("click", P, "blueprint_build")
  check(controller().work.pending_build == "blueprint" and controller().work.build.kind ~= "blueprint", "blueprint queued, the build carries on")
end)

step("...", function(player) end)

step("... the progress line names both, cancel stops them", function(player)
  local caption = el(player, "totals_length").caption
  check(type(caption) == "table" and caption[4] and caption[4][1] == "label.status-next", "the next command shown: " .. serpent.line(caption))
  check(el(player, "build_cancel").visible and el(player, "totals_progress").visible, "progress bar and cancel button shown")
  dev("click", P, "build_cancel")
  check(controller().work.build == nil and controller().work.pending_build == nil, "cancelled")
  dev("set_budget", 1000)
end, "idle")

step("... cancelled: the summary is back", function(player)
  check(not el(player, "build_cancel").visible and el(player, "totals_length").caption[1] == "label.totals", "summary back, no cancel button")
  check(not player.cursor_stack.valid_for_read, "no blueprint made")
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
  -- The curve and preset it was made from: tags on the first entity, and a note.
  local source = stack.get_blueprint_entity_tag(1, "bezierio")
  local curve_data = source and helpers.json_to_table(helpers.decode_string(source.curve))
  local preset_data = source and helpers.json_to_table(helpers.decode_string(source.preset))
  check(curve_data and curve_data.format == "bezierio-curve" and #curve_data.points == #controller().curve.points, "curve carried in the blueprint")
  check(preset_data and preset_data.format == "bezierio-preset" and #preset_data.layers > 1, "preset carried in the blueprint")
  check(stack.blueprint_description:find("Bézierio", 1, true), "a note in the description")
  flow.clear_build(s)
  -- Load them back: the curve replaced, the preset added and selected.
  storage.points = #controller().curve.points
  storage.preset_count = #controller().presets
  dev("click", P, "control_points_clear")
  check(#controller().curve.points == 0, "curve cleared")
  dev("click", P, "blueprint_load")
  check(#controller().curve.points == storage.points, "curve loaded from the blueprint")
  check(#controller().presets == storage.preset_count + 1 and controller().ui.preset_index == storage.preset_count + 1, "preset added and selected")
  dev("click", P, "preset_delete")
  -- ... also from inside a blueprint book
  local scratch = game.create_inventory(1)
  scratch[1].set_stack { name = "blueprint-book", count = 1 }
  check(scratch[1].get_inventory(defines.inventory.item_main).insert(stack) == 1, "blueprint put in a book")
  player.cursor_stack.set_stack(scratch[1])
  scratch.destroy()
  dev("click", P, "control_points_clear")
  dev("click", P, "blueprint_load")
  check(#controller().curve.points == storage.points and #controller().presets == storage.preset_count + 1, "loaded from the book's blueprint")
  dev("click", P, "preset_delete")
  player.clear_cursor()
  dev("click", P, "blueprint_load")
  dev("set_setting", P, "blueprint_source", false)
  dev("click", P, "blueprint_build")
end, "idle")

step("blueprint without curve and preset when turned off", function(player)
  local stack = player.cursor_stack
  check(stack.valid_for_read and stack.is_blueprint_setup(), "blueprint in cursor")
  check(stack.get_blueprint_entity_tag(1, "bezierio") == nil, "no tags")
  check(stack.blueprint_description == "", "no description: " .. stack.blueprint_description)
  local presets = #controller().presets
  dev("click", P, "blueprint_load")
  check(#controller().presets == presets, "nothing to load")
  dev("set_setting", P, "blueprint_source", true)
  player.clear_cursor()
  -- back to the preset the rest of the test uses
  dev("click", P, "preset_delete")
  check(controller().ui.preset_index == 1 and #controller().presets == storage.preset_count, "back to the first preset")
end, "idle")

-- Build modes (as the game's, FFF-383): Build leaves trees and water alone; Force
-- build marks trees and lays cover (landfill on water) under walls and floor.
local function cell_of(position) return { x = math.floor(position.x), y = math.floor(position.y) } end

step("build modes: water under walls and floor, a tree in the way", function(player)
  local s = player.surface
  flow.clear_build(s)
  local plan = dev("plan", P)
  local walls = planned_walls(plan)
  storage.wet = {}
  local tiles = {}
  for i = 5, 8 do
    local c = cell_of(walls[i].position)
    storage.wet[#storage.wet + 1] = c
    tiles[#tiles + 1] = { name = "water", position = c }
  end
  storage.wet_floor = { x = plan.tiles[3].x, y = plan.tiles[3].y }
  tiles[#tiles + 1] = { name = "water", position = storage.wet_floor }
  s.set_tiles(tiles)
  storage.tree3 = s.create_entity { name = "tree-01", position = walls[15].position }
  storage.wet_walls = { walls[5].position, walls[6].position, walls[7].position, walls[8].position }
  dev("click", P, "normal_build")
end, "idle")

local function wall_ghost_at(s, position)
  return s.find_entities_filtered { ghost_name = "stone-wall", position = position, limit = 1 }[1]
end
local function tile_ghost_names(s, c)
  local names = {}
  for _, g in pairs(s.find_entities_filtered { type = "tile-ghost", position = { c.x + 0.5, c.y + 0.5 } }) do names[g.ghost_name] = true end
  return names
end

step("... Build: nothing on water, the tree left standing", function(player)
  local s = player.surface
  local on_water = 0
  for _, p in ipairs(storage.wet_walls) do if wall_ghost_at(s, p) then on_water = on_water + 1 end end
  check(on_water == 0, "no wall ghosts on water: " .. on_water)
  check(not storage.tree3.to_be_deconstructed(), "tree not marked")
  check(not tile_ghost_names(s, storage.wet_floor)["stone-path"], "no floor on water")
  local landfill = 0
  for _, g in pairs(s.find_entities_filtered { type = "tile-ghost" }) do if g.ghost_name == "landfill" then landfill = landfill + 1 end end
  check(landfill == 0, "no landfill")
  check(#ghosts(s, "stone-wall") > 20, "walls elsewhere")
  flow.clear_build(s)
  dev("click", P, "build")
end, "idle")

step("... Force build: landfill under the walls and the floor, the tree marked", function(player)
  local s = player.surface
  local ok = 0
  for i, p in ipairs(storage.wet_walls) do
    if wall_ghost_at(s, p) and tile_ghost_names(s, storage.wet[i]).landfill then ok = ok + 1 end
  end
  check(ok == 4, "wall ghosts on landfill ghosts: " .. ok .. "/4")
  local floor = tile_ghost_names(s, storage.wet_floor)
  check(floor.landfill and floor["stone-path"], "landfill ghost under the floor ghost")
  check(storage.tree3.to_be_deconstructed(), "tree marked")
  flow.clear_build(s)
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("... cheat mode: real landfill under real walls and floor", function(player)
  local s = player.surface
  local ok = 0
  for i, p in ipairs(storage.wet_walls) do
    local c = storage.wet[i]
    if s.find_entity("stone-wall", p) and s.get_tile(c.x, c.y).name == "landfill" then ok = ok + 1 end
  end
  check(ok == 4, "walls on landfill: " .. ok .. "/4")
  local f = storage.wet_floor
  check(s.get_tile(f.x, f.y).name == "stone-path" and s.get_hidden_tile({ f.x, f.y }) == "landfill", "stone path over landfill")
  player.cheat_mode = false
  flow.clear_build(s)
  local tiles = {}
  for _, c in ipairs(storage.wet) do tiles[#tiles + 1] = { name = "grass-1", position = c } end
  tiles[#tiles + 1] = { name = "grass-1", position = f }
  s.set_tiles(tiles)
end)

step("force build removes a cliff in the way (cheat mode)", function(player)
  local s = player.surface
  local walls = planned_walls(dev("plan", P))
  storage.cliff = s.create_entity { name = "cliff", position = walls[12].position, cliff_orientation = "west-to-east" }
  storage.cliff_wall = walls[12].position
  check(storage.cliff and storage.cliff.valid, "cliff placed")
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("... gone, the wall built there", function(player)
  local s = player.surface
  check(not storage.cliff.valid, "cliff removed")
  check(s.find_entity("stone-wall", storage.cliff_wall), "wall where the cliff was")
  player.cheat_mode = false
  flow.clear_build(s)
  -- ghosts: marked for deconstruction (with cliff explosives), the wall ghost over it
  local tech = player.force.technologies["cliff-explosives"]
  if tech then tech.researched = true end
  storage.cliff = s.create_entity { name = "cliff", position = storage.cliff_wall, cliff_orientation = "west-to-east" }
  dev("click", P, "build")
end, "idle")

step("... ghosts: the cliff marked, a wall ghost there", function(player)
  local s = player.surface
  check(storage.cliff.valid and storage.cliff.to_be_deconstructed(), "cliff marked for deconstruction")
  check(wall_ghost_at(player.surface, storage.cliff_wall), "wall ghost where the cliff is")
  storage.cliff.destroy()
  flow.clear_build(s)
end)

step("cover from the player's list, and lava (with Space Age)", function(player)
  if not prototypes.item["foundation"] then return end
  local s = player.surface
  local walls = planned_walls(dev("plan", P))
  storage.wet2 = { cell_of(walls[5].position), cell_of(walls[6].position) }
  s.set_tiles({ { name = "water", position = storage.wet2[1] }, { name = "lava", position = storage.wet2[2] } })
  dev("set_setting", P, "cover_tiles", { "foundation" })
  dev("click", P, "build")
end, "idle")

step("... foundation on water (the list), foundation on lava (the default)", function(player)
  if not prototypes.item["foundation"] then return end
  local s = player.surface
  check(tile_ghost_names(s, storage.wet2[1]).foundation, "foundation on water, as listed")
  check(tile_ghost_names(s, storage.wet2[2]).foundation, "foundation on lava")
  dev("set_setting", P, "cover_tiles", { "landfill" })
  flow.clear_build(s)
  dev("click", P, "build")
end, "idle")

step("... landfill listed: landfill on water, still foundation on lava", function(player)
  if not prototypes.item["foundation"] then return end
  local s = player.surface
  check(tile_ghost_names(s, storage.wet2[1]).landfill, "landfill on water")
  check(tile_ghost_names(s, storage.wet2[2]).foundation, "foundation on lava (landfill can't go there)")
  dev("set_setting", P, "cover_tiles", nil)
  flow.clear_build(s)
  s.set_tiles({ { name = "grass-1", position = storage.wet2[1] }, { name = "grass-1", position = storage.wet2[2] } })
end)

-- Aquilo's ground: ammoniacal ocean takes an ice platform, and a wall (which
-- needs heat: `meltable`) can't stand on ice, so concrete goes on top; on rough
-- ice, just concrete. Inferred from the prototypes.
step("cover in two layers: ammoniacal ocean and rough ice (with Space Age)", function(player)
  if not prototypes.tile["ammoniacal-ocean"] then return end
  local s = player.surface
  flow.clear_build(s)
  local walls = planned_walls(dev("plan", P))
  storage.ocean, storage.ice = cell_of(walls[5].position), cell_of(walls[6].position)
  storage.ocean_wall, storage.ice_wall = walls[5].position, walls[6].position
  s.set_tiles({ { name = "ammoniacal-ocean", position = storage.ocean }, { name = "ice-rough", position = storage.ice } })
  dev("click", P, "build")
end, "idle")

step("... ghosts: ice platform and concrete on the ocean, concrete on the ice", function(player)
  if not prototypes.tile["ammoniacal-ocean"] then return end
  local s = player.surface
  local ocean, ice = tile_ghost_names(s, storage.ocean), tile_ghost_names(s, storage.ice)
  check(ocean["ice-platform"] and ocean.concrete, "ocean: ice platform and concrete ghosts")
  check(ice.concrete and not ice["ice-platform"], "rough ice: a concrete ghost")
  check(wall_ghost_at(s, storage.ocean_wall) and wall_ghost_at(s, storage.ice_wall), "wall ghosts on both")
  flow.clear_build(s)
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("... cheat mode: real walls on concrete", function(player)
  if not prototypes.tile["ammoniacal-ocean"] then return end
  local s = player.surface
  local o, i = storage.ocean, storage.ice
  check(s.find_entity("stone-wall", storage.ocean_wall) and s.find_entity("stone-wall", storage.ice_wall), "walls built")
  check(s.get_tile(o.x, o.y).name:find("concrete") and s.get_hidden_tile({ o.x, o.y }) == "ice-platform",
    "ocean: concrete over ice platform: " .. s.get_tile(o.x, o.y).name)
  check(s.get_tile(i.x, i.y).name:find("concrete"), "rough ice: concrete: " .. s.get_tile(i.x, i.y).name)
  player.cheat_mode = false
  flow.clear_build(s)
  s.set_tiles({ { name = "grass-1", position = o }, { name = "grass-1", position = i } })
end)

-- The undo stack holds 100 items: once full, its size stops growing, and the
-- build's actions must still go into one item.
step("undo: a build with the stack full", function(player)
  local s = player.surface
  flow.clear_build(s)
  for i = 1, 120 do
    s.create_entity { name = "stone-wall", position = { -95 + (i % 30), 90 + math.floor(i / 30) }, force = player.force,
      player = player, undo_index = 0 }
  end
  storage.undo_full = player.undo_redo_stack.get_undo_item_count()
  dev("click", P, "build")
end, "idle")

step("... one item for the whole build", function(player)
  local stack = player.undo_redo_stack
  check(storage.undo_full == 100 and stack.get_undo_item_count() == 100, "the stack is full: " .. stack.get_undo_item_count())
  check(#stack.get_undo_item(1) > 100, "the top item holds the build: " .. #stack.get_undo_item(1) .. " actions")
  check(#stack.get_undo_item(2) == 1, "the one below is the player's own")
  for _, e in pairs(player.surface.find_entities_filtered { area = { { -96, 89 }, { -60, 96 } }, name = "stone-wall" }) do e.destroy() end
  flow.clear_build(player.surface)
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
