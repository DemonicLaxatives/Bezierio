-- Rails: track fitted to the curve, continuous, with signals on the side trains
-- travel; walls alongside. tests/run.sh rails
local flow = require("__bezierio-test__/lib/flow")
local P, dev, check, el, step = flow.P, flow.dev, flow.check, flow.el, flow.step
local layers = flow.layers

local RAILS = { "straight-rail", "half-diagonal-rail", "curved-rail-a", "curved-rail-b" }

--- Ends of the built track that lead nowhere.
local function loose_ends(s)
  local loose = 0
  for _, rail in pairs(s.find_entities_filtered { name = RAILS }) do
    for _, rd in ipairs({ defines.rail_direction.front, defines.rail_direction.back }) do
      local connected = false
      for _, cd in ipairs({ defines.rail_connection_direction.straight, defines.rail_connection_direction.left, defines.rail_connection_direction.right }) do
        if rail.get_connected_rail { rail_direction = rd, rail_connection_direction = cd } then connected = true end
      end
      if not connected then loose = loose + 1 end
    end
  end
  return loose
end

step("setup: rails along a bend, walls either side", function(player)
  local s = player.surface
  flow.prepare_ground(s)
  flow.open_window(player)
  dev("click", P, "pointer_button")
  dev("pointer", P, { x = -50.5, y = 20.5 })
  dev("pointer", P, { x = 0.5, y = 10.5 })
  dev("pointer", P, { x = 40.5, y = -40.5 })
  dev("click", P, "pointer_button")
  local offered = {}
  for _, n in pairs(dev("item_filter")[1].name) do offered[n] = true end
  check(offered["rail"], "rails offered in the picker")
  dev("set_elem", P, "layer_type", { name = "rail", quality = "normal" })
  check(layers()[0].type == "straight-rail" and layers()[0].signal_name == "rail-signal", "rail layer")
  dev("set_value", P, "signal_spacing_slider", 3)
  for _, side in ipairs({ "above", "below" }) do
    dev("click", P, "add_layer_" .. side)
    dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
    dev("set_value", P, "offset_slider", 2)
  end
  dev("click", P, "layer_select_0")
  dev("click", P, "preview_build")
end, "idle")

