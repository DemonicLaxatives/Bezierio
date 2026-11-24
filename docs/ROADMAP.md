# Bézierio roadmap

Status (2026-11-22): the mod loads and runs on Factorio 2.1.24. The whole loop works
and is covered by headless tests: place points → draw → configure layers → preview →
force/superforce build. Building ghosts was missing entirely since the 2.0 rewrite
and is now implemented for walls, tiles, electric poles, electric turrets and
roboports.

There's no release planned yet: refinement and features come first, release and its
automation last. Items are ordered by priority within each phase. **(rec)** marks my
recommendation where there's a choice.

Throughout: play-test in the real client as features land. Headless tests can't
judge feel: pointer handling, map view, preview readability. Every bug found by hand
should get a scenario in `tests/` so it stays fixed.

## Phase 0: groundwork refactor (done)

The code is reshaped so later phases mostly add files (see `docs/DEVELOPMENT.md`):

- **Layer types:** one file each in `scripts/layers/`, read by the planner, GUI and
  item picker through `registry.lua`.
- **Curves:** `scripts/curve/`, a curve kind plus control points behind a
  resumable sampler.
- **Builder split up:**
  - `geometry.lua` and `planner.lua`, the planner being a resumable job;
  - `executor.lua`, also a resumable job;
  - output modules (`ghost`, `instant`), with blueprint output to come as another
    one.
- **Tick-spread jobs:** planning, drawing and building run in `jobs.lua`, a
  budgeted amount per player per tick, with state in `storage`.
  - The 850-tile / 11-wide example plans and previews in ~100 ticks and builds
    instantly in ~20 ticks.
  - Nothing heavy runs in an event handler.
- **Storage migrations:** `state.lua` upgrades v2 saves to v3 instead of wiping
  them.
- **Cleanup:** dead code removed, snake_case throughout.

Plan output is unchanged: a snapshot of 27 cases taken before the refactor still
matches. Unit tests (`tests/unit/run_all.sh`) cover the snapshot, sliced vs one-shot
planning, random-curve properties and migrations.

## Phase 1: refinement (done)

- **Curves:** Catmull-Rom only (centripetal: passes through every point, no
  cusps), any number of points, and a *Closed loop* toggle. Saves are migrated
  (schema 4); existing curves change shape.
- **Smart pointer:** one pointer (button or Alt+B).
  - Click empty ground to append a point.
  - Click a point to pick it up; click again to drop it.
  - Right-click to remove a point, or to cancel a hold.

  The window lists all points with editable coordinates.
- **Window:** a compact layer list (colour, item, width, move/delete) with a
  detail pane for the selected layer. The preview uses the same colours. A status
  line shows planning/building progress; a totals line shows length, items per
  layer, bend warnings and pole gaps.
