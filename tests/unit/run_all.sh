#!/usr/bin/env bash
# Run every unit test (no game needed). Usage: tests/unit/run_all.sh [lua interpreter]
set -euo pipefail
LUA="${1:-lua5.4}"
DIR="$(cd "$(dirname "$0")" && pwd)"
status=0
for t in plan_snapshot planner_jobs migrations curve_edit layers layer_types paths feeds rails presets shapes plan_properties; do
  printf '%-18s ' "$t"
  "$LUA" "$DIR/$t.lua" | tail -1 || status=1
done
exit $status
