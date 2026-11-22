--- Rails: selectable and configurable, but the planner can't build them yet.
--- Building them means fitting 2.0 rail pieces ("straight-rail", "half-diagonal-rail",
--- "curved-rail-a", "curved-rail-b") to the curve.
--- @type LayerType
return {
    name = "straight-rail",
    entity_types = { "straight-rail" },
    placement = "unsupported",
    output = "entity",
    priority = 1,
    fields = {
        {
            name = "direction_of_travel", widget = "slider", min = -1, max = 1, default = 1,
            labels = {
                [-1] = { "label.direction-backwards" },
                [0] = { "label.direction-neither" },
                [1] = { "label.direction-forwards" },
            },
        },
        { name = "signal_spacing", widget = "slider", min = 0, max = 6, default = 1 },
    },
}
