# Bézierio: developer notes

## Layout

```
info.json, data.lua, control.lua   mod entry points
data-final-fixes.lua     records each pipe's max_pipeline_extent (not readable at runtime) in mod-data
settings.lua             map setting: work budget per tick
migrations/              storage upgrades, run by the game once per save (see Storage)
prototypes/
  items.lua              bezierio-pointer: cursor-only item for placing control points
  custom_input.lua       pointer click / shift-click / right-click / shift-wheel, Alt+B
  sprites.lua            GUI icons: centred build icons, reverse, narrow / widen, colour swatches
  style.lua              GUI styles: shaded lists, add-layer bars, point chips
scripts/
  state.lua              the definition of `storage`, accessors, migrations (start here)
  jobs.lua               per-tick runner: planning, drawing, building, within a budget
  draw.lua               rendering: control points, curve, build preview, bend warnings
  highlight.lua          marks on unpowered / unfed entities after a build, toggled from the window
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
    shapes.lua           circles, ellipses and arcs from handles, sampled exactly
  layers/
    registry.lua         layer types: lookup, fields, new layers, item picker filter
    common.lua           pieces shared by layer types
    empty.lua wall.lua tile.lua electric_pole.lua electric_turret.lua turret.lua roboport.lua rail.lua
    belt.lua pipe.lua lamp.lua land_mine.lua radar.lua solar_panel.lua accumulator.lua
  build/
    geometry.lua         frames, spatial index, grid distance from the curve
    planner.lua          curve + layers -> BuildPlan, as a resumable job
    executor.lua         BuildPlan -> world, as a resumable job (incl. wiring)
    blueprint.lua        BuildPlan -> blueprint in the cursor, as a resumable job
    wires.lua            walking a plan's pole chains and links, for the executor and the blueprint
    cover.lua            cover tiles (landfill, foundation, ...) for force builds, from the prototypes
    paths.lua            belt and pipe lines: segments, corners, pieces
    feeds.lua            turret feeds: fluid connections, inserters
    rails.lua            rail track fitted to a line, signals' sides, elevated supports
    rail_data.lua        the game's rail planner data, generated (tests/gen-rail-data.sh): don't edit
    smart_poles.lua      pole lines as far apart as reach allows, powering what needs it
    undo.lua             keeps a whole build in one undo item
    outputs/ghost.lua    ... as ghosts
    outputs/instant.lua  ... as real entities (map editor, cheat mode)
  gui/
    interactions.lua     routes GUI events to lib[tags.group][tags.action](event)
    window.lua           find window elements by name; give the main window back its place as the opened GUI
    layout.lua           main window: title bar (pin, narrow), the sections in one column (group "main")
    control.lua          Build section: Draw / Preview / Build buttons, status and totals lines (group "control")
    curve_control.lua    Curve section: pointer button, closed loop, reverse, point list (group "curve")
    view_settings.lua    settings window: colours, curve width, preview opacity, mark time, blueprint source (group "view")
    preset_control.lua   preset bar above the layer list (group "preset")
    string_window.lua    import / export window for curve and preset strings (group "strings")
    layer_view.lua       layer list, and the layer settings window
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
   tick, at most `draw.TRASH_SHARE` of the budget (`draw.step_trash`).
   `draw.delete_sprites` moves whole caches into the trash without looking at
   them, so clearing a 50,000-object preview costs nothing up front.
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
    ui        preset_index, draw_curve, preview_build, selected_point, selected_layer,
              preset_mode, pointer_mode, narrow, pinned,
              editing {idx, backup, new, revision} (the layer settings window is open),
              reopen_main (give the main window back its place as the opened GUI next tick)
    view      colours (names from palette.NAMED), curve_width, preview_opacity
    settings  the player's other settings, only where changed (state.SETTING_DEFAULTS)
    curve     {kind, points = {{x, y}, ...}, closed, handles = {circle, ellipse, arc}, reversed = {[kind] = true}}
    presets   {{name, layers = {[k] = Layer}}}             (layer k: … -1, 0, 1 …)
    revision  bumped on curve/layer changes (changed_tick: when)
    redraw    view needs redrawing (redraw_points: only the point markers)
    work      jobs: plan (PlannerJob), draw progress, pending_build, build (BuildJob or BlueprintJob)
storage.sprites[player_index]   LuaRenderObjects: curve / control_points / preview / highlight_<kind>;
                                trash: retired caches (arrays), emptied from the end
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

**Keep derived data out of storage.** Anything computed from the mod's code and
the prototypes (the item picker filter, layer values like sizes and wire reach)
is recomputed instead of stored: the filter is a per-session cache
(`state.item_filter`), and layers are refreshed (`state.refresh_layers`) on
configuration changes and before every plan. Otherwise a code update without a
migration leaves saves with stale data: a save from before belts existed didn't
offer them in the picker.

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
reverse button flips the active kind's direction (see Curve kinds); the
points stay as they are.

**Curve kinds.** `curve.kind` is `"catmull_rom"` (the spline through
`curve.points`) or a shape: `"circle"`, `"ellipse"` or `"arc"`, defined by the
handles in `curve.handles[kind]` (see `curve/shapes.lua` for what each handle
means). Each kind keeps its own points. The editing functions in `curve.lua`
(append, set_point, remove, point_near, ...) and the pointer work on the active
kind's list (`curve_lib.active`). Shapes cap their handle count, and moving a
shape's centre moves the whole shape. Shapes are sampled exactly from their
parameters, so no control-point approximation is involved. Loops end on exactly
their first sample, as the planner expects. `shapes.construction` gives what the drawing shows about how the handles are
used: the ellipse's axes, and where its width handle (projected onto the
perpendicular axis) and the arc's end handle (its direction, at the start's
radius) actually land. `curve.reversed[kind]` makes that kind run
the other way, for the spline too: its points keep their order and numbers, and
it is sampled backwards (a loop keeps its seam at P1). Move
mode (`ui.pointer_mode = "move"`) makes clicks move `curve_lib.center` to the
click: a shape's centre, or the middle of the spline's bounding box.

## Layer types

A layer type is one file in `scripts/layers/`, listed in `TYPE_FILES` in
`registry.lua`. It declares:

- `entity_types` (or `tile = true`): which picked items select this type;
- `placement`:
  - `"band"`: fills its band (walls, tiles);
  - `"spaced"`: entities every `spacing` tiles along the band's middle;
  - `"rail"`: track fitted to the band's middle (see Rails below);
  - `"unsupported"`: shown, but skipped when building;
  - `"none"`: builds nothing (empty);
- `output` (`"entity"` or `"tile"`) and `priority` (higher claims contested cells
  first);
- `fields`: editable settings. The GUI builds its controls from these:
  - `widget`: `"slider"` (min/max as numbers or functions of the layer, optional
    word labels), `"checkbox"`, `"choice"` (a drop-down of `options`, labels from
    `label_prefix`), `"item"` (an item picker with `item_filters`; `valid(layer,
    value)` refuses items the layer can't use, e.g. the wrong ammo) or
    `"targets"` (a list of entity pickers, at most `registry.MAX_TARGETS`: turret
    targeting priorities, carried to ghosts, built turrets and blueprints as
    `priority-list` / `ignore-unprioritised`);
  - `default`, `visible_if(layer)` (hide when irrelevant, e.g. facing for turrets
    that turn all the way round), `disabled_by` (a checkbox that makes it moot);
- every layer with an item can be placed or not: the build toggle in its row of
  the layer list (`place`, `registry.place_field`, stored only when false; the
  eye next to it is `preview`, the drawing only). The planner swaps a layer that
  isn't placed for an empty stand-in of the same width (`stage_bands`), so the
  layers outside it don't move;
- `init(layer, prototype)` for derived values (e.g. pole wire reach, a turret's
  turn range and ammo categories), and `thickness(layer)` if the band width isn't
  the footprint size;
- band layers: `keep(layer, x, y)` instead of the checkerboard (land mine density:
  a fixed per-cell hash, exact in both integers and doubles), and `join_corners`
  (walls, without a checkerboard: see the joins stage);
- spaced layers: `decorate(layer, entity, info)` adds `direction`, `color` or
  `ammo` to a planned entity. `info.outward` is the normal on the layer's side
  (layer 0: layer 1's side), `info.arc` the distance along the curve. Non-square
  turrets keep to 4 directions and are shifted onto their own grid inside the
  square the planner reserved.

Spaced layers can also have `wants_feed(layer)`, `can_attach(layer, entity,
ctx)` and `attach(layer, entity, ctx)`: turrets with a feed (`build/feeds.lua`).
Their spot search only takes spots where the feed fits (falling back to a plain
spot, counted in `plan.unfed`). Then `attach` adds the feed through a
`FeedContext`, which sees the belt and pipe cells the paths stage made:
- an inserter in a free cell beside the turret, turned so its drop (the inserter
  prototype's `inserter_drop_position`) lands in the turret and its pickup on a
  belt. An inserter's direction is its pickup side;
- a pipe stub of up to `MAX_STUB` cells from one of the turret's fluid
  connections to a pipe line, touching no other pipe line. Connections facing
  straight are the prototype's north ones rotated. Facing diagonally, each north
  connection is turned 45° and rounded to the grid, and points along whichever
  straight direction beside the turned one leads out of the turret's square. That
  matches the game for the flamethrower (a reference blueprint and a probe of
  `get_fluid_box_pipe_connections`).

**Gates** are decided when building, as they depend on the world: a wall cell
(`entity.gate`, from the wall layer's *Gates on rails*) with a straight rail
under it becomes a gate. The gate is turned whichever way the game allows over
that rail, checked with `manual_ghost` and not forced, because a forced check
refuses gates over rails. Super force doesn't clear rails for such walls.
The other way round, a planned straight rail facing north/south/east/west
(`entity.gate` and `entity.track`, from the rail layer's *Gates in walls*) swaps your walls
under it for gates turned across it (ghost: walls marked for deconstruction and
gate ghosts; instant: replaced). Rails only go over other layers' walls this way;
the planner keeps planned walls off the track's cells.

The outputs and the blueprint writer carry `direction` and `color` into the
entity (a lamp ghost keeps a colour only when given at creation), and `ammo` as
an insert plan (ghost, blueprint) or by inserting it (instant). `plan.links` holds
wires that aren't pole chains (land mines: each to the nearest of the layer's last
`LINK_WINDOW` mines within reach), wired after the chains.

Layers are plain data. They name prototypes rather than holding them, so saves
survive mods changing prototypes. `layer.preview == false` hides a layer in the
preview only (a view flag: toggling it redraws without replanning, and presets
don't export it). Picking another item for a layer makes a fresh layer and then
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
   - On a closed curve, a spot in the loop's second half within half a spacing
     of the first entity is left out, so the seam gets 0.5 to 1.5 spacings instead
     of an entity next to the first one (`walk.first`, `walk.centre`).
   - Non-square entities (a 2x3 flamethrower, modded ones) are moved onto their
     own grid within the reserved square (`common.fit_footprint`: an even side
     needs a whole-number centre, an odd one a half).
   - **Pole layers** (with `wire_distance`) also form a chain (`plan.chains`, in
     order along the curve). If the next pole would be out of wire reach of the
     previous one, poles are inserted in between, halving the gap recursively;
     closed curves also close the chain.
   - Gaps that can't be bridged because there's no room are counted in
     `plan.gaps` and reported.
   - **Smart pole layers** (`smart_poles.lua`) ignore the spacing. After the greedy
     walk, a refine pass drops poles nothing needs (neighbours in reach, every
     consumer they power powered by another pole too; an open line's end pole if
     the next is within a third of the reach) and slides the rest towards the middle
     between their neighbours as far as reach and the consumers only they power
     allow. The greedy walk alone leaves a pole at full reach followed by one a
     couple of tiles on when a consumer can only be powered from a short stretch. They build the
     band's centre line with arc lengths, project every powered entity in the
     plan onto it, then walk greedily. Each next pole is the farthest free spot
     (tried every 0.5 tiles back from the wire reach) that is in reach of the
     previous pole and powers the first unpowered entity plus every unpowered one
     before the spot. If no spot can, that entity is given up on. At the end,
     entities still outside every pole's supply area are counted in
     `plan.unpowered`, in a phase of its own (`count`): the poles are put in
     buckets of `BUCKET` tiles square, and each consumer looks only at the
     buckets its pole reach touches, a budgeted number per step. (Checking every
     consumer against every pole in one call took 0.45 s at 8,000 tiles.) Spaced entities record the sample they were placed at
     (`frame`), so projection doesn't jump to another stretch where the curve
     crosses itself. Pole layers run last (lowest priority), so every consumer is
     already planned.

**Path layers** (belts, pipes; `build/paths.lua`). Each line is a one-cell
sub-band of the layer's band (`lines` of them, `line_gap` empty cells between).
The rasterizer collects each line's cells with the curve sample they belong to
(`grid_distance` returns it), and a `paths` stage (between rasterize and spaced)
builds the lines, a budgeted amount per step (the setup files the lines' cells a
number at a time; each line's progress is kept in its `path_queue` item):
- `paths.step_segments` (resumable; `paths.segments` runs it in one go) drops
  repeated cells, sorts them along the curve with a merge sort that can stop
  anywhere, then orders them by walking from neighbour to neighbour,
  preferring the way that continues along the curve over a dead end (a spur
  at a bend) and refusing neighbours from another stretch of a curve that comes
  back near itself. It steps diagonally only when it must.
- Lines are routed (segments + corners) for every line first, and only then made
  into entities. A belt line may take a corner from another line of its layer
  (preferring a free cell); the cell is locked to it and the other line is routed
  again (`MAX_REROUTES`), so no corner can appear in front of a belt that already
  chose its direction. On a closed curve, distances along the curve are measured
  around the loop, and a loop whose ends meet diagonally is closed through a corner.
  Pieces shorter than `MIN_SCRAP` beside a long stretch are dropped.
- `paths.join_corners` (a segment per call) fills a diagonal step with a corner cell. Bands get
  squeezed on the inside of bends, so a one-cell line isn't always 4-connected
  there. A corner may be a free cell or, for belts, a cell of a line of the same
  layer not built yet (that line goes round it). Pipe corners must not touch
  another pipe line. A step with no usable corner splits the line.
- `paths.pieces` (a part per call; the part's entities are then added a budgeted
  number at a time) makes the entities: belts point at the next cell (the last
  one straight on or away from other belts, so it never feeds one from the side,
  and line ends hemmed in by belts are dropped). Undergrounds go on straight
  runs, the entrance fed from behind and the exit feeding a cell that continues
  in line, chained for long runs. Pumps (pipes) go every `pump_spacing` cells
  on the next stretch straight enough for a pump with pipe in line at both ends.
  The spacing is capped at the pipeline's extent limit less the pump's two
  cells: `FluidBox::max_pipeline_extent`, the smallest of the pipe's and its
  underground's, recorded by `data-final-fixes.lua` in the
  `bezierio-pipeline-extent` mod-data because the runtime API doesn't expose it.
  Pumps carry `power`, so smart poles reach them.
Undergrounds and pumps are counted in `plan.extra_counts` for the totals.

**Joins** (a stage between paths and spaced). Walls only connect side by side.
A 1-wide band is an unbroken staircase where the curve runs straight, but off to
the side of a bend the grid distance also changes along the curve, so a side
layer's cells can meet only at a corner (layer 0 never does). For layers with
`join_corners` (walls without a checkerboard), the rasterizer records their cells
in order. Wherever two meet only at a corner, the stage fills one of the two
corner cells with the layer: the free one (no entity, no tile other than an
underlay) whose grid distance is nearest the layer's band. It runs after paths,
so belt and pipe corners are taken first, and before spaced layers, which find
spots around the walls.

**Rails** (`build/rails.lua`, a `rails` stage between bends and rasterize, one
piece per step). The rail layer's band middle is sampled about once a tile into a
line. The fit is a chain of rail ends, from `rail_data.lua`: the game's rail
planner offers three pieces at an end facing one of 16 directions (straight on, or
one direction step either way), each with its other end ("goal") where the next
attaches. The data, the tiles each piece covers and the signal locations at each
end come from `tests/gen-rail-data.sh`, which runs the `rail-data` scenario (a
search over `LuaRailEnd.get_rail_extensions`); rerun it with `space-age
elevated-rails quality` if the game's rails change.
- The fit starts at the line's start snapped to the rail grid. Each step scores
  every sequence of the next `DEPTH` pieces by how far their ends land from the
  line (squared) plus `ANGLE_WEIGHT` × the direction error (squared), and lays
  the first piece of the best. Past the line's ends, distance is to the line
  extended, so the lookahead doesn't bend the track towards the end point.
- A closed curve closes when a search of up to `CLOSE_DEPTH` pieces reaches the
  start end within `TOLERANCE`. An open one stops near its end. Ends further than
  `TOLERANCE` from the line, a fit that stops getting along the line (`STALL`),
  an unclosed loop or a missing ramp down become `plan.warnings`.
- Pieces claim their tiles (`rails.cells`) as `"rail"`, so later layers keep off.
  Each carries `track = {from, to}` (drawn as a line in the preview).
- Signals every `signal_spacing × WAGON` tiles along the track, at the end's
  `out_signal_location` (the side for forward travel; verified in the game),
  or the reversed end's for backward travel, both for both ways. They may stand on
  `"rail"` cells.
- Elevated (the elevated-rails mod): pieces are `elevated-*`, claim no tiles and
  signals get `rail_layer = "elevated"` (the outputs pass it to `create_entity`;
  the executor skips ground checks for them). With *Ramps* (open curves only), the
  fit starts with a ramp up and finishes with a ramp down at the last orthogonal
  end it can. If the band bends until too near its end for a ramp to land there,
  the ramp goes down from where the track ends, past the curve's end. Ramps are straight and orthogonal only. `rails.supports` then puts
  supports at joints greedily as far apart as their range allows (`range - 1`
  from a support, `ramp_range - 1` past a ramp top). Supports are planned before
  the rails, so their ghosts are there when the elevated rail ghosts are placed.
Rail items per piece come from `items_to_place_this` (curved pieces cost more).

A finished job keeps only what's read afterwards (`planner.KEEP_WHEN_DONE`:
stage, layers, closed, points for drawing the curve, the plan); the per-cell
working tables would otherwise stay in the save.

Values a layer derives from its prototype (size, wire reach, supply area,
`needs_power` = has an electric energy source) are set by `registry.refresh`, for new
layers and again on every configuration change; layers whose prototype is gone
become empty, and so do layers whose item is gone. An unknown quality becomes
normal. `registry.check_fields` then clamps the numbers into their (possibly
new) ranges and drops items and priority targets that are gone or no longer
fit; it also runs on new layers after their defaults, and import strings go
through `registry.carry_over`, which rounds and clamps like the sliders and
takes only enemy types as priority targets (`registry.is_target`).

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

Three modes, as the game's (FFF-383): **Build** (`normal`) places only where
nothing is in the way; **Force build** (`forced`) also removes trees, rocks and
cliffs in the way (marked for deconstruction as ghosts; a cliff only with cliff
explosives) and lays cover tiles; **Super force** (`superforced`) also removes
the player's own and neutral entities in the way.

Cover (`build/cover.lua`, forced modes): an entity needs it where a tile's
collision mask meets its own (water and walls share `water_tile`); a planned
floor tile where its item's `place_as_tile_result` can't go on the tile there.
The cover is the first of the player's `cover_tiles` setting that can go on that
tile (its `condition` / `invert` / `tile_condition`) and takes what's planned,
else the tile's `default_cover_tile` (water: landfill, lava: foundation,
ammoniacal ocean: ice platform, empty space: space platform foundation); none:
blocked. Ghosts: a tile ghost (an entity ghost may stand on a tile ghost, and a
floor ghost on a cover ghost); instant: `set_tiles` at once. A force build
checks first that nothing it won't remove is in the way, so a blocked spot isn't
left with landfill. Elevated pieces need none.

The executor walks the plan's tiles, then its entities. For each placement it:

1. skips anything already there. For belts, undergrounds (and their input /
   output), pipes-to-ground, pumps and inserters, only if it faces the planned
   way (`same_way`; not rails, whose opposite directions the game folds
   together). One facing another way is in the way: a normal build counts it
   blocked, super force replaces it (the placement check doesn't catch it:
   belts can be placed over belts). A matching ghost is revived by `instant`,
   which then counts the entity as its own and gives it its priorities and
   ammo (dropping the ghost's ammo request);
2. runs the placement check;
3. lays cover where needed (forced modes), then handles obstacles: normal =
   none (blocked), forced = trees, rocks and cliffs (cleared first when only they
   fail the check), superforced = own and neutral entities, only where the spot
   is blocked, within the collision box turned
   the planned way (`obstacle_area`; a square for diagonals and track). Super
   force never clears anything the build itself made (`job.own`, by unit
   number), only its own force's ghosts, and nothing of the types in
   `IGNORED_IN_THE_WAY` (characters and corpses, items on the ground, ore,
   robots, effects, proxies: entity types, not names). Track (rails, signals,
   supports) never clears other track: the square searched around a curved
   rail reaches far past it, and rails may cross and overlap. Elevated pieces
   clear nothing on the ground.

The outputs return nil when what they created is already gone (another mod's
`on_built` handler may destroy it), and a build whose surface or force went away
stops (`job.aborted`) without a report.

After the entities, the executor connects each pole chain's consecutive poles
(ghosts or real) with copper wire, plus red and / or green wire as the layer's
*Red wire* / *Green wire* say. Then it wires `plan.links` (land mines). The
blueprint writer walks the wires the same way (`build/wires.lua`).

Every action carries an `undo_index`, so a build spread over many ticks is still
one undo item (`build/undo.lua`). Items are addressed from the top of the stack,
so the job remembers the stack size right after creating its item; anything the
player does meanwhile shifts the index.

It then hands off to an output module:
- `ghost` places ghosts and marks obstacles for deconstruction;
- `instant` (map editor or cheat mode) builds real entities, removes obstacles,
  revives matching ghosts and batches tiles into `set_tiles`.

The blueprint writer (`build/blueprint.lua`) is the third, run by `jobs.lua`
in place of the executor. Unless the player's `blueprint_source` setting
is off, the blueprint's first entity carries a `bezierio` tag with the curve and
preset export strings (a description holds at most 500 characters: too few), and
the description a note. **Load from blueprint** (`gui/control.lua`) reads the tag
from the held blueprint (cursor item, the active one in a book, or a library
record) and loads both through the import paths (`curve_control.load`,
`preset_control.load`).

After an executor build, `jobs.lua` marks the plan's unpowered and unfed entities
(`plan.unpowered_at`, `plan.unfed_at`, recorded by `smart_poles.lua` and the feed
context) with `highlight.lua`: a frame and an icon each, drawn a budgeted number
per tick from `work.highlight`, with `time_to_live` from the player's
`highlight_seconds` setting. They live in `storage.sprites[i].highlight_<kind>`,
which a redraw of the preview leaves alone. They belong to the plan whose totals
and warnings are shown: when an edit drops that plan, they are hidden with it
(`highlight.hide_all`). Clicking the warning label toggles them.

Placement is checked with the real entity name and
`build_check_type.manual_ghost, forced = true`. Don't check with
`name = "entity-ghost", inner_name = …`: in 2.1.24 that rejects free spots
west/north of existing walls.

## The window

One column of sections (`gui/layout.lua`): Curve, Layers (presets, the layer
list) and Build. All sections share the column's width (`WIDE_WIDTH`,
`NARROW_WIDTH`). Lists (points, layers) and the build summary sit in sunken panes
(`inside_deep_frame`); buttons in a row are 8 px apart. While planning or building,
the summary pane shows the progress and a bar instead of the summary
(`jobs.lua`, `show_progress`); the summary comes back when it's done. The
progress line names the running build and the queued command
(`work.pending_build`, which waits while a build runs), with a cancel button
that drops both (`control.cancel_build`; the executor flushes its tile batch
every step, so stopping between ticks loses nothing).

Three more windows, found by `window.find` like the main one (element names are
unique across all of them):

- **Layer settings** (`bezierio_layer_window`, `layer_view.open_settings`): a
  layer's item or settings button opens it, so does a new layer. It becomes
  `player.opened`, and the main window is locked until it closes:
  `interactions.handle_event` ignores events from it while `ui.editing` is set.
  (`ignored_by_interaction` on the main window would pass clicks through to the
  world, where the pointer acts on them.) Edits apply live; `ui.editing` keeps a copy of the layer from when it
  opened. OK (`accept`) keeps the edits, Cancel or Esc (`on_gui_closed`) puts the
  copy back, or removes a new layer. Moving or deleting layers, switching
  presets, narrowing or closing the main window accept first.
- **Settings** (`bezierio_settings_window`, the gear in the title bar): the view
  settings and the player's other settings, `controller.settings`
  (`state.SETTING_DEFAULTS`, read with `state.setting`: missing ones read as
  their default, so old saves need nothing). They were per-user mod settings
  before.
- **Import / export** (`bezierio_string_window`): the curve's and the preset
  bar's export and import buttons open it, one at a time (another replaces it;
  the same button again closes it). It becomes `player.opened`, so Esc closes it,
  but the main window stays usable. A successful import closes it; switching
  presets closes a preset's.

When the layer or import window closes, the main window gets its place as the
opened GUI back (`window.focus_main`), unless it's pinned. From an
`on_gui_closed` handler that waits for the next tick (`ui.reopen_main`): the
event may come from another GUI opening (a chest clicked), and setting
`player.opened` there fights it. While another GUI is open it keeps waiting.
A reset (schema change) and configuration changes close all four windows
(`state.close_windows`).

- **Narrow** (`ui.narrow`, the chevrons in the title bar) rebuilds the window
  where it was. Each section then shows only its everyday controls: the points as
  chips (`CHIP_COLUMNS` × `CHIP_ROWS` before the list scrolls, the selected one
  kept in view), the curve tools in two rows (export / import left out), layer
  rows without their move / delete buttons, the preset
  drop-down only, the item list in the length's tooltip.
- **Pinned** (`ui.pinned`): the window isn't `player.opened`, so other GUIs and
  Esc leave it open. Letting go of it as the opened GUI raises `on_gui_closed`
  for it, which the handler ignores while pinned (and while a layer's settings
  are open, which take over as the opened GUI).
- Lists (points, layers) are tables with the `bezierio_striped_table` style:
  shaded odd rows, the game's own graphic.

## GUI events

`gui/interactions.lua` sends each GUI event to `lib[tags.group][tags.action]`, but
only for the element types listed in `routed_types`:

- clicks → buttons, and labels with tags (the unpowered / unfed warnings), left
  mouse button only (a right-click on a delete button shouldn't delete);
- elem changed → choose-elem-buttons;
- confirmed → textfields;
- value changed → sliders;
- checked state changed → checkboxes;
- selection changed → drop-downs.

Events from the main window are ignored while a layer's settings are open (see
The window).

Every element raises `on_gui_click`. Without this filter, clicking an item picker
ran its "type changed" action, which rebuilt the row and destroyed the picker
before it could open.

Pointer clicks (`bezierio-pointer`) are ignored when the event has `in_gui` or an
`element` set. `element` alone isn't enough: slider clicks don't report one.

Element names are unique across the windows (`cp_x_3`, `radius_slider`,
`layer_select_-1`, ...). `gui/window.lua` finds elements by name, so code and tests
don't depend on the layout. Found elements are remembered per player (in a plain
Lua table, not saved: a valid element of that name is the one, so results don't
depend on it).

## Locale

All texts are in `locale/en/Bezierio.cfg`. **Every key has a comment line (`;`)
right above it**: which element it's for (window, section, widget) and what that
element does, plus what `__1__`, `__2__` stand for. A section header gets one
too when its keys are built from names at runtime (layer fields, view settings,
modes). Comments end in `[unreviewed]` until a human has checked the comment and
the text; they remove the marker then.

When adding a key: write its comment, marked `[unreviewed]`. When changing what
an element does, update the comment and mark it `[unreviewed]` again.

Keys built at runtime (`"tooltip." .. field.name`, `"label.command-" .. mode`,
`"bezierio-message." .. error`) don't show up in a search for the full key:
adding a mode, field or error means adding its key.

## Testing

```sh
tests/run_all.sh                                       # everything below except bench, with a summary
tests/unit/run_all.sh                                  # all unit tests, no game needed
tests/run.sh smoke                                     # loads, runs 120 ticks with a player
tests/run.sh points                                    # the pointer, point list, closed loops
tests/run.sh layers                                    # layer list and detail pane, presets, view settings
tests/run.sh build                                     # preview, totals, builds in all modes, blueprints
tests/run.sh types                                     # turrets, lamps, mines, radars, solar panels, accumulators
tests/run.sh paths                                     # belts and pipes: real entities flow, undergrounds pair, pumps split segments
tests/run.sh feeds                                     # inserters feed turrets, flamethrowers piped (straight, diagonal), gates over rails
tests/run.sh rails                                     # continuous track, signal sides, ghosts, blueprints, gates across walls (elevated with the DLC)
tests/run.sh build space-age quality elevated-rails    # same, with DLC mods enabled
tests/gen-rail-data.sh space-age elevated-rails quality # regenerate scripts/build/rail_data.lua
tests/migrate-save.sh                                  # the game applies migrations/ to a real save
tests/run.sh bench                                     # timing (read the BENCH lines in the log)
```

**Unit tests** (`tests/unit/`, plain Lua 5.4) load mod modules through
`helpers.lua`:

| Test | What it checks |
|---|---|
| `plan_snapshot.lua` | Planner output for 37 fixed cases matches `snapshots/plans.txt`. Run with `--update` only for an intended change, and review the diff. |
| `planner_jobs.lua` | Running the planner in tiny slices gives exactly the one-shot plan; a finished job keeps only `KEEP_WHEN_DONE`. |
| `plan_properties.lua` | Random curves and loops: no overlaps, wall layers never joined only at a corner where a corner cell was free, an unbroken layer 0 wall line (a ring through the seam for loops), poles in reach except counted gaps, and bend warnings where they belong. Adding an underlay anywhere never moves an entity or a tile. Smart poles: every powered entity is covered or counted in `plan.unpowered` (exactly), and without consumers the poles are about a wire reach apart. Circles and ellipses make an unbroken 1-wide wall ring; arcs are one piece. |
| `curve_edit.lua` | Inserting (including where a shift-click goes); reversing keeps the points and samples the curve backwards. |
| `layers.lua` | Which layer settings survive picking another item (`registry.carry_over`). |
| `presets.lua` | Preset list operations; export data round trip and import validation. |
| `layer_types.lua` | Turret facing (both sides, inward) and non-square footprints (other types too), ammo, lamp colours and rainbow, radar spacing, land mine density, determinism and wires; side wall layers around a circle joined side by side. |
| `paths.lua` | Belts fed only from behind and lines continuous, undergrounds paired within reach, pipe lines connected and apart, pumps; on a gentle curve, a loop and random curves. |
| `feeds.lua` | Fluid connection targets in every facing (straight and diagonal, against the game), inserters picking from a belt and dropping into their turret (normal and long reach, straight and curved lines), pipe stubs reaching one network, and a plain pipe where the line has pipes-to-ground. |
| `rails.lua` | The rail data; fits stay near calm curves, circles close, elevated track has ramps at both ends and supports in reach of every joint, slanted ends warn; signal counts follow the spacing (doubled both ways); planning progress never goes back. |
| `shapes.lua` | What the handles mean; samples exactly on circles, (rotated) ellipses and arcs; direction; editing shapes and moving curves; spaced entities round a loop keep apart at the seam. |
| `migrations.lua` | The files in `migrations/`, run like the game does, on old and current data. |

`helpers.plan` is the only place the tests touch the planner API.

**Game tests** (`run.sh`) need a local Factorio 2.1 install (default
`~/Games/factorio`; override with `FACTORIO=`).

- `run.sh` creates a throwaway config, write-data and mod folder (`WORKDIR=` to
  keep them), so it doesn't touch your game.
- Scenarios use `--test-scenario`, which runs headless with one player. They drive
  the real GUI handlers through the `bezierio-dev` remote interface. Scripts can't
  click elements or fire custom inputs, so `dev.lua` imitates what the engine does
  first. The hooks act as a player would: on the main window while a layer's
  settings are open, they press OK first; for a name that isn't there (a layer
  setting after that), they open the selected layer's settings again.
  `click_raw` clicks without either, to test the lock. `set_budget` sets the
  work budget.
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
