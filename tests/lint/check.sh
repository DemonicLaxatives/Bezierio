#!/usr/bin/env bash
# Type-check the mod with the Lua language server and the Factorio API stubs, as
# the editor does: API misuse and type errors fail.
# Usage: tests/lint/check.sh
#   LUALS=/path/to/lua-language-server   (default: lua-language-server on PATH)
#   LUALS_LIBRARY=/dir/with/factorio      (the stubs: fmtk luals-addon, see tests/lint/README)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LUALS="${LUALS:-lua-language-server}"
LIB="${LUALS_LIBRARY:?set LUALS_LIBRARY to the folder fmtk luals-addon wrote (it holds factorio/)}"
OUT="$(mktemp -d)"
cat > "$OUT/luarc.json" <<CFG
{
  "runtime.version": "Lua 5.2",
  "runtime.path": ["?.lua"],
  "runtime.builtin": { "io": "disable", "os": "disable", "coroutine": "disable" },
  "runtime.plugin": "$LIB/factorio/plugin.lua",
  "workspace.library": ["$LIB/factorio/library"],
  "workspace.checkThirdParty": false,
  "workspace.ignoreDir": [".git", "tests/unit", "release", "builtin-presets", "mod-portal", "docs", ".vscode"],
  "diagnostics.globals": ["__DebugAdapter", "__Profiler"],
  "diagnostics.disable": ["lowercase-global", "need-check-nil"]
}
CFG
"$LUALS" --check "$REPO" --configpath "$OUT/luarc.json" --checklevel=Warning --logpath "$OUT" \
  --check_format=json --check_out_path="$OUT/check.json" > "$OUT/stdout.txt" 2>&1 || true
python3 - "$OUT" "$REPO" <<'PY'
import json, os, sys
out, repo = sys.argv[1], sys.argv[2]
path = os.path.join(out, "check.json")
problems = json.load(open(path)) if os.path.exists(path) else {}
# The stubs' LocalisedString is a variadic tuple ([string, LocalisedString...])
# that also allows any Lua object, which the language server can't match table
# literals against: every { "key", value } localised string would be flagged, and
# a nested one gets taken for a LuaGuiElement. Known noise, skipped.
def known_noise(d):
    m, code = d["message"], d.get("code")
    if code == "assign-type-mismatch":
        return "to `LocalisedString" in m or "to `LuaGuiElement|LuaItemStack`" in m or "to `LuaGuiElement`" in m
    return code == "missing-fields" and "in type `LuaGuiElement`" in m

count = 0
for uri, diags in sorted(problems.items()):
    file = uri.replace("file://", "").replace(repo + "/", "")
    for d in diags:
        if known_noise(d):
            continue
        count += 1
        line = d["range"]["start"]["line"] + 1
        print(f"{file}:{line}: [{d.get('code')}] {d['message'].splitlines()[0]}")
print(f"{count} problems")
sys.exit(1 if count else 0)
PY
