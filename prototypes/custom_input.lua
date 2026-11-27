data:extend {
  -- With the pointer in hand: click a point to select it; with a point selected,
  -- click to move it there; otherwise click to add a point at the end.
  {
    type = "custom-input",
    name = "bezierio-pointer",
    key_sequence = "mouse-button-1",
    consuming = "none",
  },
  -- With the pointer in hand: add a point into the nearest stretch of curve.
  {
    type = "custom-input",
    name = "bezierio-pointer-insert",
    key_sequence = "SHIFT + mouse-button-1",
    consuming = "none",
  },
  -- With the pointer in hand: deselect the selected point, or remove the point
  -- under the cursor.
  {
    type = "custom-input",
    name = "bezierio-pointer-remove",
    key_sequence = "mouse-button-2",
    consuming = "none",
  },
  -- With the pointer in hand and a point selected: select the next / previous point.
  {
    type = "custom-input",
    name = "bezierio-select-next",
    key_sequence = "ALT + mouse-wheel-down",
    consuming = "none",
  },
  {
    type = "custom-input",
    name = "bezierio-select-previous",
    key_sequence = "ALT + mouse-wheel-up",
    consuming = "none",
  },
  -- The game's Confirm (E by default, as the player has it bound): in the layer
  -- settings window, OK. (Linked controls aren't listed in the controls settings.)
  {
    type = "custom-input",
    name = "bezierio-confirm-gui",
    key_sequence = "",
    linked_game_control = "confirm-gui",
    consuming = "none",
  },
  -- Take the pointer.
  {
    type = "custom-input",
    name = "bezierio-get-pointer",
    key_sequence = "ALT + Z",
    consuming = "game-only",
    action = "spawn-item",
    item_to_spawn = "bezierio-pointer",
  },
}