- **Planner:**
  - spaced entities search ±2 tiles along the curve before being skipped;
  - pole chains stay within wire reach (extra poles are inserted), and gaps
    without room are counted and reported;
  - tight bends are detected and marked in the preview;
  - 1×1 entities are no longer planned as 2×2 (sizes now come from the
    prototype's tile footprint).
- **Building:**
  - copper wire, plus red and green when *Circuit wires* is on, for ghosts and
    real poles;
  - a whole build is one undo item;
  - *Smart placement* removed;
  - rails hidden from the picker until they can be built.
- **Ticks:**
  - the work budget is a map setting (default 1000 ≈ 2.5–3 ms/tick, measured
    with the `bench` scenario);
  - planning waits 10 ticks after the last edit;
  - old render objects are destroyed over several ticks.
- **Multiplayer:** builds respect the permission group; drawings follow a surface
  change.
- `python_scripts/` deleted.

### Follow-ups (done)

- **Point editing:**
  - a selected point stays selected after it moves; right-click deselects;
  - points can be selected from the point list too (this takes the pointer if
    your hand is empty);
  - Shift + click inserts a point into the nearest stretch of curve, or before or
    after an end;
  - Shift + mouse wheel cycles the selection;
  - a reverse button flips the point order.
- **Totals:**
  - items are summed by item and quality, with a per-layer breakdown in the
    tooltip;
  - the tight-bends and pole-gaps counts have tooltips explaining them.
- **Big previews:** drawing stopped at a 4,000-object cap. The cap is now 50,000,
  straight runs of cells share a rectangle, and the status line says when the cap
  is reached.
- **Tile layers:** *Under entities* option. The band takes no room, and the
  layers further out sit on the tiles.
- **Window:**
  - the layer list scrolls;
  - a View settings pane sets point, curve and warning colours, curve width and
    preview opacity, per player;
  - the build icons are centred, with "Force build" and "Super force build"
    tooltips;
  - layer 0's delete button explains why it's disabled.
- **Planner:** open curves sometimes missed a cell or two at their ends (found by
  the new underlay property test). They're probed past the ends now.
- **Left as is:**
  - bend warnings use grid units;
  - very sharp turns can leave small stray pieces, a tradeoff of a rectangular
    grid.

## Phase 2: features

Done (group a):

0. **Migrations** follow the game's convention: files in `migrations/`, each acting
   only on its starting schema version (new games run them all). The game doesn't
   raise on_configuration_changed for migrations alone, so they flag a rebuild that
   the next tick or event does. `tests/migrate-save.sh` checks it on a real save.
1. **Blueprint output:** a Blueprint button puts the plan in the cursor, with
   absolute snapping offset so it lands on the preview. Wires and qualities are
   included. Built over several ticks; writing it into the item is one engine call
   (~18 ms for the 18k-entity bench curve).
2. **Presets:** a bar above the layer list to switch, rename, copy, delete,
   export and import layer stacks (versioned string; import rebuilds each layer
   like the picker, so missing items become empty layers and are reported).
7. **Split the GUI test** into `points`, `layers` and `build` scenarios with a
   shared `lib/flow.lua`; `tests/run_all.sh` runs everything.

Done (group b):

3. **Smart pole placement:** a pole layer option. Poles go as far apart as the
   wires reach, but early enough that every powered entity in the plan (electric
   energy source: turrets, roboports, ...) is in a supply area. Ones no pole can
   reach are counted and shown ("N unpowered"). Spacing is greyed out.
6. **Shape helpers:** circle, ellipse and arc as curve kinds (a drop-down next to
   the pointer button), placed with the pointer by their handles (centre + radius
   point; centre + axis end + width point; centre + start + end) and sampled
   exactly; each kind keeps its own points. Mirror the layer stack.

Group b follow-ups (done):

- Shapes are placed with the pointer instead of typed in (the numeric pane is
  gone), and dragging a shape's centre moves the whole shape.
- Move mode works on any curve: clicks move its centre there, right-click stops.
- Offsetting sideways was dropped.
- Reverse flips the direction of any kind (layers swap sides; inside / outside for
  a circle) without touching its points: the spline no longer reorders them. Each
  kind remembers its own direction, and the button shows it.
- The drawing shows how the handles are used: the ellipse's axes and the points
  its width handle and the arc's end handle actually use (marked, with a thin line
  from the handle); the point list shows the resulting radii and arc angle.
- Each layer in the list has a checkbox for showing it in the build preview (it's
  built either way), and the layer buttons show non-normal quality.

Done (group c1):

4. **More layer types**, first part:
   - all turret types (ammo, fluid, artillery, electric): turrets that can't turn
     all the way round face outward or inward (8 directions where the game allows
     and the footprint is square); ammo turrets request ammo (insert plan on ghosts
     and blueprints, loaded when building instantly), counted in the totals;
   - radars (spacing scaled to the revealed area), solar panels, accumulators;
   - lamps: own colour, one colour, or a rainbow along the curve;
   - land mines scattered at a density or on a grid, up to 63 tiles wide,
     optionally wired together.

Group c1 follow-ups (done):

- Diagonal turrets: the flamethrower faces all 8 ways (its diagonal footprint,
  from a reference blueprint, is the 3x3 square minus two corners, centred like
  the square); the railgun's fits its 5x5 square.
- Land mines: a grid pattern next to scattered, and a much wider band.
- Red and green wire are separate checkboxes, for poles and land mines.
- Smart poles: a refine pass after the greedy walk drops poles nothing needs and
  evens out spacing (the greedy walk left pairs a couple of tiles apart).
- The curve can be exported and imported as a string (for sharing, and for bug
  reports).

Done (group c2):

