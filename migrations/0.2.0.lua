-- 0.1.x -> 0.2.0: the curve projector building is gone and the data has nothing in
-- common with 0.2, so 0.1 data is discarded. Saves from 0.2 development builds
-- (schema_version set) are upgraded by the 0.2.0-dev-*.lua files instead, which
-- sort before this one.
--
-- Migrations run once per save, also when the mod is first added (after on_init),
-- so this must do nothing on data that is already current.
if storage.schema_version ~= nil then return end

rendering.clear(script.mod_name)
for _, player in pairs(game.players) do
  local window = player.gui.screen.bezierio_window
  if window then window.destroy() end
end
for key in pairs(storage) do storage[key] = nil end
storage.controllers = {}
storage.sprites = {}
storage.schema_version = 5
storage.rebuild_needed = true
