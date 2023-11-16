data:extend{
    {
        type = "technology",
        name = "curve-projector",
        icon = "__Bezierio__/graphics/technology/curve-projector.png",
        icon_size = 256,
        order = "b",
        prerequisites = {
          "circuit-network",
        },
        unit = {
            count = 200,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1},
            },
            time = 30
        },
        effects = {
          { type = "unlock-recipe", recipe = "curve-projector" },
        },
    }
}