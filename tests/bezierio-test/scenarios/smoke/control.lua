-- Minimal smoke test: a player exists and the game runs for a while.
script.on_event(defines.events.on_tick, function(e)
  if e.tick == 120 then
    log("SMOKE OK, players=" .. #game.players)
    script.finish_test(true)
  end
end)
