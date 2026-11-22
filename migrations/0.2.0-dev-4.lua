-- Development schema 5 -> 6 (0.2 dev builds only; removed before release).
-- Layers get `needs_power` and pole layers `smart`, both filled in by the rebuild
-- (registry.refresh and the field default); nothing to convert here.
if storage.schema_version ~= 5 then return end

storage.schema_version = 6
storage.rebuild_needed = true
