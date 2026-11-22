---@diagnostic disable: undefined-global
-- Layer settings (scripts/layers/registry.lua): what survives picking a new item.
--   lua5.4 tests/unit/layers.lua
dofile((arg[0]:match("^(.*)/tests/unit/") or ".") .. "/tests/unit/helpers.lua")
local registry = require("scripts.layers.registry")

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

-- What registry.new_layer makes (it needs prototypes, so build the defaults by hand).
local function wall(idx, quality)
    return { idx = idx, type = "wall", name = "stone-wall", placed_by = "stone-wall", quality = quality, size = 1, offset = 0, checkerboard = 0, radius = 1 }
end
local function tile(idx)
    return { idx = idx, type = "tile", name = "concrete", placed_by = "concrete", quality = "normal", size = 1, offset = 0, checkerboard = 0, radius = 1, under = false }
end
local function pole(idx, wire_distance)
    return { idx = idx, type = "electric-pole", name = "pole", placed_by = "pole", quality = "normal", size = 1, offset = 0,
        wire_distance = wire_distance, reach = 2, spacing = wire_distance - 1, red_wire = false, green_wire = false }
end

-- Same item, another quality: everything kept
local old = wall(2, "normal"); old.radius, old.checkerboard, old.offset = 4, -2, 3
local new = wall(2, "rare")
registry.carry_over(new, old)
check(new.radius == 4 and new.checkerboard == -2 and new.offset == 3, "quality change keeps width, checkerboard, offset")
check(new.quality == "rare" and new.name == "stone-wall", "the new item and quality stay")

-- Wall -> tile: shared fields kept, tile-only fields at their defaults
new = tile(2)
registry.carry_over(new, old)
check(new.radius == 4 and new.checkerboard == -2 and new.under == false and new.type == "tile", "wall -> tile keeps the band settings")

-- Tile -> tile keeps the under flag
local t = tile(-1); t.under, t.radius = true, 5
new = tile(-1)
registry.carry_over(new, t)
check(new.under == true and new.radius == 5, "tile -> tile keeps under")

-- Layer 0's width range differs from side layers' only in meaning; values clamp to the range
old = wall(1, "normal"); old.radius = 99
new = wall(1, "normal")
registry.carry_over(new, old)
check(new.radius == 10, "out-of-range values clamped: " .. new.radius)

-- Pole -> pole with a shorter reach: spacing clamped to the new wire distance; derived values not copied
local p = pole(1, 9); p.spacing, p.red_wire = 9, true
new = pole(1, 7)
registry.carry_over(new, p)
check(new.spacing == 7 and new.wire_distance == 7 and new.red_wire == true and new.green_wire == false, "pole spacing clamped, wires kept")

-- Wall -> pole: nothing in common but the offset
old = wall(1, "normal"); old.offset = 2
new = pole(1, 7)
registry.carry_over(new, old)
check(new.offset == 2 and new.spacing == 6 and new.radius == nil, "unrelated types share only the offset")

-- Clearing the item keeps the offset
new = registry.new_empty(1)
registry.carry_over(new, old)
check(new.offset == 2 and new.type == "empty", "cleared layer keeps the offset")

registry.carry_over(new, nil)
check(new.offset == 2, "no old layer: nothing changes")

print(string.format("%d/%d layer checks passed", checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
