# Bézierio: developer notes

## Layout

```
info.json, data.lua, control.lua   mod entry points
settings.lua             map setting: work budget per tick
migrations/              storage upgrades, run by the game once per save (see Storage)
prototypes/
  items.lua              bezierio-pointer: cursor-only item for placing control points
  custom_input.lua       pointer click / shift-click / right-click / shift-wheel, Alt+B
  sprites.lua            GUI icons: centred build icons, reverse, colour swatches
scripts/
  state.lua              the definition of `storage`, accessors, migrations (start here)
  jobs.lua               per-tick runner: planning, drawing, building, within a budget
  draw.lua               rendering: control points, curve, build preview, bend warnings
  presets.lua            named layer stacks: copy, rename, delete, export/import strings
  palette.lua            one colour per layer; named colours and defaults for the view settings
  init.lua               on_init / on_configuration_changed / players, mod-gui button
  custom_input.lua       the curve pointer in the world
  dev.lua                remote interface for the test scenarios (only when `bezierio-test` is active)
  debug.lua              debug.print; `lib.debug` should be false for releases
  vector_math.lua        2D vector helpers
  curve/
    curve.lua            curve data ({points, closed}), editing, resumable sampling
    catmull_rom.lua      centripetal Catmull-Rom spline through the points
  layers/
    registry.lua         layer types: lookup, fields, new layers, item picker filter
    common.lua           pieces shared by layer types
    empty.lua wall.lua tile.lua electric_pole.lua electric_turret.lua roboport.lua rail.lua
  build/
    geometry.lua         frames, spatial index, grid distance from the curve
    planner.lua          curve + layers -> BuildPlan, as a resumable job
    executor.lua         BuildPlan -> world, as a resumable job (incl. wiring)
    blueprint.lua        BuildPlan -> blueprint in the cursor, as a resumable job
    undo.lua             keeps a whole build in one undo item
    outputs/ghost.lua    ... as ghosts
    outputs/instant.lua  ... as real entities (map editor, cheat mode)
  gui/
    interactions.lua     routes GUI events to lib[tags.group][tags.action](event)
    window.lua           find window elements by name
    layout.lua           main window (group "main")
    control.lua          Draw / Preview / Build buttons, status and totals lines (group "control")
    curve_control.lua    pointer button, closed loop, reverse, point list (group "curve")
    view_settings.lua    per-player colours, curve width, preview opacity (group "view")
    preset_control.lua   preset bar above the layer list (group "preset")
    layer_view.lua       layer list and the selected layer's detail pane
    layer_control.lua    layer actions (group "layer")
tests/                   see Testing
```

## How work flows

GUI and input handlers never plan, draw or build. They change data and say what
changed:

- `state.changed(i)`: the curve or the layers changed. This bumps
  `controller.revision`; the plan is redone.
- `state.request_redraw(i)`: only the view changed (Draw / Preview toggles, view
  settings).
- `state.request_point_redraw(i)`: only the point markers changed (selection).
- `state.request_build(i, mode)`: build once the plan for the current revision is
  ready.

`jobs.lua` runs every tick and, per player, spends a budget of work units
(`jobs.BUDGET`):

0. **Clear old drawings.** Destroy retired render objects, a budgeted number per
   tick (`draw.step_trash`).
1. **Reset if needed.** On a new revision, once edits have paused for
   `SETTLE_TICKS`, drop the plan and redraw. On a redraw request, retire the
   render objects and redraw the control points (cheap).
2. **Draw.** Draw what the planner has produced so far, using at most
   `DRAW_SHARE` of the budget. A straight run of neighbouring 1×1 cells in plan
   order shares one rectangle. The preview stops at `draw.MAX_PREVIEW_OBJECTS`
   (50,000; the status line says so). The 4,000 cap it replaced cut big previews
   off partway.
3. **Plan.** Advance the planner: only up to the curve samples when just the curve
   is shown; the whole plan when the preview is on or a build is waiting.
4. **Build.** Start a waiting build when its plan is done, then advance the build
   job.
5. **Window.** Update the status line (progress) and, once a plan is done, the
   totals (length; items summed by item and quality, per layer in the tooltip;
   bend warnings and pole gaps, with tooltips explaining them).

Heavy work is never done in a single tick. Every job is plain data in
`storage.controllers[i].work`: no closures or coroutines. So jobs survive
save/load and run identically on every multiplayer peer. Costs per operation
are in each module's `COST` table, and the budget counts work units, not time,
which keeps it deterministic.

The budget is the map setting `bezierio-work-budget` (default 1000). Measured
with the `bench` scenario:
- one unit is about 2.5–3 µs, whether planning, drawing or building;
- the default costs roughly 2.5–3 ms per tick per player;
- the 850-tile, 23k-placement test curve plans and previews in ~820 ticks and
  builds in ~125.

After changing costs or the planner, rerun the bench and keep the units balanced.

