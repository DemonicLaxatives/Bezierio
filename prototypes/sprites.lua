-- GUI icons.
--
-- The build buttons use the game's ghost cursor art. In the cursor sprites it sits
-- in the top-right corner of the 64px image, so take a square around it to centre it.
local function cursor_icon(name, file)
  return {
    type = "sprite",
    name = name,
    filename = "__core__/graphics/icons/mip/" .. file,
    position = { 24, 0 },
    size = 40,
    scale = 0.5,
    flags = { "gui-icon" },
  }
end

data:extend {
  cursor_icon("bezierio-force-build", "cursor-ghost.png"),
  cursor_icon("bezierio-super-force-build", "cursor-super-force-ghost.png"),
  {
    type = "sprite",
    name = "bezierio-reverse",
    filename = "__Bezierio__/graphics/icons/reverse.png",
    size = 32,
    scale = 0.5,
    flags = { "gui-icon" },
  },
}

-- Colour swatches for the view settings menus: a white square tinted per colour.
local palette = require("scripts.palette")
for _, entry in ipairs(palette.NAMED) do
  data:extend {
    {
      type = "sprite",
      name = "bezierio-color-" .. entry.name,
      filename = "__Bezierio__/graphics/icons/swatch.png",
      size = 32,
      scale = 0.5,
      tint = entry.color,
      flags = { "gui-icon" },
    },
  }
end

data:extend {
  {
    type = "sprite",
    name = "bezierio-mirror",
    filename = "__Bezierio__/graphics/icons/mirror.png",
    size = 32,
    scale = 0.5,
    flags = { "gui-icon" },
  },
}
