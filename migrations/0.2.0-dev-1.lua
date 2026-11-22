-- Development schema 2 -> 3 (0.2 dev builds only; removed before release).
-- Groundwork refactor: curve as {kind, points}; layer type "nil" is now "empty";
-- layers no longer store `priority`; UI state renamed; jobs area (rebuilt by
-- on_configuration_changed).
if storage.schema_version ~= 2 then return end

local function empty_layer(idx) return { idx = idx, type = "empty", size = 1, offset = 0 } end

for player_index, old in pairs(storage.controllers or {}) do
  local old_ui = old.state or {}
  local old_curve = (old.curve_cache or {})[0] or {}
  local points = {}
  for idx, point in pairs(old_curve.raw_control_points or {}) do
    points[idx] = { x = point.x, y = point.y }
  end
  local presets = {}
  for i, preset in pairs(old.presets or {}) do
    local layers = {}
    for k, layer in pairs(preset.layers or {}) do
      if layer.type == "nil" then layer.type = "empty" end
      layer.priority = nil
      layers[k] = layer
    end
    if not layers[0] then layers[0] = empty_layer(0) end
    presets[i] = { name = preset.name or "Default", layers = layers }
  end
  if not presets[1] then presets[1] = { name = "Default", layers = { [0] = empty_layer(0) } } end

  storage.controllers[player_index] = {
    ui = {
      preset_index = old_ui.preset_indx or 1,
      draw_curve = old_ui.draw_curve or false,
      preview_build = old_ui.preview_build or false,
      active_control_point = old_ui.active_control_point,
    },
    curve = { kind = "bezier", points = points },
    presets = presets,
    revision = 1,
    redraw = true,
  }
end
storage.sprites = {}
storage.schema_version = 3
storage.rebuild_needed = true
