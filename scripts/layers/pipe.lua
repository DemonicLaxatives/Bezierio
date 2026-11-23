local common = require("scripts.layers.common")

--- Pipes: one or more lines along the band, each a continuous chain of cells
--- following the curve (see build/paths.lua). Lines keep at least one empty cell
--- between them (pipes connect to every neighbour). Long straight runs can go
--- underground, and pumps can split long pipelines: a pipeline can only span its
--- fluidboxes' max_pipeline_extent (320 tiles by default), so the pump spacing
--- stays below it.
--- @type LayerType
return {
    name = "pipe",
    entity_types = { "pipe" },
    placement = "path",
    output = "entity",
    priority = 90,
    fields = {
        common.lines,
        { name = "line_gap", widget = "slider", min = 1, max = 3, default = 1 },
        { name = "undergrounds", widget = "checkbox", default = false },
        { name = "pumps", widget = "checkbox", default = false },
        {
            -- Up to the pipeline's extent limit, less the pump's own two cells.
            name = "pump_spacing", widget = "slider", min = 20,
            max = function(layer) return math.max(20, (layer.pipeline_extent or 320) - 2) end,
            default = function(layer) return math.max(20, (layer.pipeline_extent or 320) - 2) end,
            visible_if = function(layer) return layer.pumps == true end,
        },
        {
            name = "flow", widget = "choice", options = { "forward", "backward" }, label_prefix = "bezierio-flow", default = "forward",
            visible_if = function(layer) return layer.pumps == true end,
        },
    },
    thickness = common.path_thickness,
    --- @param layer Layer
    --- @param prototype LuaEntityPrototype
    init = function(layer, prototype)
        local underground = prototypes.entity[prototype.name .. "-to-ground"]
        if underground and underground.type ~= "pipe-to-ground" then underground = nil end
        layer.underground_name = underground and underground.name or nil
        layer.underground_item = underground and common.item_for(underground) or nil
        layer.underground_distance = underground and underground.max_underground_distance or nil
        local pump = prototypes.entity["pump"]
        layer.pump_name = pump and pump.name or nil
        layer.pump_item = pump and common.item_for(pump) or nil
        -- A pipeline reaches as far as its most limited fluidbox allows
        -- (recorded in data-final-fixes.lua).
        local record = prototypes.mod_data["bezierio-pipeline-extent"]
        local extents = record and record.data.extents or {}
        local default = record and record.data.default or 320
        local extent = extents[prototype.name] or default
        if underground then extent = math.min(extent, extents[underground.name] or default) end
        layer.pipeline_extent = extent
    end,
}
