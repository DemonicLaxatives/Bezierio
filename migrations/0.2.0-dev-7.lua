-- Development schema 8 -> 9 (0.2 dev builds only; removed before release).
-- Red and green wire are separate settings: connect_with_circuit_wires becomes
-- red_wire and green_wire (poles and land mines).
if storage.schema_version ~= 8 then return end

for _, controller in pairs(storage.controllers or {}) do
  for _, preset in pairs(controller.presets or {}) do
    for _, layer in pairs(preset.layers or {}) do
      if layer.connect_with_circuit_wires ~= nil then
        layer.red_wire = layer.connect_with_circuit_wires
        layer.green_wire = layer.connect_with_circuit_wires
        layer.connect_with_circuit_wires = nil
      end
    end
  end
end
storage.schema_version = 9
storage.rebuild_needed = true
