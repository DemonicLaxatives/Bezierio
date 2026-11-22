# Bézierio: developer notes

## Layout

```
info.json, data.lua, control.lua   mod entry points
prototypes/
  items.lua              bezierio-pointer-1..9: cursor-only items marking control points
  custom-input.lua       left click with a pointer, Alt+1..9, Alt+scroll
scripts/
  state.lua              *the* definition of `storage` and its accessors (start here)
  init.lua               on_init / on_configuration_changed / player created/removed, mod-gui button
  custom-input.lua       pointer click / cycle handlers, keeps P-buttons in sync with the cursor
  draw.lua               all rendering (curve, control points, build preview); redraws dirty players every 5 ticks
  dev.lua                remote interface for the test scenarios (only when `bezierio-test` is active)
  debug.lua              debug.print etc.; `lib.debug` should be false for releases
  vector_math.lua        2D vector helpers
  curve_math/
    calc.lua             De Casteljau evaluation, adaptive sampling (+ unused offset/round helpers)
    control.lua          control points -> curve (ordering, relative to p0), world-space samples
  build/
    buildable_types.lua  layer data (one constructor per supported entity type) + editable field ranges
    builder.lua          curve + layers -> BuildPlan -> ghosts
    utils.lua            prototype lookups, item filter for the layer pickers
  gui/
    interactions.lua     routes every GUI event to lib[tags.group][tags.action](event)
    layout.lua           main window (group "main")
    control.lua          Draw / Preview / Build buttons (group "control")
    curve_control.lua    control point table (group "curve")
    buildable_layers.lua builds the layer rows
    layer_control.lua    layer actions (group "layer")
  constants/rails.lua    stub for future rail support
python_scripts/          offline experiments (sympy/numpy notebooks, icon generation); not used by the mod
tests/                   see Testing
```

## Storage

All state is per player and lives in `storage.controllers[player_index]`, with the
shape documented at the top of `scripts/state.lua`:

```
controller.state         UI state: toggles, active control point, `dirty` flag
controller.curve_cache[0] the curve: raw_control_points (sparse 1..9), p0, control_points (relative), degree
controller.presets[i].layers[k]   layer k (… -1, 0, 1 …) -> Buildable (plain data, prototypes by name)
storage.sprites[player_index]     LuaRenderObjects by group: curve / control_points / preview
storage.item_filter               ItemPrototypeFilter for the layer pickers
storage.schema_version
```

Always go through `state.get/ui/curve/layers/sprites`. They create missing data
lazily and call `state.ensure()`, which **discards** storage that has a different
`schema_version`. Bump `SCHEMA_VERSION` whenever the layout changes. If old data is
ever worth keeping, write a migration in `ensure()` instead of discarding it.

## GUI events

`gui/interactions.lua` sends each GUI event to `lib[tags.group][tags.action]`, but
only for the element types listed in `routed_types`:

- clicks → buttons;
- elem changed → choose-elem-buttons;
- confirmed → textfields;
- value changed → sliders;
- checked state changed → checkboxes.

Every element raises `on_gui_click`. Without this filter, clicking an item picker
ran its "type changed" action, which rebuilt the row and destroyed the picker
before it could open. Pointer clicks (`bezierio-pointer`) are ignored when the
event has `in_gui` or an `element` set. `element` alone isn't enough: slider clicks
don't report one.

Changes that need a redraw call `state.mark_dirty(player_index)`. `draw.lua`
redraws dirty players from its 5-tick loop. Keep drawing (and any heavy
calculation) out of GUI/input events: work belongs in the tick loop so it can be
spread over ticks. Unpause the map editor when testing.

## How the builder works (`scripts/build/builder.lua`)

1. **Sample** the curve so that no step exceeds 0.25 tiles. Each sample gets a
   tangent `t`, a normal `n` (to the right of the travel direction) and
   `w = |n.x| + |n.y|`.
2. **Distances are in grid units**: `u = d / w`. `w` is the width of one grid cell
   projected onto the normal, so a band 1 unit wide is a 4-connected staircase on
   diagonals. Walls never join only at corners.
3. **Layers become bands** `[lo, hi)` of `u`. Layer 0 is centred. ±k stack
   outward, each starting `offset` after the previous one. Thickness is
   `2·radius−1` for layer 0 walls/tiles, `radius` for side walls/tiles, and the
   entity size for spaced entities.
4. **Rasterize**: sweep cells near the curve and compute each cell centre's `u`.
   - Exact nearest sample via a spatial hash. Where the curve passes near itself,
     the branch with the smallest |u| wins.
   - `u` is quantized to 1/1024 so exact ties on rational slopes fall
     deterministically into one band.
   - Each cell gets at most one band, so layers never overlap.
5. **Walls/tiles** take their band's cells (checkerboard applied). **Spaced
   entities** walk the band's centre line by arc length. Each tries the 4 nearest
   grid-aligned positions and is skipped if all of them collide. Entities (walls
   first, then by `priority`) compete for cells; tiles are a separate plane.
6. **Execute**: tile and entity ghosts via `create_entity`.
   - Placement is checked with the real entity name and
     `build_check_type.manual_ghost, forced = true`.
   - Don't check with `name = "entity-ghost", inner_name = …`: in 2.1.24 that
     rejects free spots west/north of existing walls.

Known geometric limits: on the inside of a bend tighter than a side layer's
distance from the curve, that layer splits (there is no room there). A near-cusp
can leave a stray 1–2 cell piece.

## Testing

Requires a local Factorio 2.1 install (default `~/Games/factorio`; override with `FACTORIO=`).

```sh
tests/run.sh smoke                     # loads, runs 120 ticks with a player
tests/run.sh gui-flow                  # full UI flow: points, layers, preview, both build modes
tests/run.sh gui-flow space-age quality elevated-rails   # same, with DLC mods enabled
lua5.4 tests/unit/plan_properties.lua 300 [seed]          # random curves: planner invariants
```

- `run.sh` creates a throwaway config, write-data and mod folder (`WORKDIR=` to
  keep them), so it doesn't touch your game, and can run while the game is open.
- Scenarios use `--test-scenario`, which runs headless with one player. They drive
  the real GUI handlers through the `bezierio-dev` remote interface. Scripts can't
  click elements or fire custom inputs, so `dev.lua` imitates what the engine does
  first (e.g. flipping auto-toggle buttons).
- To add a scenario: create `tests/bezierio-test/scenarios/<name>/control.lua` and
  end with `script.finish_test(true|false)`.

The `tests/` and `python_scripts/` folders sit inside the mod folder; leave them out
of release zips.
