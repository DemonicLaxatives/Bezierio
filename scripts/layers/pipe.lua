local common = require("scripts.layers.common")

--- How many cells a pump takes along a pipe line, or nil if it doesn't fit in one:
--- one tile wide, with just two pipe connections, the input at its back and the
--- output at its front, in line (facing north: output north at the top cell,
--- input south at the bottom one). The base game's pump is 1 x 2.
--- @param pump LuaEntityPrototype|nil
--- @return integer|nil
local function pump_length(pump)
    if not (pump and pump.type == "pump") or pump.tile_width ~= 1 then return nil end
    local length = pump.tile_height
    local front, back, count = false, false, 0
    for _, box in ipairs(pump.fluidbox_prototypes or {}) do
        for _, connection in ipairs(box.pipe_connections or {}) do
            if connection.connection_type == "normal" then
                count = count + 1
                local p = connection.positions and connection.positions[1]
                local x, y = p and (p.x or p[1]), p and (p.y or p[2])
                local edge = length / 2 - 0.5
                if x and math.abs(x) < 0.01 then
                    if connection.direction == 0 and math.abs(y + edge) < 0.01 and connection.flow_direction ~= "input" then front = true end
                    if connection.direction == 8 and math.abs(y - edge) < 0.01 and connection.flow_direction ~= "output" then back = true end
                end
            end
        end
    end
    return (count == 2 and front and back) and length or nil
end

--- The pump an item places, if it fits in a pipe line.
--- @param item_name string|nil
--- @return LuaEntityPrototype|nil, integer|nil
local function pump_of(item_name)
    local item = item_name and prototypes.item[item_name]
    local pump = item and item.place_result
    local length = pump_length(pump)
    if length then return pump, length end
    return nil, nil
end

--- The pump to use when none is chosen: the base game's, else the first (by name)
--- that fits in a pipe line.
--- @return string|nil
local function default_pump()
    if not prototypes then return nil end
    if pump_of("pump") then return "pump" end
    local names = {}
    for name in pairs(prototypes.get_item_filtered { { filter = "place-result", elem_filters = { { filter = "type", type = "pump" } } } }) do
        if pump_of(name) then names[#names + 1] = name end
    end
    table.sort(names)
    return names[1]
end

--- Pipes: one or more lines along the band, each a continuous chain of cells
--- following the curve (see build/paths.lua). Lines keep at least one empty cell
--- between them (pipes connect to every neighbour). Long straight runs can go
--- underground, and pumps can split long pipelines: a pipeline can only span its
--- fluidboxes' max_pipeline_extent (320 tiles by default), so the pump spacing
--- stays below it. The pump is the player's pick among those that fit in the line
--- (see pump_length), the base game's by default.
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
            name = "pump", widget = "item", default = default_pump,
            item_filters = { { filter = "place-result", elem_filters = { { filter = "type", type = "pump" } } } },
            visible_if = function(layer) return layer.pumps == true end,
            --- Only pumps that fit in the line.
            valid = function(_, value)
                if not prototypes then return true end
                return pump_of(value) ~= nil
            end,
        },
        {
            -- Up to the pipeline's extent limit, less the pump's own cells.
            name = "pump_spacing", widget = "slider", min = 20,
            max = function(layer) return math.max(20, (layer.pipeline_extent or 320) - (layer.pump_length or 2)) end,
            default = function(layer) return math.max(20, (layer.pipeline_extent or 320) - (layer.pump_length or 2)) end,
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
        -- The chosen pump (none chosen, or one a mod took away: the default).
        if not pump_of(layer.pump) then layer.pump = default_pump() end
        local pump, length = pump_of(layer.pump)
        layer.pump_name = pump and pump.name or nil
        layer.pump_item = pump and layer.pump or nil
        layer.pump_length = length
        layer.pump_power = pump and pump.electric_energy_source_prototype ~= nil
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