4. **Belts and pipes:** continuous lines following the curve (one-cell sub-bands
   ordered along the curve, diagonal steps joined through corner cells, spurs
   and doubled-back cells left out), several lines side by side with a gap (pipes
   at least one cell, so lines don't join), belts flowing along or against the
   curve and never feeding each other from the side, undergrounds on straight
   runs, pumps every N tiles for long pipelines. Known limit: where the curve folds
   back on itself, or a squeezed bend leaves no free corner, a line splits.

Group c2 follow-ups (done):

- Closed loops with several belt lines lost their inner lines: a loop's line end
  looked hemmed in by its own start, and trimming it ate the line. Loops now close
  (around the seam, through a corner when the ends meet diagonally), lines are
  routed all together before any entity is made (a line may take a corner from
  another, which then goes round it), and lines continue across the inside of a
  tight bend. The reported 8-line loop is a regression test.
- Preview arrows (black) for belts, undergrounds, pumps and turrets facing a way.
- Pump spacing stops at the pipe's `max_pipeline_extent` (less the pump), read in
  the data stage.
- The item picker filter and layer values are derived on use instead of stored
  (an old save didn't offer belts and pipes).

Done (group c3):

- **Turret feeds:** ammo turrets can get an inserter each, from a belt layer
  beside them; fluid turrets a pipe stub to a pipe layer beside them, facing any
  of 8 ways (diagonal connections worked out from the reference blueprint). The
  turret spot search prefers spots where the feed fits; the rest are shown as
  unfed (on diagonals, turrets packed side by side often are).
- **Gates:** a planned wall landing on an existing straight rail becomes a gate
  (*Gates on rails*, on by default); super force keeps such rails.

Done (rails, item 5):

- **Rails** fitted from the game's rail planner data (generated by
  `tests/gen-rail-data.sh`): a lookahead search over the next 4 pieces, loops
  closed, warnings where the curve is tighter than rails go.
- Signals every so many wagons on the travel side (both for both ways).
- *Elevated*: supports placed by range, ramps up and down (orthogonal only: curves
  starting or ending diagonally warn).
- Gates the other way round: a planned rail crossing your walls swaps them for
  gates (*Gates in walls*).
- Limits: rails cover more than one tile, so wall layers right beside them get cut
  (use *Offset*).

Done (side wall layers):

- Side wall layers could meet only at a corner, not just on the inside of tight
  bends: off to the side of any bend (a radius-40 bend, a radius-30 circle). A new
  planner stage fills a corner cell there, the free one nearest the band. Checked
  for every random plan and a fixed circle.

### Followups (done)
- After a build, unpowered and unfed entities are marked on the map (a frame and an
  icon each) for a per-player time, default a minute (0: until hidden); clicking
  the warning in the window shows or hides them. They go with the warnings when
  an edit drops the plan. The totals and warnings also show after a build with
  the preview off.
- Blueprints carry the curve and preset they were made from. A description holds
  at most 500 characters, too few for both, so they are tags on the blueprint's
  first entity, with a note in the description; **Load from generated blueprint** reads them
  back (from the cursor, a book or the blueprint library). A per-player setting
  turns it off.
- Test ground covers the whole area the scenarios clear: water from random map
  generation sometimes blocked a ramp at the end of the elevated test track.

## Phase pre-3: GUI and controll upgrades

Decided (mockups: the "Bézierio window layouts" canvas): layout B, one column of
Curve, Layers and Build, with a narrow mode where the whole window collapses
together (points as chips that scroll past 4 rows, tools in rows); layer
settings in their own window, edits live and Cancel reverting; a pin in the
title bar. Groups: a) layout, shading, alignment, loop button, add bars, no
mirror, new preset, pin, narrow mode, layer settings window, settings window
(the view settings plus the former per-user mod settings, the gear in the title
bar), sunken list and summary panes, wider button spacing (done); b) import /
export windows (done); c) job status and queue, disabling a layer, turret targeting
priorities, facing tooltips (done).

  - Closed loop toggle is an odd one out. It should be a button.
  - Have the panels, and elements within them align to one another. 
  - Give the list entries alternating shaded backgrounds. 
  - The button for adding a layer should take the full width of the layer in gui, but also be shorter in height.
  - Give the user the option to collapse some parts of the gui, like the point coordinates, layer controls, etc. and in the collapsed mode hide some of the buttons and controls. 
  - Disable a layer's placement (plan for it).
  - show the status of  the job, as well as the queued commands, like force build
  - get rid of the layer mirroring button.
  - In the turrets config panel give the user a way to set the targeting priorities
  - Give tooltips to the turret facing paramater, so that it's clear what which direction means
  - Add a button to add a new preset.
  - curve/preset imports/exports should open their own windows with the text fields.
  - layer config panels should be in their own windows, which, untill accepted, would lock the main gui.
  - On top of the rest of the suggestions make it more cohesive and nicer. Give me options on how you see fit some things should be rearanged.

