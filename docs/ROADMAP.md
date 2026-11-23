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

To do:

- Side wall layers on the inside of tight bends can be joined only diagonally (the
  bands get squeezed there; found with belts, never checked for walls).



## Phase 3: release, CI and automated release

### CI (GitHub Actions, on every push and PR)

1. **Unit job:** install `lua5.4` and run `tests/unit/run_all.sh`. It finishes in
   seconds and needs no game.
2. **Lint job:**
   - run the Lua language server in check mode (`lua-language-server --check`)
     with the Factorio API stubs, so API misuse fails the build like it shows in
     the editor;
   - check that every `{"section.key"}` used in code exists in
     `locale/en/Bezierio.cfg` (a small script).
3. **Game job:**
   - IMPORTANT: not part of the CI job, just a script to run by the dev on their own machine
   - run `tests/run.sh smoke` and `tests/run.sh gui-flow` with `FACTORIO=` pointing
     at it.

   Open questions to verify first:
   - Does the headless build support `--test-scenario`? It's the same CLI, but
     check.
   - DLC variants: Space Age and its mods are not in the free headless download,
     so the space-age test can only run where the DLC data is available (e.g. a
     self-hosted runner, or keep it a local pre-release step).
4. Make `run.sh` print the failing step clearly and upload the full log as a job
   artifact on failure.

### Automated release (on pushing a tag `vX.Y.Z`)

1. **Validate:**
   - the tag matches `info.json` `version`;
   - `changelog.txt` has a correctly formatted entry for that version (Factorio's
     format is strict about the dashes line and indentation);
   - `debug.lua` has `lib.debug = false`.
2. **Package:** `Bezierio_X.Y.Z.zip` containing a top-level `Bezierio_X.Y.Z/`
   folder. Exclude `tests/`, `python_scripts/`, `docs/`, `.vscode/` and `.github/`.
   Generate it with `git archive` plus an exclude list (`.gitattributes`
   `export-ignore`), so local and CI zips are identical.
3. **Run the CI jobs** against the packaged zip (unzip it into the test mod
   directory), so what's tested is what ships.
4. **Publish:**
   - create a GitHub release with the zip and the changelog section as notes;
   - upload to the Factorio mod portal via its upload API
     (`/api/v2/mods/releases/init_upload`, then POST the file to the returned URL),
     with the portal API key stored as a repository secret.
5. **Version bumps:** a small script (`scripts/release.sh X.Y.Z`, or a manual
   workflow) that updates `info.json`, adds the changelog header and creates the
   tag, so releasing is one step.

### Release hygiene for the first release (0.2.0)

- GUI and controll upgrades
  - On top of the rest of the suggestions make it more cohesive and nicer. 
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
- `debug.lua` `lib.debug = false` (enforced by the release check above).
- New screenshots for the README and mod portal. The current ones show the 0.1
  curve projector.
- A real multiplayer test: a manual session with two players (everything is per
  player and in `storage`, but nothing has run two players at once yet). Lay out a plan for what and how should be tested.
- Remove the dev-migrations, they're usefull for seamless testing but serve no purpose for the end user on initial release.
- A storage migration test ground work, there will be no migrations for release: create a save with schema N, load it with N+1, check
  nothing crashes (`--test-save`). Releases are when old saves start to matter. 
- A full review.

## Testing to add along the way

- A scenario per new layer type (ghost counts match the plan, no overlaps).
- A scenario for every bug found by hand.
- Run `tests/unit/run_all.sh` after touching the planner; update the snapshot only
  for intended changes.
