# Bézierio: developer notes

## Layout

```
info.json, data.lua, control.lua   mod entry points
prototypes/
  items.lua              bezierio-pointer-1..9: cursor-only items marking control points
  custom_input.lua       left click with a pointer, Alt+1..9, Alt+scroll
scripts/
  state.lua              the definition of `storage`, accessors, migrations (start here)
  jobs.lua               per-tick runner: planning, drawing, building, within a budget
  draw.lua               rendering: control points, curve, build preview
  init.lua               on_init / on_configuration_changed / players, mod-gui button
  custom_input.lua       pointer click / cycle handlers, keeps P-buttons in sync with the cursor
  dev.lua                remote interface for the test scenarios (only when `bezierio-test` is active)
  debug.lua              debug.print; `lib.debug` should be false for releases
  vector_math.lua        2D vector helpers
  curve/
    curve.lua            curve data ({kind, points}) and resumable sampling
    bezier.lua           the "bezier" kind: one Bézier through all points
  layers/
    registry.lua         layer types: lookup, fields, new layers, item picker filter
    common.lua           pieces shared by layer types
    empty.lua wall.lua tile.lua electric_pole.lua electric_turret.lua roboport.lua rail.lua
  build/
    geometry.lua         frames, spatial index, grid distance from the curve
    planner.lua          curve + layers -> BuildPlan, as a resumable job
    executor.lua         BuildPlan -> world, as a resumable job
    outputs/ghost.lua    ... as ghosts
    outputs/instant.lua  ... as real entities (map editor, cheat mode)
  gui/
    interactions.lua     routes GUI events to lib[tags.group][tags.action](event)
    layout.lua           main window (group "main")
    control.lua          Draw / Preview / Build buttons (group "control")
    curve_control.lua    control point table (group "curve")
    layer_rows.lua       builds the layer rows from the registry
    layer_control.lua    layer actions (group "layer")
python_scripts/          offline experiments (sympy/numpy notebooks, icon generation); not used by the mod
tests/                   see Testing
```

## How work flows

GUI and input handlers never plan, draw or build. They change data and say what
changed:

- `state.changed(i)`: the curve or the layers changed. This bumps
  `controller.revision`; the plan is redone.
- `state.request_redraw(i)`: only the view changed (Draw / Preview toggles).
- `state.request_build(i, mode)`: build once the plan for the current revision is
  ready.

`jobs.lua` runs every tick and, per player, spends a budget of work units
(`jobs.BUDGET`):

1. **Reset if needed.** On a new revision, drop the plan and redraw. On a redraw
   request, clear the render objects and redraw the control points (≤ 9, cheap).
2. **Draw.** Draw what the planner has produced so far, using at most
   `DRAW_SHARE` of the budget.
3. **Plan.** Advance the planner: only up to the curve samples when just the curve
   is shown; the whole plan when the preview is on or a build is waiting.
4. **Build.** Start a waiting build when its plan is done, then advance the build
   job.

Heavy work is never done in a single tick. Every job is plain data in
`storage.controllers[i].work`: no closures or coroutines. So jobs survive
save/load and run identically on every multiplayer peer. Costs per operation
are in each module's `COST` table, and the budget counts work units, not time,
which keeps it deterministic.

The map editor starts with ticks paused, and then nothing happens. Unpause it
when testing.

## Storage

The shape is documented at the top of [scripts/state.lua](../scripts/state.lua):

```
storage.schema_version
storage.controllers[player_index]
    ui        preset_index, draw_curve, preview_build, active_control_point
    curve     {kind = "bezier", points = {[n] = {x, y}}}   (sparse; half-entered points allowed)
    presets   {{name, layers = {[k] = Layer}}}             (layer k: … -1, 0, 1 …)
    revision  bumped on curve/layer changes
    redraw    view needs redrawing
    work      jobs: plan (PlannerJob), draw progress, pending_build, build (BuildJob)
storage.sprites[player_index]   LuaRenderObjects: curve / control_points / preview
storage.item_filter             ItemPrototypeFilter for the layer pickers
```

Always go through the `state` accessors.

**Changing the layout:**
1. Bump `SCHEMA_VERSION`.
2. Add `MIGRATIONS[old_version]`, which upgrades storage by one version.
3. Add a case to `tests/unit/migrations.lua`.

`state.ensure()` runs the migrations in order. Data with no migration path
(0.1.x, or a newer version) is discarded.

## Layer types

A layer type is one file in `scripts/layers/`, listed in `TYPE_FILES` in
`registry.lua`. It declares:

- `entity_types` (or `tile = true`): which picked items select this type;
- `placement`:
  - `"band"`: fills its band (walls, tiles);
  - `"spaced"`: entities every `spacing` tiles along the band's middle;
  - `"unsupported"`: shown, but skipped when building (rails, for now);
  - `"none"`: builds nothing (empty);
