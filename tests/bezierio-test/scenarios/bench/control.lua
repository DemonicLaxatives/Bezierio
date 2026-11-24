-- Measures how long Bézierio's jobs take per tick (wall clock, from log timestamps).
-- tests/run.sh bench, then read "BENCH" lines. Not part of the regular test run.
local P = 1
---@diagnostic disable-next-line: param-type-mismatch
local function dev(fn, ...) return remote.call("bezierio-dev", fn, ...) end
local phase, started_tick = "warmup", 0

local function mark(name) log("BENCH " .. name .. " tick=" .. game.tick) end

local function setup(player)
  local s = player.surface
  s.request_to_generate_chunks({ 0, 0 }, 10); s.force_generate_chunk_requests()
  local function find(el) if el.name == "bezierio_button" then return el end for _, c in pairs(el.children) do local f = find(c) if f then return f end end end
  dev("click", P, find(player.gui.top))
  dev("click", P, "pointer_button")
  for _, xy in ipairs({ { -250, 0 }, { -100, -280 }, { 100, 280 }, { 250, 0 } }) do dev("pointer", P, { x = xy[1], y = xy[2] }) end
  dev("click", P, "pointer_button")
  dev("set_elem", P, "layer_type", { name = "stone-wall", quality = "normal" })
  dev("set_value", P, "radius_slider", 6)
  dev("click", P, "add_layer_above")
  dev("set_elem", P, "layer_type", { name = "small-electric-pole", quality = "normal" })
  dev("click", P, "add_layer_below")
  dev("set_elem", P, "layer_type", { name = "stone-brick", quality = "normal" })
  dev("set_value", P, "radius_slider", 3)
end

script.on_event(defines.events.on_tick, function(e)
  local player = game.get_player(P)
  if phase == "warmup" and e.tick == 5 then
    setup(player)
    phase, started_tick = "idle", e.tick
    mark("idle-start")
  elseif phase == "idle" and e.tick - started_tick >= 300 then
    mark("idle-end")
    dev("click", P, "preview_build")
    phase, started_tick = "plan", e.tick
    mark("plan-start")
  elseif phase == "plan" and e.tick > started_tick + 15 and dev("idle", P) then
    mark("plan-end")
    local plan = dev("plan", P)
    local progress = dev("controller", P).work.draw
    log("BENCH plan entities=" .. #plan.entities .. " tiles=" .. #plan.tiles
      .. " preview drew " .. progress.preview_entities .. " entities, " .. progress.preview_tiles .. " tiles in "
      .. progress.preview_count .. " rectangles (render objects " .. dev("render_count") .. ")")
    if progress.preview_entities < #plan.entities or progress.preview_tiles < #plan.tiles then
      log("BENCH FAIL: preview incomplete")
      script.finish_test(false)
      return
    end
    player.cheat_mode = true
    dev("click", P, "build")
    phase, started_tick = "instant", e.tick
    mark("instant-start")
  elseif phase == "instant" and dev("idle", P) then
    mark("instant-end")
    for _, en in pairs(player.surface.find_entities_filtered { name = { "stone-wall", "small-electric-pole" } }) do en.destroy() end
    player.cheat_mode = false
    dev("click", P, "build")
    phase, started_tick = "ghost", e.tick
    mark("ghost-start")
  elseif phase == "ghost" and dev("idle", P) then
    mark("ghost-end")
    dev("click", P, "blueprint_build")
    phase, started_tick = "blueprint", e.tick
    mark("blueprint-start")
  elseif phase == "blueprint" then
    mark("blueprint-tick") -- per-tick timestamps: the last step writes the whole blueprint in one call
    -- wall time of each tick, to see the one-call write at the end
    if dev("idle", P) then
      mark("blueprint-end")
      log("BENCH blueprint entities=" .. player.cursor_stack.get_blueprint_entity_count())
      script.finish_test(true)
    end
  end
end)
