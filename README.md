# Bézierio

A Factorio 2.1 mod for building walls, floors, power lines, turrets, belts, pipes
and rails along a curve.

**Using the mod:** see [mod-portal/description.md](mod-portal/description.md), the
player's guide. It is also the mod portal page.

This README is for working on the mod.

## Repository

```
info.json, control.lua, data.lua, ...   the mod (see docs/DEVELOPMENT.md, Layout)
scripts/          runtime code: state, jobs, planner, executor, GUI, layers
prototypes/       items, custom inputs, sprites, styles
locale/en/        texts; every key commented (see docs/DEVELOPMENT.md, Locale)
migrations/       save upgrades
graphics/         icons
tests/            unit tests (plain Lua) and game test scenarios
docs/             DEVELOPMENT.md (how it works), ROADMAP.md (what's next)
mod-portal/       the mod portal page: description, FAQ, summary, images (with
                  their order and portal ids)
release/          release and mod portal sync scripts (stubs, see Releasing)
```

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) explains how the mod works: storage,
the per-tick job runner, the planner's stages, building, the GUI and the tests.
[docs/ROADMAP.md](docs/ROADMAP.md) lists what's done and what's next.
[CLAUDE.md](CLAUDE.md) holds project rules for AI assistants (and people).

## Running it

Link or copy the repository into your Factorio mods folder as `Bezierio` and
enable it. The `tests/` folder and the repository files (`docs/`, `mod-portal/`,
`release/`, `CLAUDE.md`) don't belong in a release zip.

## Tests

```sh
tests/unit/run_all.sh          # unit tests: plain Lua 5.4, no game needed
tests/run.sh <scenario> [mods] # one game scenario headless (smoke, points, layers,
                               # build, types, paths, feeds, rails; mods: space-age
                               # quality elevated-rails)
tests/run_all.sh               # everything: unit tests, every scenario (some also
                               # with the DLC), the save migration test
tests/run.sh bench             # timing (BENCH lines in the log)
```

The game tests need a local Factorio 2.1 (`FACTORIO=/path/to/bin/x64/factorio`,
default `~/Games/factorio/bin/x64/factorio`) and run in a throwaway config and mod
folder, so they don't touch your game. The DLC runs need the Space Age data.
See docs/DEVELOPMENT.md, Testing, for what each test checks and how to add one.

## Releasing

The plan, in [docs/ROADMAP.md](docs/ROADMAP.md) (Phase 3):

- `release/upload.py`: package the mod (without the repository files), bump the
  version in `info.json` and `changelog.txt`, upload through the mod portal API
  and make a GitHub release, on pushing a version tag.
- `release/images.py`: keep the portal's images in sync with
  `mod-portal/images/` (order from `order.txt`, ids in `mod-portal-ids.json`).
- `release/detail.py`: push changed `mod-portal/` texts to the portal page, with
  repository image links replaced by portal ones.

They are stubs so far. Until then: zip the mod folder without the repository
files, named `Bezierio_<version>.zip`, and upload it on the mod portal.

## Contributing

Feedback and crash logs are welcome on the mod portal or on GitHub. Before a pull
request, run `tests/run_all.sh`; for new texts, follow the locale rule in
docs/DEVELOPMENT.md.

## License

MIT, see [LICENSE](LICENSE).
