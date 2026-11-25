-- Turret feeds and gates: inserters taking ammo from a belt, flamethrowers piped to
-- a pipe line (straight and diagonal), gates where a wall crosses a rail.
-- tests/run.sh feeds
local flow = require("__bezierio-test__/lib/flow")
local P, dev, check, el, step = flow.P, flow.dev, flow.check, flow.el, flow.step
local layers = flow.layers

local RAILS = { -35, -27 }
--- Away from the test rails (which cut the lines under them).
local function clear_of_rails(e)
  for _, x in ipairs(RAILS) do if math.abs(e.position.x - x) < 5 then return false end end
  return true
end

local function clear_all(s, keep_rails)
  for _, e in pairs(s.find_entities_filtered { area = { { -90, -90 }, { 90, 90 } } }) do
    if e.type ~= "character" and not (keep_rails and e.type == "straight-rail") then e.destroy() end
  end
end

step("setup: a straight stretch then a diagonal, rails across the wall", function(player)
  local s = player.surface
  flow.prepare_ground(s)
  s.request_to_generate_chunks({ 0, 0 }, 5); s.force_generate_chunk_requests()
  flow.open_window(player)
  dev("click", P, "pointer_button")
  -- points in line on both sides of -40..-20 keep that stretch exactly straight
  dev("pointer", P, { x = -52.5, y = 0.5 })
  dev("pointer", P, { x = -40.5, y = 0.5 })
  dev("pointer", P, { x = -20.5, y = 0.5 })
  dev("pointer", P, { x = -5.5, y = 0.5 })
  dev("pointer", P, { x = 45.5, y = 45.5 })
  dev("click", P, "pointer_button")
  dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
  check(layers()[0].gate_name == "gate" and el(player, "gates").state == true, "gates on by default")
  -- 3 wide, so a rail piece (2 wide) crossing it lies under wall only
  dev("set_value", P, "radius_slider", 2)

  dev("click", P, "add_layer_above")
  dev("set_elem", P, "layer_type", { name = "transport-belt", quality = "normal" })
  dev("click", P, "add_layer_above")
  dev("set_elem", P, "layer_type", { name = "gun-turret", quality = "normal" })
  dev("set_value", P, "offset_slider", 1)
  dev("set_elem", P, "inserter", "inserter")
  check(layers()[2].inserter_name == "inserter", "inserter chosen")
  dev("set_elem", P, "ammo", "firearm-magazine")
  -- (Packed side by side, some turrets on a diagonal have no room for an inserter;
  -- they're counted as unfed.)
  dev("set_value", P, "spacing_slider", 4)

  dev("click", P, "add_layer_below")
  dev("set_elem", P, "layer_type", { name = "pipe", quality = "normal" })
  dev("click", P, "add_layer_below")
  dev("set_elem", P, "layer_type", { name = "flamethrower-turret", quality = "normal" })
  dev("set_value", P, "offset_slider", 1)
  dev("set_value", P, "spacing_slider", 7)
  check(el(player, "pipe_feed") and not el(player, "inserter"), "pipe feed offered for fluid turrets")
  dev("set_checked", P, "pipe_feed", true)
  dev("click", P, "layer_select_0")

  -- two short vertical rails crossing the straight stretch's wall (and its belt);
  -- turrets beside them lose their feed, so the checks below leave them out
  for _, x in ipairs(RAILS) do
    s.create_entity { name = "straight-rail", position = { x, 0 }, force = player.force, direction = defines.direction.north }
  end
  storage.rails = s.count_entities_filtered { type = "straight-rail" }
  dev("click", P, "preview_build")
end, "idle")

step("plan: everything fed", function(player)
  local plan = dev("plan", P)
  -- At a bend a turret can be left with no cell for its inserter; those are counted.
  storage.unfed = plan.unfed
  check(plan.unfed <= 2, "at most a couple of unfed turrets: " .. plan.unfed)
  local items = el(player, "totals_items").caption
  check(items:find("[item=inserter]", 1, true), "inserters in the totals: " .. items)
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("inserters feed turrets from the belt", function(player)
  local s = player.surface
  local guns = s.find_entities_filtered { name = "gun-turret" }
  local inserters = s.find_entities_filtered { name = "inserter" }
  local checked, without = 0, 0
  for _, g in pairs(guns) do
    if clear_of_rails(g) then
      local feeding = false
      for _, ins in pairs(inserters) do
        if ins.drop_target == g then feeding = true end
      end
      if not feeding then without = without + 1 end
      checked = checked + 1
    end
  end
  check(checked > 10 and without <= storage.unfed, "turrets without an inserter (" .. without .. ") are the ones counted unfed (" .. storage.unfed .. ")")
  for _, ins in pairs(inserters) do
    if clear_of_rails(ins) then check(ins.drop_target and ins.drop_target.name == "gun-turret", "inserter drops into a turret at " .. ins.position.x .. "," .. ins.position.y)
    local pick = s.find_entities_filtered { position = ins.pickup_position, name = "transport-belt", limit = 1 }[1]
    check(pick, "inserter picks up from a belt at " .. ins.position.x .. "," .. ins.position.y)
    end
  end
end)

step("flamethrowers piped, straight and diagonal", function(player)
  local s = player.surface
  local flamers = s.find_entities_filtered { name = "flamethrower-turret" }
  local diagonal = 0
  -- (The rails cut the pipe line into pieces, so: is a pipe connected to it?)
  for _, f in pairs(flamers) do
    if f.direction % 4 ~= 0 then diagonal = diagonal + 1 end
    local piped = false
    for _, n in pairs(f.get_fluid_box_neighbours(1) or {}) do
      local other = n.entity
      if other and (other.name == "pipe" or other.name == "pipe-to-ground") then piped = true end
    end
    check(piped or not clear_of_rails(f), "flamethrower at " .. f.position.x .. "," .. f.position.y .. " (facing " .. f.direction .. ") has a pipe connected")
  end
  check(#flamers > 5 and diagonal > 2, "flamethrowers: " .. #flamers .. ", diagonal " .. diagonal)
end)

step("gates over the rails", function(player)
  local s = player.surface
  local gates = s.find_entities_filtered { name = "gate" }
  check(#gates >= 2 and s.count_entities_filtered { type = "straight-rail" } == storage.rails, "gates built, rails kept: " .. #gates)
  player.cheat_mode = false
  clear_all(s, true)
  dev("click", P, "super_build")
end, "idle")

step("superforced: gate ghosts, rails not deconstructed", function(player)
  local s = player.surface
  check(#s.find_entities_filtered { ghost_name = "gate" } >= 2, "gate ghosts")
  for _, r in pairs(s.find_entities_filtered { type = "straight-rail" }) do
    check(not r.to_be_deconstructed(), "rail at " .. r.position.x .. "," .. r.position.y .. " kept")
  end
end)

-- Unfed turrets are marked on the map after a build; the warning toggles the marks.
--- The mod's marks: icon sprites by name.
--- Marks with this icon in the world (and the same count on the map, checked).
local function marks(icon)
  local n, chart, ttl = 0, 0, nil
  for _, o in pairs(rendering.get_all_objects("Bezierio")) do
    if o.valid and o.type == "sprite" and o.sprite == icon then
      if o.render_mode == "chart" then chart = chart + 1 else n, ttl = n + 1, o.time_to_live end
    end
  end
  check(chart == n, "each mark on the map too: " .. chart .. " on the map, " .. n .. " in the world")
  return n, ttl
end

step("unfed: no belt, so the gun turrets go without", function(player)
  clear_all(player.surface)
  -- (with the preview off: a build shows the totals and warnings all the same)
  dev("click", P, "preview_build")
  check(not el(player, "preview_build").toggled, "preview off")
  dev("click", P, "layer_select_1")
  dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
  dev("click", P, "layer_select_0")
  player.cheat_mode = true
  dev("click", P, "build")
end, "idle")

step("unfed turrets marked for a minute", function(player)
  local plan = dev("plan", P)
  check(plan.unfed > 5 and #plan.unfed_at == plan.unfed, "unfed turrets recorded: " .. plan.unfed)
  local n, ttl = marks("utility/ammo_icon")
  check(n == plan.unfed, "an ammo mark on each: " .. n .. "/" .. plan.unfed)
  check(ttl and ttl > 3000 and ttl <= 3600, "they fade after a minute: " .. tostring(ttl))
  check(el(player, "totals_unfed").visible, "the warning is shown, preview off")
  check(el(player, "totals_items").caption ~= "", "the totals too")
  player.cheat_mode = false
  dev("click", P, "totals_unfed")
end, "idle")

step("clicking the warning hides them", function(player)
  check(marks("utility/ammo_icon") == 0, "marks gone")
  dev("set_setting", P, "highlight_seconds", 0)
  dev("click", P, "totals_unfed")
end, "idle")

step("... and shows them again (0 seconds: until hidden)", function(player)
  local n, ttl = marks("utility/ammo_icon")
  check(n == dev("plan", P).unfed and (ttl == nil or ttl == 0), "marks back, not fading: " .. n .. ", ttl " .. tostring(ttl))
  dev("set_setting", P, "highlight_seconds", 60)
  -- (the view settings redraw everything, but the plan stays)
  dev("click", P, "settings_button")
  dev("click", P, "view_reset")
  dev("click", P, "settings_button")
end, "idle")

step("marks stay when only the drawing is redone", function(player)
  check(marks("utility/ammo_icon") > 0 and el(player, "totals_unfed").visible, "marks and warning kept")
  dev("set_value", P, "radius_slider", 1)
end, "idle")

step("an edit drops the plan: warning and marks go together", function(player)
  -- (edited with the preview off: no plan, so no totals until the next build)
  check(not el(player, "totals_unfed").visible, "warning gone with the edit")
  check(marks("utility/ammo_icon") == 0, "marks gone with it")
  dev("click", P, "preview_build")
end, "idle")

step("preview on again: the warning is back, and its marks by default", function(player)
  check(el(player, "totals_unfed").visible, "warning shown")
  check(marks("utility/ammo_icon") == dev("plan", P).unfed, "marked without a click")
  dev("click", P, "totals_unfed")
end, "idle")

step("clicked off", function(player)
  check(marks("utility/ammo_icon") == 0, "marks hidden")
  dev("set_value", P, "radius_slider", 2)
end, "idle")

step("... they stay off for the next plan", function(player)
  check(el(player, "totals_unfed").visible and marks("utility/ammo_icon") == 0, "warning shown, no marks")
  dev("click", P, "totals_unfed")
end, "idle")

step("clicked on again: marked, and on by default once more", function(player)
  check(marks("utility/ammo_icon") == dev("plan", P).unfed, "marks for the new plan")
  check(flow.controller().ui.marks_off == nil, "nothing left turned off")
end)

flow.run("feeds")
