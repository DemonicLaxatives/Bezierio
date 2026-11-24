# Bézierio roadmap

What's left to do. Done work isn't listed: the git history has it, and the roadmap
as it stood before this cleanup is `git show 42e9e52:docs/ROADMAP.md` (phases 0
to 3, with the reviews and their findings).

Throughout: play-test in the real client as features land. Headless tests can't
judge feel: pointer handling, map view, preview readability. Every bug found by hand
gets a scenario in `tests/`, so it stays fixed.

## Release 0.2.0

1. Merge `refactor` into `main` (CI runs there).
2. The repository secret `FACTORIO_API_KEY` needs "ModPortal: Upload Mods" as well
   as "ModPortal: Edit Mods" (the page sync already uses that).
3. `python3 release/bump.py --version 0.2.0` (the changelog's top section is
   already 0.2.0: it sets today's date), commit, tag `v0.2.0`, push the tag. The
   release workflow validates, packages, tests the zip and publishes; see the
   README, Releasing.
4. Afterwards, a `portal-*` tag on `main` if the page should change with it.

## Multiplayer test (after the release)

Everything is per player and in `storage`, but nothing has run two players at once
yet. A manual session (a host and a second client, or two clients on a local
headless server), checking:

- **Isolation:** each player's window, curve, layers, presets, settings, preview and
  marks are their own; one player's edits don't redraw or replan the other's.
- **Working at once:** both plan and preview big curves together (the work budget is
  per player: watch the update time); both build together, also over each other's
  spots; each build is one undo item in its own player's undo stack.
- **Joining and leaving:** a player joining mid-build sees none of the other's
  drawings; a player leaving mid-build stops their build cleanly; rejoining finds
  their curve and presets.
- **Permissions:** a player whose group can't build gets the message; the other
  still builds.
- **Desyncs:** part of the session with the game's consistency checks on (jobs are
  plain data in `storage`, so there should be none).

Afterwards: turn what the session found into scenarios where a single headless
player can reproduce it.

## Known limits

- Ghosts revived by an instant build (cheat mode, map editor) aren't in the build's
  undo item: `LuaEntity.revive` takes no undo index.
- Planning: `paths.pieces` and `join_corners` work on one whole line part or
  segment per call (about 4 ms per 8,000 tiles); split them if lines get much longer.
- Super force with ghosts marks obstacles for deconstruction before the final
  placement check; if the entity still can't go there, the marks stay.
- Cover tiles (landfill, foundation, ...) aren't in the totals or in blueprints:
  the planner doesn't look at the map.
- Geometry: on the inside of a bend tighter than a side layer's distance from the
  curve, that layer splits; a near-cusp can leave stray pieces; where the curve
  folds back on itself, or a squeezed bend leaves no free corner, a belt or pipe
  line splits; rails cover more than one tile, so wall layers right beside them get
  cut (use *Offset*).
- The lint (`tests/lint/check.sh`) catches API misuse like unknown fields, but not
  every wrong argument type.

## Testing along the way

- A scenario per new layer type (ghost counts match the plan, no overlaps).
- A scenario for every bug found by hand.
- Run `tests/unit/run_all.sh` after touching the planner; update the snapshot only
  for intended changes.
