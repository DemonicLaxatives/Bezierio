data:extend {
  -- With the pointer in hand: click empty ground to add a point, click a point to
  -- pick it up, click again to drop it.
  {
    type = "custom-input",
    name = "bezierio-pointer",
    key_sequence = "mouse-button-1",
    consuming = "none",
  },
  -- With the pointer in hand: remove the point under the cursor (or put a held
  -- point back).
  {
    type = "custom-input",
    name = "bezierio-pointer-remove",
    key_sequence = "mouse-button-2",
    consuming = "none",
  },
  -- Take the pointer.
  {
    type = "custom-input",
    name = "bezierio-get-pointer",
    key_sequence = "ALT + B",
    consuming = "game-only",
    action = "spawn-item",
    item_to_spawn = "bezierio-pointer",
  },
}
