#!/usr/bin/env bash
# Checks that the game applies migrations/ to a real save: creates a save whose
# Bézierio storage is in an old layout, then loads it with the current mod.
#   1. --create with a copy of the mod that has no migrations/ folder; the fixture
#      mod writes old data into storage in on_init.
#   2. load that save (--benchmark, a few ticks) with the real mod: the game runs
#      the migration files, then on_configuration_changed, where the fixture checks.
# Usage: tests/migrate-save.sh   (FACTORIO=, WORKDIR= as for run.sh)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
FACTORIO="${FACTORIO:-$HOME/Games/factorio/bin/x64/factorio}"
READ_DATA="$(cd "$(dirname "$FACTORIO")/../../data" && pwd)"
WORKDIR="${WORKDIR:-$(mktemp -d)}"
mkdir -p "$WORKDIR/mods" "$WORKDIR/write"
cat > "$WORKDIR/config.ini" <<CFG
[path]
read-data=$READ_DATA
write-data=$WORKDIR/write
CFG
mods='{"name":"base","enabled":true},{"name":"Bezierio","enabled":true},{"name":"bezierio-test","enabled":true},{"name":"bezierio-migration-fixture","enabled":true}'
for m in elevated-rails quality space-age; do mods+=",{\"name\":\"$m\",\"enabled\":false}"; done
echo "{\"mods\":[$mods]}" > "$WORKDIR/mods/mod-list.json"
ln -sfn "$REPO/tests/bezierio-test" "$WORKDIR/mods/bezierio-test"
ln -sfn "$REPO/tests/bezierio-migration-fixture" "$WORKDIR/mods/bezierio-migration-fixture"

# 1. the mod without its migrations
rm -rf "$WORKDIR/mods/Bezierio"
mkdir -p "$WORKDIR/mods/Bezierio"
(cd "$REPO" && tar cf - --exclude=./tests --exclude=./migrations --exclude=./.git .) | (cd "$WORKDIR/mods/Bezierio" && tar xf -)
"$FACTORIO" -c "$WORKDIR/config.ini" --mod-directory "$WORKDIR/mods" --create "$WORKDIR/old.zip" > "$WORKDIR/create.log" 2>&1
grep -E "MIGRATION|Error|error" "$WORKDIR/create.log" || true

# 2. the real mod
rm -rf "$WORKDIR/mods/Bezierio"
ln -sfn "$REPO" "$WORKDIR/mods/Bezierio"
set +e
"$FACTORIO" -c "$WORKDIR/config.ini" --mod-directory "$WORKDIR/mods" \
  --benchmark "$WORKDIR/old.zip" --benchmark-ticks 10 --benchmark-runs 1 > "$WORKDIR/load.log" 2>&1
set -e
grep -E "MIGRATION|Error|error" "$WORKDIR/load.log" || true
echo "(logs: $WORKDIR/create.log, $WORKDIR/load.log)"
grep -q "MIGRATION PASS" "$WORKDIR/load.log"
