-- The curve pointer: held in the cursor to place, move and remove control points.
data:extend {
  {
    type = "item",
    name = "bezierio-pointer",
    icon = "__Bezierio__/graphics/icons/pointer.png",
    icon_size = 64,
    flags = { "only-in-cursor", "spawnable", "not-stackable" },
    subgroup = "other",
    order = "a[bezierio-pointer]",
    stack_size = 1,
  },
}