- `output` (`"entity"` or `"tile"`) and `priority` (higher claims contested cells
  first);
- `fields`: editable settings with widget, min/max (number or function of the
  layer), default and optional word labels. The GUI builds its controls from
  these;
- `init(layer, prototype)` for derived values (e.g. pole wire reach), and
  `thickness(layer)` if the band width isn't the footprint size.

Layers are plain data. They name prototypes rather than holding them, so saves
survive mods changing prototypes.

## How the planner works (`scripts/build/planner.lua`, `geometry.lua`)

1. **Sample** the curve so that no step exceeds 0.25 tiles. Each sample gets a
   tangent `t`, a normal `n` (to the right of the travel direction) and
   `w = |n.x| + |n.y|`.
2. **Distances are in grid units**: `u = d / w`. `w` is the width of one grid cell
   projected onto the normal, so a band 1 unit wide is a 4-connected staircase on
   diagonals. Walls never join only at corners.
3. **Layers become bands** `[lo, hi)` of `u`. Layer 0 is centred; ±k stack
   outward, each starting `offset` after the previous one. The width comes from
   the layer type.
4. **Rasterize**: sweep cells near the curve and compute each cell centre's `u`.
   - Exact nearest sample via a spatial hash. Where the curve passes near itself,
     the branch with the smallest |u| wins.
   - `u` is quantized to 1/1024 so exact ties on rational slopes fall
     deterministically into one band.
   - Each cell gets at most one band, so layers never overlap.
   - Band layers emit placements as cells are classified.
5. **Spaced layers** walk their band's centre line by arc length, in priority
   order.
   - Each placement tries the 4 nearest grid-aligned positions.
   - It is skipped if all of them collide with a cell already taken.

Each stage keeps a cursor, so `planner.step(job, budget)` can stop anywhere and
continue next tick.

Known geometric limits:
- On the inside of a bend tighter than a side layer's distance from the curve,
  that layer splits (there is no room there).
- A near-cusp can leave small stray pieces.

## Building (`scripts/build/executor.lua`, `outputs/`)

The executor walks the plan's tiles, then its entities. For each placement it:

1. skips anything already there;
2. runs the placement check;
3. handles obstacles: forced = trees/rocks only, superforced = own and neutral
   entities.

It then hands off to an output module:
- `ghost` places ghosts and marks obstacles for deconstruction;
- `instant` (map editor or cheat mode) builds real entities, removes obstacles,
  revives matching ghosts and batches tiles into `set_tiles`.

A blueprint output would be a third module.

Placement is checked with the real entity name and
`build_check_type.manual_ghost, forced = true`. Don't check with
`name = "entity-ghost", inner_name = …`: in 2.1.24 that rejects free spots
west/north of existing walls.

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
before it could open.

Pointer clicks (`bezierio-pointer`) are ignored when the event has `in_gui` or an
`element` set. `element` alone isn't enough: slider clicks don't report one.

## Testing

```sh
tests/unit/run_all.sh                                    # all unit tests, no game needed
tests/run.sh smoke                                       # loads, runs 120 ticks with a player
tests/run.sh gui-flow                                    # full UI flow, builds in all modes
tests/run.sh gui-flow space-age quality elevated-rails   # same, with DLC mods enabled
```

**Unit tests** (`tests/unit/`, plain Lua 5.4) load mod modules through
`helpers.lua`:

| Test | What it checks |
|---|---|
| `plan_snapshot.lua` | Planner output for 27 fixed cases matches `snapshots/plans.txt`. Run with `--update` only for an intended change, and review the diff. |
| `planner_jobs.lua` | Running the planner in tiny slices gives exactly the one-shot plan. |
| `plan_properties.lua` | Random curves: no overlaps, and the layer 0 wall line is unbroken. |
| `migrations.lua` | Storage upgrades. |

`helpers.plan` is the only place the tests touch the planner API.

**Game tests** (`run.sh`) need a local Factorio 2.1 install (default
`~/Games/factorio`; override with `FACTORIO=`).

- `run.sh` creates a throwaway config, write-data and mod folder (`WORKDIR=` to
  keep them), so it doesn't touch your game.
- Scenarios use `--test-scenario`, which runs headless with one player. They drive
  the real GUI handlers through the `bezierio-dev` remote interface. Scripts can't
  click elements or fire custom inputs, so `dev.lua` imitates what the engine does
  first.
- Steps that start work wait for `dev("idle")`, i.e. for jobs to catch up.
- To add a scenario: create `tests/bezierio-test/scenarios/<name>/control.lua` and
  end with `script.finish_test(true|false)`.

The `tests/` and `python_scripts/` folders sit inside the mod folder; leave them out
of release zips.
