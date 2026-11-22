---@diagnostic disable: undefined-global
-- Presets (scripts/presets.lua): list operations and the export data round trip.
--   lua5.4 tests/unit/presets.lua
local helpers = dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")
local presets = require("scripts.presets")
local registry = require("scripts.layers.registry")

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

local function wall(idx) return { idx = idx, type = "wall", name = "stone-wall", placed_by = "stone-wall", quality = "normal", size = 1, offset = 0, checkerboard = 0, radius = 1 } end
local function pole(idx) return { idx = idx, type = "electric-pole", name = "small-electric-pole", placed_by = "small-electric-pole", quality = "rare", size = 1, offset = 0, wire_distance = 7, reach = 2, spacing = 6, connect_with_circuit_wires = false } end

--- What the GUI picker makes for an item (registry.new_layer without prototypes).
local KNOWN = { ["stone-wall"] = wall, ["small-electric-pole"] = pole }
local function make_layer(idx, item, quality)
    local maker = KNOWN[item]
    if not maker then return nil end
    local layer = maker(idx)
    layer.quality = quality
    return layer
end

local function controller()
    return { ui = { preset_index = 1 }, presets = { { name = "Default", layers = { [0] = wall(0) } } } }
end

-- duplicate / rename / select / delete
local c = controller()
check(presets.duplicate(c) and #c.presets == 2 and c.ui.preset_index == 2 and c.presets[2].name == "Default 2", "copy selected, named uniquely")
c.presets[2].layers[0].radius = 5
check(c.presets[1].layers[0].radius == 1, "copy is independent")
check(presets.rename(c, "  Walls\n ") and c.presets[2].name == "Walls", "rename trims")
check(not presets.rename(c, "   ") and c.presets[2].name == "Walls", "empty name refused")
check(presets.rename(c, string.rep("x", 100)) and #c.presets[2].name == presets.MAX_NAME, "long name cut")
check(presets.select(c, 1) and c.ui.preset_index == 1 and not presets.select(c, 7), "select")
check(presets.delete(c) and #c.presets == 1 and c.ui.preset_index == 1, "delete the first, the next becomes selected")
check(not presets.delete(c), "the last preset stays")
c = controller()
for _ = 1, presets.MAX_PRESETS + 3 do presets.duplicate(c) end
check(#c.presets == presets.MAX_PRESETS, "list capped")

-- export data round trip
local preset = { name = "Defence", layers = { [0] = wall(0), [1] = pole(1), [-1] = registry.new_empty(-1) } }
preset.layers[0].radius, preset.layers[0].checkerboard = 3, -2
preset.layers[1].spacing, preset.layers[1].offset, preset.layers[1].connect_with_circuit_wires = 5, 2, true
preset.layers[-1].offset = 1
local data = presets.to_data(preset)
check(data.format == "bezierio-preset" and data.version == 1 and #data.layers == 3 and data.layers[1].idx == -1, "export data")
check(data.layers[3].wire_distance == nil and data.layers[3].size == nil, "derived values not exported")
local back, missing = presets.from_data(helpers.deepcopy(data), make_layer)
check(back and #missing == 0, "imported")
check(helpers.canonical_table(back.layers) == helpers.canonical_table(preset.layers), "round trip keeps every layer")
check(back.name == "Defence", "name kept")

-- JSON gives floats and may drop or garble things
local float = helpers.deepcopy(data)
for _, entry in ipairs(float.layers) do entry.idx = entry.idx + 0.0; entry.offset = (entry.offset or 0) + 0.0 end
back = presets.from_data(float, make_layer)
check(back and back.layers[1] and back.layers[1].offset == 2 and math.type(back.layers[1].offset) == "integer", "float numbers accepted")

local odd = { format = "bezierio-preset", version = 1, name = 5, layers = {
    { idx = 0, item = "stone-wall", quality = "normal", radius = 99, checkerboard = "x" },
    { idx = 3, item = "gone-wall" },
    { idx = 0, item = "small-electric-pole" },    -- duplicate idx: ignored
    { idx = 1.5 }, { idx = 900 }, "junk",
} }
back, missing = presets.from_data(odd, make_layer)
check(back.layers[0].type == "wall" and back.layers[0].radius == 10 and back.layers[0].checkerboard == 0, "values clamped, wrong types ignored")
check(#missing == 1 and missing[1] == "gone-wall" and back.layers[3].type == "empty", "missing item -> empty layer, reported")
check(back.layers[1] and back.layers[2] and back.layers[1].type == "empty", "gaps filled with empty layers")
check(back.layers[900] == nil, "far layers dropped")
check(back.name == "Imported", "bad name replaced")

back = presets.from_data({ format = "bezierio-preset", version = 1, layers = { { idx = 2, item = "stone-wall" } } }, make_layer)
check(back.layers[0] and back.layers[0].type == "empty", "layer 0 always exists")

local _, err = presets.from_data({ hello = 1 }, make_layer)
check(err == "not-a-preset", "not a preset")
_, err = presets.from_data({ format = "bezierio-preset", version = 2, layers = {} }, make_layer)
check(err == "unknown-version", "newer version refused")
_, err = presets.from_data(nil, make_layer)
check(err == "not-a-preset", "nothing decoded")

print(string.format("%d/%d preset checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