## Phase post-pre-3:
- A full code-review. Make sure the code reads well, doesn't reapeat itself and stays maintainable.

Review findings (2026-11-24, four parallel reviews, each finding checked against
the code; "repro" = reproduced with a script):

Bugs:
1. Super force clears things it shouldn't: `item-on-ground` is a name, the type
   is `item-entity`, so dropped items, character corpses (`character-corpse`)
   and flying robots are destroyed in instant mode; ghosts of any force are
   destroyed (executor.lua IGNORED_IN_THE_WAY, the ghost branch).
2. The pointer button overwrites whatever the player holds (curve_control
   "pointer": `set_stack` without an empty-hand check; `take_pointer` does it
   right). Items are lost.
3. The "locked" main window uses `ignored_by_interaction`, which passes clicks
   through: with the pointer in hand a click on it adds a curve point behind.
4. Import: `offset` isn't clamped (an offset of 1e5 stalls planning forever,
   repro) and numbers aren't rounded (radius 2.5 changes the plan, repro);
   `valid()` sees non-string item values; priority targets accept any entity.
5. Belt reroutes lose the curve sample of corner cells (`use()` stores j = 0),
   so a rerouted line splits at that corner (repro: 51 of 300 random plans change).
6. A closed spline with a repeated point is planned as a loop but sampled open
   (`curve.is_closed` counts raw points, the sampler distinct ones; repro).
7. Crashes when another mod destroys what we just built (no `.valid` after
   `create_entity` in the outputs; `own()` counts invalid entities as placed);
   and after an aborted build (deleted surface) `highlight.show` reads an invalid
   surface.
8. Rail gates: the wall is removed before checking the gate fits (instant mode
   leaves a hole); gates aren't counted.
9. A finished build's work isn't taken off the tick budget (jobs.lua drops
   `used`), so that tick can run up to twice the budget.
10. `state.reset` (schema mismatch) destroys only the main window: a layer window
    open then can never be closed. Windows also survive mod updates unchanged.
11. Removed quality / item / entity: `refresh` doesn't check `layer.quality`
    (wire reach calls with an unknown quality), nor `ammo`, `inserter`,
    `priority_targets`, `placed_by` (pickers would get unknown values).

Budget (single-tick spikes):
- Smart pole "count" phase is O(consumers × poles) in one call (repro: 0.45 s
  at 8000 tiles, 2.5 s at 16000).
- Catmull-Rom pieces aren't split: one 20000-tile segment samples in one call
  (repro: 0.25 s); also ~30% more samples than the 0.25 step needs.
- `draw.delete_sprites` walks every render object (up to 50 000) in one call;
  `step_trash` then blocks all other work while it drains.
- Whole path lines, rail laying and `rails.close` run in one call each.
- The finished PlannerJob keeps dead per-cell tables (`feed_*`, `recent`,
  `bands`) in storage.

Risks:
- `player.opened` is set inside on_gui_closed handlers (the API force-closes the
  new GUI then): opening a chest while the layer / import window is open can
  leave the main window not `opened`.
- Closed loops can get two spaced entities ~1 tile apart at the seam (repro).
- Pipe stubs may end beside a pipe-to-ground's side (not connected in game).
- Clicks with the right mouse button run actions (delete layer, build).
- "Already there" ignores direction (belts / rails facing another way count as
  built); the super force clearing square is bigger than non-square footprints.
- Electric pole spacing range can be empty for odd modded poles; defaults aren't
  clamped; non-square non-turret modded entities are centred wrongly.
- Revived ghosts aren't remembered as this build's own, and lose their ammo
  request.

Status (2026-11-24, uncommitted on `refactor`; `tests/run_all.sh` passes):

- Bugs 1-11: fixed, each with a unit or game test (super force leaves items on
  the ground and corpses; the pointer keeps the hand, or refuses on a full
  inventory; the lock via `click_raw`; import clamps offset 1e5 and rounds radius
  2.5; ...). The dev hooks now act as a player would: they press OK before using
  the main window while a layer's settings are open, and open the selected
  layer's settings again for a layer setting.
