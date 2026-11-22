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

## Phase 1: refinement

- **Undo support.** Pass `undo_index` to `create_entity` (or use
  `player.undo_redo_stack`) so Ctrl+Z removes a whole build. Without it, a bad
  build is painful to clean up.
- **Calibrate the work budget.** `jobs.BUDGET` and the `COST` tables are rough
  guesses. Headless runs suggest ~7–9 ms of work per tick at the current budget,
  which is too much next to the game's own 16.6 ms.
  - Measure (e.g. with `--benchmark` on a save with a large curve) and tune.
  - Consider a per-map setting.
- **Restarts while editing.** The plan is now kept when only the view changes,
  but every curve or layer edit restarts it. Dragging a slider restarts once per
  step. Consider waiting a few ticks after the last edit before starting, and a
  progress note for long plans and builds.
- **Batch sprite deletion.** Clearing a full preview (up to 4000 render objects)
  happens in one tick; spread it like the rest.
- **Electric pole reach guarantee.** After grid snapping, check the distance to the
  previous pole and insert an extra pole when it exceeds the wire reach. The
  default spacing is reach − 1, which is usually but not always enough.
- **The *Smart placement* and *Circuit wires* checkboxes** are stored but do
  nothing. Implement circuit wires (connect consecutive pole ghosts) and hide smart
  placement until it has a meaning.
- **Rails:** hide them from the layer picker until they are buildable **(rec)**.
  Today they can be chosen but are skipped with a message.
- **Curves with many points (rec: piecewise cubic).** One Bézier of degree up to 8
  is hard to steer: every point pulls on the whole curve. Recommended:
  - treat points as a chain of cubic segments (Catmull-Rom or a uniform B-spline,
    selectable);
  - allow more than 9 points;
  - offer "close loop" as a toggle instead of duplicating P1.

  This is a new curve kind in `scripts/curve/` next to `bezier.lua`. The curve data
  already allows any number of points; the GUI's 9 slots are the limit.
- **Edit points directly in the world:** click near an existing point to pick it up
  and drag it.
- **Tight bends:** side layers split where the bend is tighter than their distance
  from the curve. Show this in the preview (highlight where curvature radius <
  outermost layer distance) rather than silently producing gaps.
- **Spaced entities skipped on collision:** search a little further along the curve
  (±1–2 tiles of arc) before giving up. The build message already counts skipped
  entities.
- **GUI layout.** Layer rows grow wide as sliders are added.
  - Consider a compact layer list (index, item, thickness) plus a detail pane for
    the selected layer.
  - Colour each layer the same in the list and the preview.
  - Show totals: curve length, item counts per layer (a bill of materials).
- **Decide whether `python_scripts/` stays** in the repo (offline experiments, not
  used by the mod).
- **Multiplayer pass:**
  - rendering is already per player and state is per player;
  - check force/permission handling, e.g. whether a player may build at all
    (`player.permission_group`);
  - check behaviour when a player changes surface while the window is open.

## Phase 2: features

1. **Blueprint output (rec: highest-value feature).** Write the plan into a
   blueprint in the cursor instead of placing ghosts. Players can then
   stamp/rotate/share it, and it works with any build mode the game supports.
2. **Presets.** The data model already has `presets[]` but the GUI only uses #1.
   Add save/rename/switch, and export/import as a string.
3. **More layer types**, prioritised by defence use:
   - ammo turrets (with optional ammo request);
   - land mines (scattered with a density);
   - lamps (spacing);
   - pipes and belts (directional: needs the tangent → direction mapping);
   - gates where a rail or belt crosses a wall.
4. **Rails.** Fit 2.0 rail pieces (straight, half-diagonal, curved-a/b) to the
   curve, plus signals at a spacing measured in wagons (fields already exist).
   This is the largest item: it needs a search over rail-piece sequences that stays
   within a tolerance of the curve. `scripts/layers/rail.lua` is the stub (it is
   `placement = "unsupported"` today).
5. **Shape helpers:** circle/arc/ellipse generators (see
   `python_scripts/generate_circles.py`), mirroring the layer stack, offsetting the
   whole curve.

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
   - download the Factorio headless server at a pinned version
     (`https://factorio.com/get-download/<version>/headless/linux64`, no login
     needed) and cache it;
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

- `debug.lua` `lib.debug = false` (enforced by the release check above).
- New screenshots for the README and mod portal. The current ones show the 0.1
  curve projector.
- A storage migration test: create a save with schema N, load it with N+1, check
  nothing crashes (`--test-save`). Releases are when old saves start to matter.
- Quality: build with a non-normal quality under the `quality` mod and check the
  ghost quality.

## Testing to add along the way

- A scenario per new layer type (ghost counts match the plan, no overlaps).
- A scenario for every bug found by hand.
- Run `tests/unit/run_all.sh` after touching the planner; update the snapshot only
  for intended changes.
