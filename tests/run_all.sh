#!/usr/bin/env bash
# Every test: unit tests, the game scenarios (build also with the DLC mods), and
# the save migration test. Prints one line per test and a summary.
# Usage: tests/run_all.sh   (FACTORIO= as for run.sh)
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
failed=()

echo "== unit"
"$DIR/unit/run_all.sh" || failed+=("unit")

run() {
  local label="$1"; shift
  local out
  out="$("$@" 2>&1)"
  if [[ $? -eq 0 ]]; then
    echo "ok    $label: $(grep -oE "TEST PASS.*|SMOKE OK.*|MIGRATION PASS.*" <<<"$out" | tail -1)"
  else
    echo "FAIL  $label"
    grep -E "FAIL|Error" <<<"$out" | tail -5 | sed 's/^/      /'
    failed+=("$label")
  fi
}

echo "== game"
for s in smoke points layers build types paths feeds; do run "$s" "$DIR/run.sh" "$s"; done
run "build (space-age, quality, elevated-rails)" "$DIR/run.sh" build space-age quality elevated-rails
run "types (space-age, quality, elevated-rails)" "$DIR/run.sh" types space-age quality elevated-rails
run "migrate-save" "$DIR/migrate-save.sh"

if [[ ${#failed[@]} -eq 0 ]]; then
  echo "all passed"
else
  echo "failed: ${failed[*]}"
  exit 1
fi
