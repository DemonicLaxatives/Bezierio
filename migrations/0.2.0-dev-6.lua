-- Development schema 7 -> 8 (0.2 dev builds only; removed before release).
-- Reversing no longer reorders a spline's points: each kind has its own direction
-- flag (curve.reversed[kind]). The old flag was one boolean for all shapes.
if storage.schema_version ~= 7 then return end

for _, controller in pairs(storage.controllers or {}) do
  local curve = controller.curve
  if curve and type(curve.reversed) ~= "table" then
    local old = curve.reversed == true
    curve.reversed = {}
    if old then
      curve.reversed.circle, curve.reversed.ellipse, curve.reversed.arc = true, true, true
    end
  end
end
storage.schema_version = 8
storage.rebuild_needed = true
