--- What the planner's stages share: costs, the sample step, cell keys, extra
--- item counts and grid helpers.
local lib = {}

--- Max distance between curve samples, in tiles.
lib.SAMPLE_STEP = 0.25

--- Spacing of the extra probes past the ends of an open curve, in tiles.
lib.END_PROBE_STEP = 0.2

--- Work units per operation, for budgeting.
lib.COST = {
    sample = 1,  -- one curve sample
    frame = 1,   -- one pass over one sample (tangent / fill / normal + index)
    sweep = 1,   -- one probe across the curve
    cell = 10,   -- classifying one cell (nearest-sample search)
    place = 4,   -- trying one spaced entity position
}

--- @param x integer
--- @param y integer
function lib.cell_key(x, y)
    return x .. "," .. y
end

--- Item counts beyond the layer's own item (undergrounds, pumps), for the totals.
--- @param plan BuildPlan
--- @param idx integer
--- @param item string|nil
function lib.count_extra(plan, idx, item)
    if not item then return end
    plan.extra_counts[idx] = plan.extra_counts[idx] or {}
    plan.extra_counts[idx][item] = (plan.extra_counts[idx][item] or 0) + 1
end

--- @param x integer
--- @param y integer
--- @param checkerboard integer|nil
--- @return boolean
function lib.checkerboard_keep(x, y, checkerboard)
    if not checkerboard or checkerboard == 0 then return true end
    local size = math.abs(checkerboard)
    local parity = (math.floor(x / size) + math.floor(y / size)) % 2
    return (parity == 0) == (checkerboard > 0)
end

--- Two nearest grid-aligned centres for an entity of `size` along one axis.
function lib.snap_candidates(x, size)
    local a
    if size % 2 == 1 then
        a = math.floor(x) + 0.5
    else
        a = math.floor(x + 0.5)
    end
    local b = a + ((x >= a) and 1 or -1)
    return a, b
end

--- @param center Vector
--- @param size integer
--- @return integer, integer  # left-top cell
function lib.footprint_origin(center, size)
    return math.floor(center.x - size / 2 + 0.5), math.floor(center.y - size / 2 + 0.5)
end

return lib