step("planned and previewed", function(player)
  local plan = dev("plan", P)
  local rails, signals = 0, 0
  for _, e in pairs(plan.entities) do
    if e.track then rails = rails + 1 end
    if e.name == "rail-signal" then signals = signals + 1 end
  end
  check(rails > 20 and signals >= 2, "track planned: " .. rails .. " pieces, " .. signals .. " signals")
  check(#plan.warnings == 0, "track stays on the curve: " .. #plan.warnings .. " warnings")
  storage.rails, storage.signals = rails, signals
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("built track is continuous", function(player)
  local s = player.surface
  check(s.count_entities_filtered { name = RAILS } == storage.rails, "all rails built: " .. s.count_entities_filtered { name = RAILS } .. "/" .. storage.rails)
  check(loose_ends(s) == 2, "one continuous track (two loose ends): " .. loose_ends(s))
  local signals = s.find_entities_filtered { name = "rail-signal" }
  check(#signals == storage.signals, "signals built: " .. #signals)
  for _, sig in pairs(signals) do check(#sig.get_connected_rails() > 0, "signal on the track") end
  check(s.count_entities_filtered { name = "stone-wall" } > 100, "walls alongside")
end)

step("signals face the direction of travel", function(player)
  local s = player.surface
  -- Travelling forwards (from the curve's start), some segment ends in a signal;
  -- backwards none does.
  local plan = dev("plan", P)
  local first
  for _, e in pairs(plan.entities) do if e.track then first = first or e end end
  local rail = s.find_entity(first.name, first.position)
  check(rail, "first rail found")
  local forward_dir
  for _, rd in ipairs({ defines.rail_direction.front, defines.rail_direction.back }) do
    local loc = rail.get_rail_end(rd).location
    if math.abs(loc.position.x - first.track.to.x) < 0.01 and math.abs(loc.position.y - first.track.to.y) < 0.01 then forward_dir = rd end
  end
  check(forward_dir, "the first rail's forward end")
  local backward_dir = forward_dir == defines.rail_direction.front and defines.rail_direction.back or defines.rail_direction.front
  check(rail.get_rail_segment_signal(forward_dir, false) ~= nil, "going forwards, the first segment ends at a signal")
  -- From the far end going backwards there's no signal for that way.
  local last
  for _, e in pairs(plan.entities) do if e.track then last = e end end
  local far = s.find_entity(last.name, last.position)
  local back_dir
  for _, rd in ipairs({ defines.rail_direction.front, defines.rail_direction.back }) do
    local loc = far.get_rail_end(rd).location
    if math.abs(loc.position.x - last.track.from.x) < 0.01 and math.abs(loc.position.y - last.track.from.y) < 0.01 then back_dir = rd end
  end
  check(back_dir and far.get_rail_segment_signal(back_dir, false) == nil, "going backwards, no signal")
  player.cheat_mode = false
  for _, e in pairs(s.find_entities_filtered { area = { { -90, -90 }, { 90, 90 } } }) do
    if e.type ~= "character" then e.destroy() end
  end
  dev("click", P, "build")
end, "idle")

step("both ways: signals on both sides", function(player)
  dev("set_value", P, "direction_of_travel_slider", 0)
  local both = 0
  for _, e in pairs(dev("plan", P).entities) do if e.name == "rail-signal" then both = both + 1 end end
  check(both == 2 * storage.signals, "twice the signals: " .. both .. " vs " .. storage.signals)
  dev("set_value", P, "direction_of_travel_slider", 1)
end)

step("rail ghosts", function(player)
  local s = player.surface
  local ghosts = 0
  for _, name in ipairs(RAILS) do ghosts = ghosts + #s.find_entities_filtered { ghost_name = name } end
  check(ghosts == storage.rails, "rail ghosts: " .. ghosts .. "/" .. storage.rails)
  check(#s.find_entities_filtered { ghost_name = "rail-signal" } == storage.signals, "signal ghosts")
end)

step("blueprint of the track", function(player)
  for _, e in pairs(player.surface.find_entities_filtered { area = { { -90, -90 }, { 90, 90 } } }) do
    if e.type ~= "character" then e.destroy() end
  end
  dev("click", P, "blueprint_build")
end, "idle")

step("blueprint stamps rails onto the plan", function(player)
  local s, stack = player.surface, player.cursor_stack
  check(stack.valid_for_read and stack.is_blueprint, "blueprint in cursor")
  local plan = dev("plan", P)
  local first
  for _, e in pairs(plan.entities) do if e.track then first = first or e end end
  stack.build_blueprint { surface = s, force = player.force, position = first.position, build_mode = defines.build_mode.forced }
  local missing = 0
  for _, e in pairs(plan.entities) do
    if e.track and not s.find_entities_filtered { ghost_name = e.name, position = e.position, limit = 1 }[1] then missing = missing + 1 end
  end
  check(missing == 0, "rail ghosts on the planned spots: missing " .. missing)
  player.clear_cursor()
end)

-- Elevated rails (elevated-rails mod): supports and ramps, built in that order.
local ELEVATED = { "elevated-straight-rail", "elevated-half-diagonal-rail", "elevated-curved-rail-a", "elevated-curved-rail-b" }

local function clear_all(s)
  for _, e in pairs(s.find_entities_filtered { area = { { -90, -90 }, { 90, 90 } } }) do
    if e.type ~= "character" then e.destroy() end
  end
end

step("elevated: plan", function(player)
  if not prototypes.entity["elevated-straight-rail"] then
    log("(no elevated-rails mod: skipped)")
    return
  end
  clear_all(player.surface)
  check(el(player, "elevated"), "elevated option offered")
  dev("set_checked", P, "elevated", true)
  check(el(player, "ramps") and el(player, "ramps").state, "ramps on")
  local plan = dev("plan", P)
  local n = { rails = 0, supports = 0, ramps = 0, signals = 0 }
  for _, e in pairs(plan.entities) do
    if e.track and e.name ~= "rail-ramp" then n.rails = n.rails + 1 end
    if e.name == "rail-ramp" then n.ramps = n.ramps + 1 end
    if e.name == "rail-support" then n.supports = n.supports + 1 end
    if e.name == "rail-signal" then n.signals = n.signals + 1 end
  end
  check(n.rails > 20 and n.supports >= 5 and n.ramps >= 1, string.format("elevated track: %d rails, %d supports, %d ramps", n.rails, n.supports, n.ramps))
  storage.elevated = n
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("elevated: built on its supports", function(player)
  if not storage.elevated then return end
  local s = player.surface
  local n = storage.elevated
  check(s.count_entities_filtered { name = ELEVATED } == n.rails, "elevated rails built: " .. s.count_entities_filtered { name = ELEVATED } .. "/" .. n.rails)
  check(s.count_entities_filtered { name = "rail-support" } == n.supports, "supports built")
  check(s.count_entities_filtered { name = "rail-ramp" } == n.ramps, "ramps built")
  local signals = s.find_entities_filtered { name = "rail-signal" }
  check(#signals == n.signals, "signals built: " .. #signals .. "/" .. n.signals)
  for _, sig in pairs(signals) do check(sig.rail_layer == defines.rail_layer.elevated, "signal on the elevated track") end
  local all = {}
  for _, name in ipairs(ELEVATED) do all[#all + 1] = name end
  for _, name in ipairs(RAILS) do all[#all + 1] = name end
  all[#all + 1] = "rail-ramp"
  local loose = 0
  for _, rail in pairs(s.find_entities_filtered { name = all }) do
    for _, rd in ipairs({ defines.rail_direction.front, defines.rail_direction.back }) do
      local connected = false
      for _, cd in ipairs({ defines.rail_connection_direction.straight, defines.rail_connection_direction.left, defines.rail_connection_direction.right }) do
        if rail.get_connected_rail { rail_direction = rd, rail_connection_direction = cd } then connected = true end
      end
      if not connected then loose = loose + 1 end
    end
  end
  check(loose == 2, "one continuous track, ramps included: " .. loose .. " loose ends")
  player.cheat_mode = false
  clear_all(s)
  dev("click", P, "build")
end, "idle")

step("elevated: ghosts", function(player)
  if not storage.elevated then return end
  local s = player.surface
  local ghosts = 0
  for _, name in ipairs(ELEVATED) do ghosts = ghosts + #s.find_entities_filtered { ghost_name = name } end
  check(ghosts == storage.elevated.rails, "elevated rail ghosts: " .. ghosts .. "/" .. storage.elevated.rails)
  check(#s.find_entities_filtered { ghost_name = "rail-support" } == storage.elevated.supports, "support ghosts")
  dev("set_checked", P, "elevated", false)
end)

step("gates where the track crosses walls already there", function(player)
  local s = player.surface
  clear_all(s)
  dev("click", P, "control_points_clear")
  dev("click", P, "pointer_button")
  dev("pointer", P, { x = -40.5, y = 0.5 })
  dev("pointer", P, { x = 40.5, y = 0.5 })
  dev("click", P, "pointer_button")
  dev("set_value", P, "signal_spacing_slider", 0)
  check(el(player, "wall_gates") and el(player, "wall_gates").state, "gates on for rails")
  -- a wall line across the track
  for y = -8, 8 do s.create_entity { name = "stone-wall", position = { 0.5, y + 0.5 }, force = player.force } end
  dev("click", P, "build")
end, "idle")

step("gate ghosts across the track, walls to be removed", function(player)
  local s = player.surface
  local gates = s.find_entities_filtered { ghost_name = "gate" }
  check(#gates >= 2, "gate ghosts: " .. #gates)
  for _, g in pairs(gates) do check(g.direction == defines.direction.north, "gate turned across the east-west track") end
  local marked = 0
  for _, w in pairs(s.find_entities_filtered { name = "stone-wall" }) do if w.to_be_deconstructed() then marked = marked + 1 end end
  check(marked == #gates, "the walls under the track marked for removal: " .. marked)
  local plan = dev("plan", P)
  local missing = 0
  for _, e in pairs(plan.entities) do
    if e.track and not s.find_entities_filtered { ghost_name = e.name, position = e.position, limit = 1 }[1] then missing = missing + 1 end
  end
  check(missing == 0, "the whole track as ghosts, through the wall: missing " .. missing)
  clear_all(s)
  for y = -8, 8 do s.create_entity { name = "stone-wall", position = { 0.5, y + 0.5 }, force = player.force } end
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("instant: walls swapped for gates, rails through", function(player)
  local s = player.surface
  check(s.count_entities_filtered { name = "gate" } >= 2, "gates built")
  local column = { { 0, -8 }, { 1, 9 } }
  local walls, gates = s.count_entities_filtered { name = "stone-wall", area = column }, s.count_entities_filtered { name = "gate", area = column }
  check(walls + gates == 17, "the rest of the wall stays: walls " .. walls .. ", gates " .. gates)
  check(s.count_entities_filtered { name = RAILS } == #(function() local t = {} for _, e in pairs(dev("plan", P).entities) do if e.track then t[#t + 1] = e end end return t end)(),
    "the whole track built")
  player.cheat_mode = false
end)

-- Super force: each piece clears what's in its way, but not the track this build
-- just laid (the square around a curved rail reaches over its neighbours) nor the
-- other track.
local function planned_track()
  local out = {}
  for _, e in pairs(dev("plan", P).entities) do
    if e.track or e.name == "rail-signal" or e.name == "rail-support" then out[#out + 1] = e end
  end
  return out
end

step("super force: two tracks along a bend", function(player)
  local s = player.surface
  clear_all(s)
  dev("click", P, "control_points_clear")
  dev("click", P, "pointer_button")
  dev("pointer", P, { x = -50.5, y = 20.5 })
  dev("pointer", P, { x = 0.5, y = 10.5 })
  dev("pointer", P, { x = 40.5, y = -40.5 })
  dev("click", P, "pointer_button")
  dev("click", P, "layer_select_0")
  dev("set_value", P, "signal_spacing_slider", 2)
  dev("click", P, "layer_select_1")
  dev("set_elem", P, "layer_type", { name = "rail", quality = "normal" })
  dev("set_value", P, "offset_slider", 0)
  dev("set_value", P, "signal_spacing_slider", 2)
  check(layers()[1].type == "straight-rail", "second rail layer")
  -- something of the player's on the track, to be cleared
  local first = planned_track()[1]
  storage.chest = s.create_entity { name = "wooden-chest", position = first.position, force = player.force }
  dev("click", P, "super_build")
end, "idle")

step("super force: every piece of both tracks as a ghost", function(player)
  local s = player.surface
  local track, missing = planned_track(), 0
  for _, e in pairs(track) do
    if not s.find_entities_filtered { ghost_name = e.name, position = e.position, limit = 1 }[1] then missing = missing + 1 end
  end
  local layers_seen = {}
  for _, e in pairs(track) do layers_seen[e.layer] = true end
  check(layers_seen[0] and layers_seen[1], "two tracks planned")
  check(missing == 0, "all " .. #track .. " ghosts there: missing " .. missing)
  check(storage.chest.valid and storage.chest.to_be_deconstructed(), "the chest in the way marked")
  clear_all(s)
  player.cheat_mode = true
  dev("click", P, "super_build")
end, "idle")

step("super force, instant: both tracks built", function(player)
  local s = player.surface
  local track, missing = planned_track(), 0
  for _, e in pairs(track) do
    if not s.find_entity(e.name, e.position) then missing = missing + 1 end
  end
  check(missing == 0, "all " .. #track .. " built: missing " .. missing)
  player.cheat_mode = false
  if not prototypes.entity["elevated-straight-rail"] then return end
  clear_all(s)
  dev("set_checked", P, "elevated", true)
  dev("click", P, "super_build")
end, "idle")

step("super force: elevated track over ground track", function(player)
  if not prototypes.entity["elevated-straight-rail"] then return end
  local s = player.surface
  local track, missing = planned_track(), 0
  for _, e in pairs(track) do
    if not s.find_entities_filtered { ghost_name = e.name, position = e.position, limit = 1 }[1] then missing = missing + 1 end
  end
  check(missing == 0, "all " .. #track .. " ghosts there: missing " .. missing)
  dev("set_checked", P, "elevated", false)
end)

flow.run("rails")
