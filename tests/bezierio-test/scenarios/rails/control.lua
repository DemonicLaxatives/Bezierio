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

-- Blueprints of track keep to the 2x2 rail grid wherever the build is: the
-- game rounds an odd grid size up (the blueprint would no longer snap onto the
-- preview), and its blueprint window refuses an odd grid position. The curve
-- moved a tile at a time, so the build's corner falls on odd tiles too.
local BEND = { { x = -50.5, y = 20.5 }, { x = 0.5, y = 10.5 }, { x = 40.5, y = -40.5 } }
local function set_curve(points, dx, dy)
  dev("click", P, "control_points_clear")
  dev("click", P, "pointer_button")
  for _, p in ipairs(points) do dev("pointer", P, { x = p.x + dx, y = p.y + dy }) end
  dev("click", P, "pointer_button")
end
for _, shift in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
  local name = "moved " .. shift[1] .. "," .. shift[2]
  step("blueprint of the track, " .. name, function(player)
    for _, e in pairs(player.surface.find_entities_filtered { area = { { -90, -90 }, { 90, 90 } } }) do
      if e.type ~= "character" then e.destroy() end
    end
    set_curve(BEND, shift[1], shift[2])
    dev("click", P, "blueprint_build")
  end, "idle")
  step("... on the rail grid, and stamps the track onto the plan, " .. name, function(player)
    local s, stack = player.surface, player.cursor_stack
    check(stack.valid_for_read and stack.is_blueprint, "blueprint in cursor")
    local grid, rel = stack.blueprint_snap_to_grid, stack.blueprint_position_relative_to_grid
    check(grid and rel and grid.x % 2 == 0 and grid.y % 2 == 0 and rel.x % 2 == 0 and rel.y % 2 == 0,
      string.format("grid %s,%s at %s,%s: all even", grid and grid.x, grid and grid.y, rel and rel.x, rel and rel.y))
    local plan = dev("plan", P)
    local first
    for _, e in pairs(plan.entities) do if e.track then first = first or e end end
    stack.build_blueprint { surface = s, force = player.force, position = first.position, build_mode = defines.build_mode.forced }
    local missing, total = 0, 0
    for _, e in pairs(plan.entities) do
      if e.track or e.name == "stone-wall" then
        total = total + 1
        if not s.find_entities_filtered { ghost_name = e.name, position = e.position, limit = 1 }[1] then missing = missing + 1 end
      end
    end
    check(missing == 0, "track and walls stamped on the planned spots: missing " .. missing .. "/" .. total)
    player.clear_cursor()
    for _, e in pairs(s.find_entities_filtered { area = { { -90, -90 }, { 90, 90 } } }) do
      if e.type ~= "character" then e.destroy() end
    end
    set_curve(BEND, 0, 0)
  end)
end

-- Elevated rails (elevated-rails mod): supports and ramps, built in that order.
local ELEVATED = { "elevated-straight-rail", "elevated-half-diagonal-rail", "elevated-curved-rail-a", "elevated-curved-rail-b" }

local function clear_all(s)
  for _, e in pairs(s.find_entities_filtered { area = { { -90, -90 }, { 90, 90 } } }) do
    if e.type ~= "character" then e.destroy() end
  end
end

