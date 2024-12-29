for i = 1, 9 do
  local button = {
    type = "item",
    name = "bezierio-pointer-"..i,
    icon = "__Bezierio__/graphics/icons/pointer-" .. i .. ".png",
    icon_size = 64,
    flags = {"only-in-cursor", "spawnable", "not-stackable"},
    subgroup = "other",
    order = "a[bezierio-pointer-"..i.."]",
    stack_size = 1
  }
  data:extend{button}
end