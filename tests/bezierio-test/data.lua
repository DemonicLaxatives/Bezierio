-- Test-only prototypes, standing in for what other mods add.
--   bezierio-test-long-pump: a 1x3 pump, input and output in line (fits a pipe line)
--   bezierio-test-wide-pump: a 2x2 pump (doesn't: refused by the pipe layer's pump picker)

local function pump(name, collision, selection, output_at, input_at)
    local entity = table.deepcopy(data.raw["pump"]["pump"])
    entity.name = name
    entity.minable = { mining_time = 0.2, result = name }
    entity.collision_box, entity.selection_box = collision, selection
    entity.fast_replaceable_group = nil
    entity.next_upgrade = nil
    -- (the base pump's: output north, input south; moved to the new ends)
    local connections = entity.fluid_box.pipe_connections
    connections[1].position, connections[2].position = output_at, input_at
    local item = table.deepcopy(data.raw["item"]["pump"])
    item.name, item.place_result, item.order = name, name, "b[pipe]-c[pump]-z[" .. name .. "]"
    data:extend({ entity, item })
end

pump("bezierio-test-long-pump", { { -0.29, -1.4 }, { 0.29, 1.4 } }, { { -0.5, -1.5 }, { 0.5, 1.5 } }, { 0, -1 }, { 0, 1 })
pump("bezierio-test-wide-pump", { { -0.9, -0.9 }, { 0.9, 0.9 } }, { { -1, -1 }, { 1, 1 } }, { -0.5, -0.5 }, { -0.5, 0.5 })
