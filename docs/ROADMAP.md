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

### Follow-ups found along the way

- **Insert a point between two others.** The pointer only appends. Option:
  click near the curve (not a point) to insert there.
  - Yes let's do it, shift + click near the curve
  - Also, let the user select the point not just by clicking on it in the world but also in the gui, don't deselect the point after it's been moved, let it be cleared by righ click in the world, just like it already is
  - when a point has been selected, let the user shift + scroll to cycle the exising points
  - add a button between closed loop and remove controlpoints, that swaps the point order - flipping the tangent direction.
- **A real multiplayer test.** Everything is per player and in `storage`, but
  nothing runs two players at once. A headless server plus a client isn't
  possible in `--test-scenario`; this needs a manual session. 
  - Let's put this off for later - pre-release.
- **Bend warnings use grid units**, which underestimate distance on diagonals by
  up to √2. Fine as a hint; refine if it misleads.
  - Leave as is, just give a tooltip on the "N Tight bends" warning explaining the issue better, without going into detail on the underestimation, just explain what the warning means in general.
- **Very sharp turns** still leave small stray pieces of wall (a few cells) at the
  tip. They're cosmetic, and the property test tolerates pieces under 10 cells.
  - That's fine, it's a tradeoff of trying to make sharp turns on a rectangular grid.
- Bug, larger build preview jobs fail at some point, builds fine, just the drawing stops at some point.
- Make it an option that tile bands don't offset entity bands, they have no collision with them, so it would be nice to have them under the entities.
- Layer list should also become scrollable at some size
- We need per player settings on the sprite colors, opacity, etc. accesible from the mod gui.
- Build icons are offset to the upper right corner in their slots, further more shorten their tooltips to just "force build" and "super force build" these are ingame terms with an already defined meaning.
- Build costs should be totalled and list qualities too, only in tooltips show the breakdown per layer.
- Give a tooltip on why L0 can't be deleted.


## Phase 2: features

1. **Blueprint output (rec: highest-value feature).** Write the plan into a
   blueprint in the cursor instead of placing ghosts. Players can then
   stamp/rotate/share it, and it works with any build mode the game supports.
2. **Presets.** The data model already has `presets[]` but the GUI only uses #1.
   Add save/rename/switch, and export/import as a string.
3. **Pole smart placement.** Override spacing, placing the poles as far as possible from one another, 
but when there's consumers along the way, ensure they're all powered. 
Just like drag placing poles works in game.
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
5. **Rails.** Fit 2.0 rail pieces (straight, half-diagonal, curved-a/b) to the
   curve, plus signals at a spacing measured in wagons (fields already exist).
   This is the largest item: it needs a search over rail-piece sequences that stays
   within a tolerance of the curve. `scripts/layers/rail.lua` is the stub (it is
   `placement = "unsupported"` today).

6. **Shape helpers:** circle/arc/ellipse generators (see
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
