


script.on_configuration_changed(function()
    local types = {
        "artillery-turret",
        "ammo-turret",
        "electric-turret",
        "turret",
        "lamp",
        "wall",
        "accumulator",
        "land-mine",
        "electric-pole",
        "roboport",
        "heat-pipe",
        "pipe",
        "transport-belt",
        "tile",
    }

    local entity_filter = {
        {filter="type", type=types, mode="or"},
        {filter="blueprintable", mode="and"},
        {filter="hidden", invert=true, mode="and"},
    }

    local tile_filter = {
        {filter="blueprintable"},
    }

    local item_filter = {
        {filter = "place-result", elem_filters = entity_filter},
        {filter = "place-as-tile", elem_filters = tile_filter},
    }

    storage.item_filter = {{filter = "name", name = {}}}
            local items = prototypes.get_item_filtered(item_filter)
    for name, _ in pairs(items) do
        table.insert(storage.item_filter[1].name, name)
    end

end)



local lib = {}

return lib