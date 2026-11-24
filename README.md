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
release/          release and mod portal scripts, and their tests (see Releasing)
.github/          CI and release workflows
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
tests/lint/check.sh            # type check with the Lua language server and the API stubs
python3 tests/lint/locale_keys.py   # every locale key the code names exists
python3 -m pytest release/tests tests/lint   # the release scripts' tests (pip install -r release/requirements.txt)
```

CI (`.github/workflows/ci.yml`) runs the unit tests, the lint and the Python tests
on every push and pull request. For the lint locally: `LUALS=` the
`lua-language-server` binary (the VS Code extension has one), `LUALS_LIBRARY=` a
folder made with `npx factoriomod-debug luals-addon --online 2.1.25 <folder>`.

The game tests need a local Factorio 2.1 (`FACTORIO=/path/to/bin/x64/factorio`,
default `~/Games/factorio/bin/x64/factorio`) and run in a throwaway config and mod
folder, so they don't touch your game. The DLC runs need the Space Age data.
See docs/DEVELOPMENT.md, Testing, for what each test checks and how to add one.

## Releasing

1. Put the release's changes in `changelog.txt` under the top section, which
   stays `Version: 0.0.0` while unreleased.
2. `python3 release/bump.py --version X.Y.Z`: sets the version in `info.json` and
   on that section, with today's date (fails if the changelog isn't ready).
3. Commit, tag `vX.Y.Z`, push the tag.

The release workflow (`.github/workflows/release.yml`) then checks the tag against
`info.json` and the changelog, the changelog's format and that no locale comment
is still `[unreviewed]` (`release/validate.py`); builds `Bezierio_X.Y.Z.zip` with
`git archive`, leaving out what `.gitattributes` marks `export-ignore` and with
`lib.debug = false` (`release/package.py`, the same bytes locally and in CI);
runs the unit tests and the lint on the unpacked zip; makes a GitHub release
with the changelog section as notes, and uploads the zip to the mod portal
(`release/upload.py`, needing the repository secret `FACTORIO_API_KEY` with
the "ModPortal: Upload Mods" permission).

To try it locally: `python3 release/package.py --out dist` and
`python3 release/validate.py --tag vX.Y.Z --zip dist/Bezierio_X.Y.Z.zip`.

## The mod portal page

`mod-portal/` is the page's one source of truth: `summary.txt`, `description.md`,
`faq.md`, and `images/` (shown in the order of `images/order.txt`). Push a tag
`portal-<anything>` (e.g. `portal-2026-11-25`) to bring the page in line, between
releases too (`.github/workflows/portal.yml`):

- `release/images.py` uploads images that are new or whose file changed (by
  SHA1), sets the page's images in order (ones not in `order.txt` come off), and
  records each image's SHA1 and portal id, URL and thumbnail in
  `images/mod-portal-ids.json`. The workflow commits that file to the default
  branch when the tag is its latest commit, otherwise leaves it as an artifact.
- `release/detail.py` sends the texts changed since the previous `portal-*` tag
  (all of them the first time), with the description's image links (raw GitHub
  URLs in the repository) swapped for the portal's.

Both take `--dry-run` (they only read the public page then; any non-empty
`FACTORIO_API_KEY` will do). The key needs "ModPortal: Edit Mods" for this, and
"ModPortal: Upload Mods" for releases: one secret with both.

## Contributing

Feedback and crash logs are welcome on the mod portal or on GitHub. Before a pull
request, run `tests/run_all.sh`; for new texts, follow the locale rule in
docs/DEVELOPMENT.md.

## License

MIT, see [LICENSE](LICENSE).
