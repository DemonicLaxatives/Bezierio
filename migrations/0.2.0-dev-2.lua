-- Development schema 3 -> 4 (0.2 dev builds only; removed before release).
-- Catmull-Rom curves: control points become a plain list (unset and half-entered
-- slots are dropped), curves get a `closed` flag, and the numbered pointers are
-- replaced by one pointer. Entity sizes come from the prototype's tile footprint
-- (rounded collision boxes made 1x1 entities 2x2).
if storage.schema_version ~= 3 then return end

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

for _, controller in pairs(storage.controllers or {}) do
  local old = controller.curve or {}
  local slots = {}
  for idx, point in pairs(old.points or {}) do
    if point.x and point.y then table.insert(slots, idx) end
  end
  table.sort(slots)
  local points = {}
  for _, idx in ipairs(slots) do
    table.insert(points, { x = round2(old.points[idx].x), y = round2(old.points[idx].y) })
  end
  controller.curve = { kind = "catmull_rom", points = points, closed = false }
  controller.ui.active_control_point = nil
  controller.ui.held_point = nil
  controller.ui.selected_layer = 0
  for _, preset in pairs(controller.presets or {}) do
    for _, layer in pairs(preset.layers or {}) do
      local prototype = layer.name and prototypes.entity[layer.name]
      if prototype and layer.type ~= "tile" then
        layer.size = math.max(1, prototype.tile_width, prototype.tile_height)
        if type(layer.spacing) == "number" then layer.spacing = math.max(layer.size, layer.spacing) end
      end
    end
  end
  controller.revision = (controller.revision or 0) + 1
end
storage.schema_version = 4
storage.rebuild_needed = true
