-- How far each pipe's pipelines may reach (FluidBox::max_pipeline_extent). The
-- runtime API doesn't expose it, so record it here for the pipe layers' pump
-- spacing: prototypes.mod_data["bezierio-pipeline-extent"].data[entity name].
local default = data.raw["utility-constants"]["default"].default_pipeline_extent or 320
local extents = {}
for _, kind in ipairs({ "pipe", "pipe-to-ground", "pump" }) do
  for name, entity in pairs(data.raw[kind] or {}) do
    local box = entity.fluid_box
    extents[name] = box and box.max_pipeline_extent or default
  end
end
data:extend {
  { type = "mod-data", name = "bezierio-pipeline-extent", data = { default = default, extents = extents } },
}
