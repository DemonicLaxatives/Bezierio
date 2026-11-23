-- GUI styles.
local styles = data.raw["gui-style"].default

-- Lists (points, layers): a table whose odd rows are shaded, as in the game's own
-- lists (the same graphic).
styles.bezierio_striped_table = {
  type = "table_style",
  parent = "table",
  horizontal_spacing = 8,
  vertical_spacing = 0,
  top_cell_padding = 2,
  bottom_cell_padding = 2,
  left_cell_padding = 4,
  right_cell_padding = 4,
  odd_row_graphical_set = {
    filename = "__core__/graphics/gui-new.png",
    position = { 472, 25 },
    size = 1,
  },
}

-- The control points as chips (narrow window): a tighter grid, shaded the same.
styles.bezierio_striped_chips = {
  type = "table_style",
  parent = "bezierio_striped_table",
  horizontal_spacing = 4,
  left_cell_padding = 2,
  right_cell_padding = 2,
}

-- The add-layer bars above and below the layer list: full width, low.
styles.bezierio_add_bar = {
  type = "button_style",
  parent = "button",
  height = 18,
  minimal_width = 0,
  padding = 0,
  font = "default-bold",
  horizontally_stretchable = "on",
}

-- The control points as chips (narrow window).
styles.bezierio_point_chip = {
  type = "button_style",
  parent = "button",
  height = 24,
  minimal_width = 30,
  horizontally_stretchable = "on",
  padding = 0,
  font = "default-bold",
}
