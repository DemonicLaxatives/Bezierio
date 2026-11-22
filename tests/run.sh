#!/usr/bin/env bash
# Run a Bézierio test scenario headless, isolated from your normal Factorio data.
# Usage: tests/run.sh [scenario] [extra mods...]
#   FACTORIO=/path/to/bin/x64/factorio  (default: ~/Games/factorio/bin/x64/factorio)
#   WORKDIR=/some/dir                   (default: a fresh mktemp dir)
set -euo pipefail
SCENARIO="${1:-smoke}"; shift || true
EXTRA_MODS=("$@")
REPO="$(cd "$(dirname "$0")/.." && pwd)"
FACTORIO="${FACTORIO:-$HOME/Games/factorio/bin/x64/factorio}"
READ_DATA="$(cd "$(dirname "$FACTORIO")/../../data" && pwd)"
WORKDIR="${WORKDIR:-$(mktemp -d)}"

mkdir -p "$WORKDIR/mods" "$WORKDIR/write"
ln -sfn "$REPO" "$WORKDIR/mods/Bezierio"
ln -sfn "$REPO/tests/bezierio-test" "$WORKDIR/mods/bezierio-test"

mods='{"name":"base","enabled":true},{"name":"Bezierio","enabled":true},{"name":"bezierio-test","enabled":true}'
for m in elevated-rails quality space-age; do
  enabled=false
  for e in "${EXTRA_MODS[@]}"; do [[ "$e" == "$m" ]] && enabled=true; done
  mods+=",{\"name\":\"$m\",\"enabled\":$enabled}"
done
echo "{\"mods\":[$mods]}" > "$WORKDIR/mods/mod-list.json"

cat > "$WORKDIR/config.ini" <<CFG
[path]
read-data=$READ_DATA
write-data=$WORKDIR/write
CFG

set +e
"$FACTORIO" -c "$WORKDIR/config.ini" --mod-directory "$WORKDIR/mods" \
  --test-scenario "bezierio-test/$SCENARIO" --test-ticks 3600 > "$WORKDIR/stdout.log" 2>&1
code=$?
set -e
grep -E "Error|error|TEST|SMOKE|FAIL|PASS|step ok|plan:" "$WORKDIR/stdout.log" | grep -v "Checksum" | tail -40
echo "exit code: $code   (full log: $WORKDIR/stdout.log)"
exit $code
