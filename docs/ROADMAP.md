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

To do:

4. **More layer types**, prioritised by defence use:
   - pipes and belts 
      - directional: needs the tangent → direction mapping
      - skip sharp kinks - ensure a continuos line;
      - allow placing multiple parralel lines;
      - avoiding cross connections, especially for pipes, as adjecent pipes will always connect;
      - respect pipe extent limits, place pumps to account for them;
      - Parameter to maximize underground placement where possible, like long straight stretches.
   - All turret types:
      - respect turrets attack parameters, importantly turn_range, so turrets with a limited turn range are facing outwards. 
      - ammo turrets:
          - optional ammo request;
          - optional infeed belt with inserters - respect inserter pickup/placement locations, ignoring mods that let the user change them at  will, maybe worth considering it at a later stage, but not now.
      - fluid turrets with:
          - pipes
   - land mines (scattered with a density, optional parameter to connect them up with circui wires);
   - lamps (spacing, colors - monochrome, a cyclic color pallete takings samples from the curve lenght);
   - gates where a rail or belt crosses a wall.
   - solar pannels - spacing
   - acumulators - spacing
   - radars - spacing, autoscale the slider with their range
5. **Rails.** Fit 2.0 rail pieces (straight, half-diagonal, curved-a/b) to the
   curve, plus signals at a spacing measured in wagons (fields already exist).
   This is the largest item: it needs a search over rail-piece sequences that stays
   within a tolerance of the curve. `scripts/layers/rail.lua` is the stub (it is
   `placement = "unsupported"` today). Give the user a toggle to lay elevated or normal rails, 
   will have to do the support calculations ourselves.


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

- GUI upgrades, make it more cohesive and nicer. Have the panels, and elements within them align to one another. Give the list entries alternating shaded backgrounds. The button for adding a layer should take the full width of the layer in gui, but also shorter in height. Give the user The option to hide some parts of the gui, like the point coordinates, layer controls, etc. and in the collapsed mode hide some of the buttons and controls.
- `debug.lua` `lib.debug = false` (enforced by the release check above).
- New screenshots for the README and mod portal. The current ones show the 0.1
  curve projector.
- Quality: build with a non-normal quality under the `quality` mod and check the
  ghost quality.
- A real multiplayer test: a manual session with two players (everything is per
  player and in `storage`, but nothing has run two players at once yet).
- Remove the dev-migrations, they're usefull for seamless testing but serve no purpose for the end user on initial release.
- A storage migration test ground work, there will be no migrations for release: create a save with schema N, load it with N+1, check
  nothing crashes (`--test-save`). Releases are when old saves start to matter. 
- A full review.

## Testing to add along the way

- A scenario per new layer type (ghost counts match the plan, no overlaps).
- A scenario for every bug found by hand.
- Run `tests/unit/run_all.sh` after touching the planner; update the snapshot only
  for intended changes.