- Budget: smart pole counting bucketed (445 ms -> 18 ms worst step at 8,000
  tiles); long spline segments split (first step on a 20,000-tile segment: 8
  ms; the remaining spikes there are Lua's garbage collector, ~10 ms with it
  stopped); old previews go into the trash as whole caches, and the trash takes
  at most half the budget; a finished PlannerJob keeps only `KEEP_WHEN_DONE`.
  (A save from before keeps its finished job's tables until the next plan.)
- Risks: all handled.
  - The main window gets `player.opened` back on the next tick when it was
    lost inside `on_gui_closed`, and only once nothing else is open
    (`window.focus_main`).
  - Spaced entities skip a spot within half a spacing of the first one at a
    loop's seam (lamps round r = 10.52: 1.00 -> 5.39 apart; 3 snapshot cases
    lost their seam duplicate).
  - Turret pipe stubs join only plain pipes (pipes-to-ground and pumps don't
    connect sideways).
  - Right clicks don't act.
  - Belts, undergrounds, pipes-to-ground, pumps and inserters facing another way
    aren't "already there"; super force replaces them (in ghost mode: marked for
    deconstruction, ghost placed).
  - The super force clearing area is the collision box turned the planned way.
  - Pole spacing range and defaults clamped.
  - Every non-square entity is fitted to its grid.
  - Revived ghosts are this build's own, with priorities and ammo.
- Cleanup: all done (`build/wires.lua` shared by the executor and the blueprint;
  class annotations; DEVELOPMENT.md; dead locale key; `ammo_quality`; progress
  monotonic through rails, with a test; `window.find` remembers what it found;
  Cancel without changes doesn't plan again; `grid_distance`'s parameter; one
  sort of path cells).
- Budget, the last finding: path lines were set up, routed and made into
  entities a whole line per call (worst `paths` step ~53 ms on an 8,000-tile
  curve with 2 belt and 2 pipe lines). Now each is budgeted: the setup files a
  number of cells per step, `paths.step_segments` orders a line resumably (a
  merge sort that can stop anywhere, then the walk a cell at a time), corners
  are joined a segment and entities made a part at a time. Worst step: 5.4 ms
  (`paths.pieces` and `join_corners` on one whole part / segment, ~4 ms per
  8,000 tiles; split those if lines get much longer). Rails measured: the
  `rails` stage stays at 3-6 ms on a 4,000-tile curve (ground and elevated) and
  a radius-600 loop, `rails.close` under 1 ms: nothing to do.

## Phase post-post-pre-3: more features and findings