-- Smoothing: longer straights and steadier bends, still one continuous track.
step("smoothing: a smoother track", function(player)
  clear_all(player.surface)
  local function bends(plan)
    local n, prev = 0, nil
    for _, e in ipairs(plan.entities) do
      if e.track then
        local bend = e.name:find("curved") and "c" or "s"
        if prev and bend ~= prev then n = n + 1 end
        prev = bend
      end
    end
    return n
  end
  check(layers()[0].smoothing == 2, "smoothing 2 by default")
  dev("set_value", P, "smoothing_slider", 0)
  local tight = bends(dev("plan", P))
  dev("set_value", P, "smoothing_slider", 6)
  check(layers()[0].smoothing == 6, "smoothing set")
  local plan = dev("plan", P)
  local rails = 0
  for _, e in pairs(plan.entities) do if e.track then rails = rails + 1 end end
  check(bends(plan) < tight, "fewer changes between bending and straight: " .. bends(plan) .. " vs " .. tight)
  check(#plan.warnings == 0, "no warnings: " .. #plan.warnings)
  storage.smooth_rails = rails
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("smoothing: built, one continuous track", function(player)
  local s = player.surface
  check(s.count_entities_filtered { name = RAILS } == storage.smooth_rails, "all rails built: " .. s.count_entities_filtered { name = RAILS } .. "/" .. storage.smooth_rails)
  check(loose_ends(s) == 2, "one continuous track (two loose ends): " .. loose_ends(s))
  player.cheat_mode = false
  dev("set_value", P, "smoothing_slider", 2)
  clear_all(s)
end)

step("elevated: plan", function(player)
  if not prototypes.entity["elevated-straight-rail"] then
    log("(no elevated-rails mod: skipped)")
    return
  end
  clear_all(player.surface)
  dev("click", P, "layer_settings_0")
  check(el(player, "elevated"), "elevated option offered")
  dev("set_checked", P, "elevated", true)
  check(el(player, "ramps") and el(player, "ramps").state, "ramps on")
  -- the walls right beside the band: supports and ramps are wider than the track
  for _, idx in ipairs({ -1, 1 }) do
    dev("click", P, "layer_settings_" .. idx)
    dev("set_value", P, "offset_slider", 0)
  end
  dev("click", P, "layer_select_0")
  local plan = dev("plan", P)
  local n = { rails = 0, supports = 0, ramps = 0, signals = 0, walls = 0 }
  for _, e in pairs(plan.entities) do
    if e.track and e.name ~= "rail-ramp" then n.rails = n.rails + 1 end
    if e.name == "rail-ramp" then n.ramps = n.ramps + 1 end
    if e.name == "rail-support" then
      n.supports = n.supports + 1
      check(e.arrow == false, "a support is previewed without an arrow")
    end
    if e.name == "rail-signal" then n.signals = n.signals + 1 end
    if e.name == "stone-wall" then n.walls = n.walls + 1 end
  end
  check(n.rails > 20 and n.supports >= 5 and n.ramps >= 1 and n.walls > 50,
    string.format("elevated track: %d rails, %d supports, %d ramps, %d walls", n.rails, n.supports, n.ramps, n.walls))
  storage.elevated = n
end)

--- Every planned elevated piece is carried by the planned supports and ramps: on
--- a clear stretch of `s` with only those, each piece passes the check a
--- player's build gets (a script or ghost placement doesn't check supports). A
--- support carries track joined to it, so pieces are placed over and over, those
--- that pass each time, until no more do. Returns how many never do, and how
--- many planned signals a player couldn't place on that track.
local function unsupported(s, plan, force)
  clear_all(s)
  local pieces = {}
  for _, e in ipairs(plan.entities) do
    if e.name == "rail-support" or e.name == "rail-ramp" then
      s.create_entity { name = e.name, position = e.position, direction = e.direction, force = force }
    elseif e.track then
      pieces[#pieces + 1] = e
    end
  end
  local progress = true
  while progress do
    progress = false
    local left = {}
    for _, e in ipairs(pieces) do
      if s.can_place_entity { name = e.name, position = e.position, direction = e.direction, force = force,
            build_check_type = defines.build_check_type.manual } then
        s.create_entity { name = e.name, position = e.position, direction = e.direction, force = force }
        progress = true
      else
        left[#left + 1] = e
      end
    end
    pieces = left
  end
  -- and the signals, where a player could place them on that track
  local signals = 0
  for _, e in ipairs(plan.entities) do
    if e.name == "rail-signal" and not s.can_place_entity { name = e.name, position = e.position, direction = e.direction, force = force,
          rail_layer = e.rail_layer and defines.rail_layer[e.rail_layer] or nil, build_check_type = defines.build_check_type.manual } then
      signals = signals + 1
    end
  end
  clear_all(s)
  return #pieces, signals
end

step("elevated: every piece carried by the supports, which are as few as that allows", function(player)
  if not storage.elevated then return end
  local plan = dev("plan", P)
  local bad, signals = unsupported(player.surface, plan, player.force)
  check(bad == 0, "elevated pieces out of the supports' reach: " .. bad)
  check(signals == 0, "signals a player couldn't place there (at a ramp's end): " .. signals)
  -- (a support carries 10 tiles either way: about one per 20 tiles of track,
  -- less the 8 tiles past each ramp top)
  local length = 0
  for _, e in ipairs(plan.entities) do
    if e.track and e.name ~= "rail-ramp" then
      length = length + math.sqrt((e.track.to.x - e.track.from.x) ^ 2 + (e.track.to.y - e.track.from.y) ^ 2)
    end
  end
  check(storage.elevated.supports <= math.ceil(length / 20) + 2,
    string.format("supports: %d for %.0f tiles of elevated track", storage.elevated.supports, length))
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("elevated: built on its supports", function(player)
  if not storage.elevated then return end
  local s = player.surface
  local n = storage.elevated
  check(s.count_entities_filtered { name = ELEVATED } == n.rails, "elevated rails built: " .. s.count_entities_filtered { name = ELEVATED } .. "/" .. n.rails)
  check(s.count_entities_filtered { name = "rail-support" } == n.supports, "supports built: " .. s.count_entities_filtered { name = "rail-support" } .. "/" .. n.supports)
  check(s.count_entities_filtered { name = "stone-wall" } == n.walls, "walls built right beside them: " .. s.count_entities_filtered { name = "stone-wall" } .. "/" .. n.walls)
  check(s.count_entities_filtered { name = "rail-ramp" } == n.ramps, "ramps built: " .. s.count_entities_filtered { name = "rail-ramp" } .. "/" .. n.ramps)
  local signals = s.find_entities_filtered { name = "rail-signal" }
  check(#signals == n.signals, "signals built: " .. #signals .. "/" .. n.signals)
  -- every signal joined to the track: elevated, or on the ground at a ramp's foot
  for _, sig in pairs(signals) do
    local joined = sig.get_connected_rails()
    check(#joined > 0, "signal at " .. sig.position.x .. "," .. sig.position.y .. " joined to the track")
    if sig.rail_layer ~= defines.rail_layer.elevated then
      check(joined[1] and joined[1].name == "rail-ramp", "a signal on the ground only at a ramp's foot")
    end
  end
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
  check(#s.find_entities_filtered { ghost_name = "rail-ramp" } == storage.elevated.ramps, "ramp ghosts")
  check(#s.find_entities_filtered { ghost_name = "stone-wall" } == storage.elevated.walls, "wall ghosts: " .. #s.find_entities_filtered { ghost_name = "stone-wall" } .. "/" .. storage.elevated.walls)
  dev("set_checked", P, "elevated", false)
  for _, idx in ipairs({ -1, 1 }) do
    dev("click", P, "layer_settings_" .. idx)
    dev("set_value", P, "offset_slider", 2)
  end
  dev("click", P, "layer_select_0")
end)

-- A straight and a diagonal stretch of elevated track: supports as far apart as
-- the game lets them carry the track (20 tiles straight): it carries all of it,
-- and wouldn't without any one of them.
step("elevated: supports 20 tiles apart on a straight, carrying it all", function(player)
  if not storage.elevated then return end
  for _, case in ipairs({ { name = "straight", to = { x = 80.5, y = 0.5 }, from = { x = -80.5, y = 0.5 }, most = 7 },
                          { name = "diagonal", from = { x = -60.5, y = 60.5 }, to = { x = 60.5, y = -60.5 }, most = 11 } }) do
    dev("click", P, "control_points_clear")
    dev("click", P, "pointer_button")
    dev("pointer", P, case.from)
    dev("pointer", P, case.to)
    dev("click", P, "pointer_button")
    dev("click", P, "layer_settings_0")
    dev("set_checked", P, "elevated", true)
    dev("set_checked", P, "ramps", case.name == "straight")
    dev("click", P, "layer_select_0")
    local plan = dev("plan", P)
    local supports = 0
    for _, e in ipairs(plan.entities) do if e.name == "rail-support" then supports = supports + 1 end end
    local bad = unsupported(player.surface, plan, player.force)
    check(bad == 0, case.name .. ": elevated pieces out of the supports' reach: " .. bad)
    check(supports >= 3 and supports <= case.most, case.name .. ": " .. supports .. " supports")
    -- none of them is needless: without any one, some piece isn't carried
    local needless = 0
    for k, e in ipairs(plan.entities) do
      if e.name == "rail-support" then
        local without = { entities = {} }
        for m, f in ipairs(plan.entities) do if m ~= k then without.entities[#without.entities + 1] = f end end
        if unsupported(player.surface, without, player.force) == 0 then needless = needless + 1 end
      end
    end
    check(needless == 0, case.name .. ": supports that could go: " .. needless)
  end
  dev("set_checked", P, "ramps", true)
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

-- Surface conditions hold for every mode with ghosts: rails need gravity (none on
-- a space platform), so even super force places no rail ghosts without it.
local function rails_need_gravity()
  for _, c in pairs(prototypes.entity["straight-rail"].surface_conditions or {}) do
    if c.property == "gravity" then return true end
  end
  return false
end

-- On water, a forced build lays landfill only where each rail piece stands (the
-- game's own minimum, scripts/build/rail_data.lua), not the square around a curve.
step("on water: landfill just under the track", function(player)
  local s = player.surface
  clear_all(s)
  local water = {}
  for x = -90, 89 do for y = -90, 89 do water[#water + 1] = { name = "water", position = { x, y } } end end
  s.set_tiles(water)
  dev("click", P, "super_build") -- (two tracks here, overlapping at the bend: rails over rails)
end, "idle")

step("... the landfill ghosts are exactly the pieces' cells", function(player)
  local s = player.surface
  local expected, rails_planned = {}, 0
  for _, e in pairs(dev("plan", P).entities) do
    local offsets = e.track and dev("rail_cover", e.name, e.direction or 0)
    if offsets then
      rails_planned = rails_planned + 1
      for _, o in ipairs(offsets) do expected[math.floor(e.position.x + o[1]) .. "," .. math.floor(e.position.y + o[2])] = true end
    elseif not e.track and (e.size or 1) == 1 then
      expected[math.floor(e.position.x) .. "," .. math.floor(e.position.y)] = true
    end
  end
  local got, extra = {}, 0
  for _, g in pairs(s.find_entities_filtered { type = "tile-ghost" }) do
    if g.ghost_name == "landfill" then
      local key = math.floor(g.position.x) .. "," .. math.floor(g.position.y)
      got[key] = true
      if not expected[key] then extra = extra + 1 end
    end
  end
  local missing = 0
  for key in pairs(expected) do if not got[key] then missing = missing + 1 end end
  check(rails_planned > 10, "rail pieces planned: " .. rails_planned)
  check(extra == 0 and missing == 0, "landfill where the pieces stand: " .. extra .. " extra, " .. missing .. " missing")
  local rail_ghosts = 0
  for _, name in ipairs(RAILS) do rail_ghosts = rail_ghosts + #s.find_entities_filtered { ghost_name = name } end
  local lost = {}
  for _, e in pairs(dev("plan", P).entities) do
    if e.track and dev("rail_cover", e.name, e.direction or 0)
        and not s.find_entities_filtered { ghost_name = e.name, position = e.position, limit = 1 }[1] then
      lost[#lost + 1] = e.name .. "/" .. (e.direction or 0) .. "@" .. e.position.x .. "," .. e.position.y
    end
  end
  check(rail_ghosts == rails_planned, "every rail ghost placed: " .. rail_ghosts .. "/" .. rails_planned .. " " .. table.concat(lost, " "))
  clear_all(s)
  local grass = {}
  for x = -90, 89 do for y = -90, 89 do grass[#grass + 1] = { name = "grass-1", position = { x, y } } end end
  s.set_tiles(grass)
end)

step("no gravity: super force places no rail ghosts", function(player)
  if not rails_need_gravity() then return end
  local s = player.surface
  clear_all(s)
  storage.gravity = s.get_property("gravity")
  s.set_property("gravity", 0)
  dev("click", P, "super_build")
end, "idle")

step("... none, and the walls still there", function(player)
  if not rails_need_gravity() then return end
  local s = player.surface
  local rails = 0
  for _, name in ipairs(RAILS) do rails = rails + #s.find_entities_filtered { ghost_name = name } end
  check(rails == 0, "no rail ghosts without gravity: " .. rails)
  s.set_property("gravity", storage.gravity)
end)

flow.run("rails")
