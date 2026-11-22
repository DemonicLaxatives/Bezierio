-- Development schema 4 -> 5 (0.2 dev builds only; removed before release).
-- A point picked up by the pointer stays selected after it is moved
-- (held_point -> selected_point). View settings are filled in with defaults by
-- on_configuration_changed.
if storage.schema_version ~= 4 then return end

for _, controller in pairs(storage.controllers or {}) do
  controller.ui.selected_point = controller.ui.held_point
  controller.ui.held_point = nil
end
storage.schema_version = 5
storage.rebuild_needed = true