- (done) force build and super force build has to place landfill/foundations/ice platforms for entites that collide with the underlying tiles. The tile to place should be automatically detected and applied. Like landfill on water or foundation on lava, etc. Foundation and landfill can bothj build over water, but it makes more sense to use landfill when applicable. Give the user a setting in per player settings to set priority on these tiles, autodetect and decide when no valid tiles are set in the priority list. I think the behaviour should be inferrable from the tile prototype definitions: https://lua-api.factorio.com/latest/prototypes/TilePrototype.html
- (done) Force build should deconstruct cliffs, 
- (done) the intended force and super force building behaivor is described in this blogpost, we should try to replicate it: https://factorio.com/blog/post/fff-383
- (done) we need a build action "Build", which does not mark trees for deconstruction or lay landfill or alike.
- (done) non square power consumers/producers can end up disconnected from the network and the fact undetected (for example railgun), because they're treated as squares in the check. Planning the overall layout with them assumed as squares is an acceptable trade-off, but smart pole placement should not make the same assumption.
- (done) Sometimes the build work ends up split in the LuaUndoRedoStack, ensure that the whole build is one item. Looks like it happens when the build overlaps an existing one. (It was a full undo stack: 100 items, after which counting fails; the item is found by a tag now. Not fixed: ghosts revived by an instant build aren't in the undo item, `revive` takes no undo index.)
- (done) break up `scripts/build/planner.lua` (stages in `scripts/build/plan/`) it has balooned
- (done) Make the readme a more of a technical description of the mod, with how to run tests, publish, etc. At the top, put a link to `mod-portal/description.md` which will be the user side doc, that lives on the mod page too, containing essentially what the current one does, just with some nice images in the beginning, and a how-to section.
- (done) Describe every en locale element in a comment, which element each is for, what it does. Mark each for human review. Make it a project rule to do so for each newly created local element.

## Phase 3: release, CI and automated release

### CI (GitHub Actions, on every push and PR) (done: `.github/workflows/ci.yml`, `tests/lint/`)

1. **Unit job:** install `lua5.4` and run `tests/unit/run_all.sh`. It finishes in
   seconds and needs no game.
2. **Lint job:**
   - run the Lua language server in check mode (`lua-language-server --check`)
     with the Factorio API stubs, so API misuse fails the build like it shows in
     the editor;
   - check that every `{"section.key"}` used in code exists in
     `locale/en/Bezierio.cfg` (a small script).

# Automated release/detail sync/image sync (on pushing a tags)
**Use Python scripts using requests (with tests, that don't touch the actual API) for interfacing with the API, packaging, version bumps, validation, etc**
- portal API key stored as a repository secret.
- edit version numbers, release dates and refrence jsons in the repo.

## Release (done: `release/`, `.github/workflows/release.yml`; to try on the first real tag)

0. **Version bumps:** a small script `release/bump.py --version "X.Y.Z"`, that updates 
  - `info.json`, ensure the correct version, edit it repo if needed
  - `changelog.txt` match the latest version for 0.0.0 - fail if the latest version isn't matched, in the repo update the date on that entry to the current date
  - in a copy to be packaged, not the repo, set `lib.debug = false` 

1. **Validate:**
   - the tag matches `info.json` and `changelog.txt`
   - `changelog.txt` has a correctly formatted entry for that version (Factorio's
     format is strict about the dashes line and indentation);
   - `debug.lua` has `lib.debug = false`.
   - no `[unreviewed]` entries in the english locale, except in the top description.
2. **Package:** `Bezierio_X.Y.Z.zip` containing a top-level `Bezierio_X.Y.Z/`
   folder. Exclude `tests/`, `python_scripts/`, `docs/`, `.vscode/`, `mod-portal`, `release` and `.github/`.
   Generate it with `git archive` plus an exclude list (`.gitattributes`
   `export-ignore`), so local and CI zips are identical.

3. **Run the CI jobs** against the packaged zip (unzip it into the test mod
   directory), so what's tested is what ships.
4. **Publish:**
   - create a GitHub release with the zip and the changelog section as notes;
   - https://wiki.factorio.com/Mod_upload_API,

## Modportal sync (done: `portal-*` tags, `release/images.py`, `release/detail.py`, `.github/workflows/portal.yml`)
- not via `vX.Y.Z`, let's figure out a different tag format, so we can update the details and images in between releases
- as one tag for both images and details, images first, then details

### Modpage image sync
- keep the one source of truth for modpage images in the repo.
- https://wiki.factorio.com/Mod_images_API
- write mod portal id refrences in the repo, the `mod-portal/images/mod-portal-ids.json`
- order them with respect to `mod-portal/images/order.txt`
- detect changes, reordering, etc, and keep that in sync with mod portal. Skip if nothing is changed

### Modpage detail sync
- keep the one source of truth for details on the mod page in the repo.
- API (`api/v2/mods/edit_detail`) https://wiki.factorio.com/Mod_details_API
- use details files from `/mod-portal/`
- autodetect the changed detail files from the last tagged commit, and only push the changed fields
- details in the desciption will contain github refrences, for the upload replace them with the mod portal links. Keep them as is in the repo.

## Release hygiene for the first release (0.2.0)

- New screenshots for the README and mod portal. The current ones show the 0.1
  curve projector.
- A real multiplayer test: a manual session with two players (everything is per
  player and in `storage`, but nothing has run two players at once yet). Lay out a plan for what and how should be tested. Let's put it off for now, when it comes to this step, let's just document it in the next roadmap.
- Remove the dev-migrations, they're usefull for seamless testing but serve no purpose for the end user on initial release.
- A storage migration test ground work, there will be no migrations for release: create a save with schema N, load it with N+1, check
  nothing crashes (`--test-save`). Releases are when old saves start to matter.
- Update the changelog
- Cleanup the completed roadmap, no need to summaraize everything that's done on main, git history will still be there. On main the roadmap should really contain just what's left to do.
- Add some default presets to ship it with. They're in the folder builtin-presets, bake them into the scripts.
- Let a human pass over the locale, review it, some of them are far too verbose.


## Testing to add along the way

- A scenario per new layer type (ghost counts match the plan, no overlaps).
- A scenario for every bug found by hand.
- Run `tests/unit/run_all.sh` after touching the planner; update the snapshot only
  for intended changes.