The map editor starts with ticks paused, and then nothing happens. Unpause it
when testing.

## Storage

The shape is documented at the top of [scripts/state.lua](../scripts/state.lua):

```
storage.schema_version
storage.controllers[player_index]
    ui        preset_index, draw_curve, preview_build, selected_point, selected_layer
    view      colours (names from palette.NAMED), curve_width, preview_opacity
    curve     {kind = "catmull_rom", points = {{x, y}, ...}, closed}
    presets   {{name, layers = {[k] = Layer}}}             (layer k: … -1, 0, 1 …)
    revision  bumped on curve/layer changes (changed_tick: when)
    redraw    view needs redrawing (redraw_points: only the point markers)
    work      jobs: plan (PlannerJob), draw progress, pending_build, build (BuildJob or BlueprintJob)
storage.sprites[player_index]   LuaRenderObjects: curve / control_points / preview / trash
storage.item_filter             ItemPrototypeFilter for the layer pickers
storage.rebuild_needed          set by migrations: rebuild derived data on next access
```

Always go through the `state` accessors.

Upgrades follow the game's [migration
mechanism](https://lua-api.factorio.com/latest/auxiliary/migrations.html): Lua files
in `migrations/`. The game runs each file once per save, in byte-wise file name
order, when a save is loaded. It also runs all of them when the mod is added to a
save or a new game starts, right after `on_init`. Hence:

- each file acts only when `storage.schema_version` is its starting version, and
  sets the next one, so it does nothing on current data;
- files use only `storage`, `game`, `rendering` and `prototypes`, never the mod's
  modules: a migration must keep doing what it did when it was written;
- derived data (jobs, drawings, the item filter, settings added later) isn't
  migrated. `state.on_configuration_changed` rebuilds it. The game doesn't raise
  `on_configuration_changed` when it only applied migrations (seen in 2.1.24 with
  the mod version unchanged), so migrations set `storage.rebuild_needed` and the
  first tick or event does the rebuild (`state.ensure_rebuilt`). The map editor
  starts paused, so a GUI event may come first.

Files: `0.2.0.lua` discards 0.1.x data (no `schema_version`). The
`0.2.0-dev-N.lua` files upgrade saves from development builds; they sort before
`0.2.0.lua` (`-` < `.`) and are to be removed before the first release (see the
roadmap). Name later ones after the mod version that introduces them. Names sort
byte-wise, so `0.10.0.lua` would run before `0.9.0.lua`: once versions get there,
rename or pad accordingly.

**Changing the layout:**
1. Bump `state.SCHEMA_VERSION`.
2. Add a migration file that upgrades from the previous version, sets the new one
   and sets `storage.rebuild_needed = true`.
3. Add cases to `tests/unit/migrations.lua` (it runs the files the way the game
   does), and update the fixture in `tests/bezierio-migration-fixture` if it
   helps.

Data from a newer version of the mod is discarded (on_configuration_changed).

## Curves

A curve is a list of control points and a `closed` flag. It is drawn as a
centripetal Catmull-Rom spline (`curve/catmull_rom.lua`):

- it passes through every point;
- each point only bends the curve between its neighbours;
- the centripetal form never forms cusps or loops within a segment.

Open curves get reflected end neighbours, so they start and end exactly on the
first and last points. Closed curves wrap around. Consecutive duplicate points are
dropped before sampling. The sampler is resumable, one piece of a segment at a time.

The pointer (`custom_input.lua`) edits the list. One point can be selected
(`ui.selected_point`, also from the point list in the window):
- left-click on a point (within `PICK_RADIUS`) selects it;
- left-click elsewhere moves the selected point there (it stays selected), or
  appends a point if none is selected;
- shift + left-click inserts a point where `curve.insertion_index` says: into the
  segment passing nearest the click (16 evaluations per segment), or before the
  first / after the last point when the click lies beyond an end of an open curve.
  The new point is selected;
- right-click deselects, or removes the point under the cursor;
- shift + mouse wheel selects the next / previous point.

Changing the selection only redraws the point markers, not the preview. The
reverse button reverses the list, so the curve runs the other way and the layers
swap sides.

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
survive mods changing prototypes. Picking another item for a layer makes a fresh layer and then
`registry.carry_over` keeps every setting the new type also has (same field name),
clamped to the new range, plus the offset.

## How the planner works (`scripts/build/planner.lua`, `geometry.lua`)

1. **Sample** the curve so that no step exceeds 0.25 tiles. Each sample gets a
   tangent `t`, a normal `n` (to the right of the travel direction) and
   `w = |n.x| + |n.y|`.
2. **Distances are in grid units**: `u = d / w`. `w` is the width of one grid cell
   projected onto the normal, so a band 1 unit wide is a 4-connected staircase on
   diagonals. Walls never join only at corners.
3. **Layers become bands** `[lo, hi)` of `u`. Layer 0 is centred; ±k stack
   outward, each starting `offset` after the previous one. The width comes from
   the layer type. A tile layer with *Under entities* (`registry.is_underlay`)
   takes no room: the next layer out starts where it starts.
4. **Rasterize**: sweep cells near the curve and compute each cell centre's `u`.
   - Exact nearest sample via a spatial hash. Where the curve passes near itself,
     the branch with the smallest |u| wins.
   - `u` is quantized to 1/1024 so exact ties on rational slopes fall
     deterministically into one band.
   - Each cell gets at most one band, so layers never overlap. Underlay bands are
     the exception: a cell also gets the first underlay containing it, unless its
     own band placed a tile there.
   - Band layers emit placements as cells are classified.
   - Open curves also get a few probes past each end (`END_PROBE_STEP`): cells
     count as beside the curve up to half a grid unit past its end, and no probe
     across the end frame may cross them.
5. **Tight bends**: a stage measures curvature (the turn of the tangent between
   neighbouring samples). Where a bend is tighter than the outermost layer on its
   inside, it records a warning position (`plan.warnings`); the preview marks
   them.
6. **Spaced layers** walk their band's centre line by arc length, in priority
   order.
   - Each placement tries the 4 nearest grid-aligned positions, then the same
     with the target shifted up to ±2 tiles along the curve.
   - It is skipped only if all of those are taken.
   - **Pole layers** (with `wire_distance`) also form a chain (`plan.chains`, in
     order along the curve). If the next pole would be out of wire reach of the
     previous one, poles are inserted in between, halving the gap recursively;
     closed curves also close the chain.
   - Gaps that can't be bridged because there's no room are counted in
     `plan.gaps` and reported.

Entity sizes come from the prototype's `tile_width`/`tile_height`. The collision
box is smaller than the footprint; rounding it outward made 1×1 entities 2×2.

Each stage keeps a cursor, so `planner.step(job, budget)` can stop anywhere and
continue next tick. The plan also records the curve length and placements per
layer, for the totals line.

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

After the entities, the executor connects each pole chain's consecutive poles
(ghosts or real) with copper wire, plus red and green wire when the layer has
*Circuit wires* on.

Every action carries an `undo_index`, so a build spread over many ticks is still
one undo item (`build/undo.lua`). Items are addressed from the top of the stack,
so the job remembers the stack size right after creating its item; anything the
player does meanwhile shifts the index.

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

Element names are unique within the window (`cp_x_3`, `radius_slider`,
`layer_select_-1`, ...). `gui/window.lua` finds elements by name, so code and tests
don't depend on the layout.

## Testing

```sh
tests/run_all.sh                                       # everything below except bench, with a summary
tests/unit/run_all.sh                                  # all unit tests, no game needed
tests/run.sh smoke                                     # loads, runs 120 ticks with a player
tests/run.sh points                                    # the pointer, point list, closed loops
tests/run.sh layers                                    # layer list and detail pane, presets, view settings
tests/run.sh build                                     # preview, totals, builds in all modes, blueprints
tests/run.sh build space-age quality elevated-rails    # same, with DLC mods enabled
tests/migrate-save.sh                                  # the game applies migrations/ to a real save
tests/run.sh bench                                     # timing (read the BENCH lines in the log)
```

**Unit tests** (`tests/unit/`, plain Lua 5.4) load mod modules through
`helpers.lua`:

| Test | What it checks |
|---|---|
| `plan_snapshot.lua` | Planner output for 30 fixed cases matches `snapshots/plans.txt`. Run with `--update` only for an intended change, and review the diff. |
| `planner_jobs.lua` | Running the planner in tiny slices gives exactly the one-shot plan. |
| `plan_properties.lua` | Random curves and loops: no overlaps, an unbroken layer 0 wall line (a ring through the seam for loops), poles in reach except counted gaps, and bend warnings where they belong. Adding an underlay anywhere never moves an entity or a tile. |
| `curve_edit.lua` | Inserting (including where a shift-click goes) and reversing points. |
| `layers.lua` | Which layer settings survive picking another item (`registry.carry_over`). |
| `presets.lua` | Preset list operations; export data round trip and import validation. |
| `migrations.lua` | The files in `migrations/`, run like the game does, on old and current data. |

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
- Scenarios share helpers, a standard curve and layer stack, and the step runner
  in `tests/bezierio-test/lib/flow.lua`.
- To add a scenario: create `tests/bezierio-test/scenarios/<name>/control.lua`,
  add steps with `flow.step` and end with `flow.run("<name>")`, and add it to
  `tests/run_all.sh`.
- `migrate-save.sh` creates a save with a copy of the mod that has no
  `migrations/` folder; the `bezierio-migration-fixture` mod writes old data into
  its storage. It then loads the save with the real mod and the fixture checks the
  result on the first tick.

The `tests/` folder sits inside the mod folder; leave it out of release zips.
