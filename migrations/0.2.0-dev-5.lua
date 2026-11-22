-- Development schema 6 -> 7 (0.2 dev builds only; removed before release).
-- Curves get shape kinds: handles for each shape and a `reversed` flag. The shape
-- tools pane's values (ui.shape) are gone.
if storage.schema_version ~= 6 then return end

for _, controller in pairs(storage.controllers or {}) do
  local curve = controller.curve
  if curve then
    curve.handles = curve.handles or { circle = {}, ellipse = {}, arc = {} }
    if curve.reversed == nil then curve.reversed = false end -- (a table since schema 8)
  end
  controller.ui.shape = nil
end
storage.schema_version = 7
storage.rebuild_needed = true
