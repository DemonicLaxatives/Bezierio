--- Path layers (belts, pipes): turning a line's cells into a continuous chain of
--- entities.
---
--- Each line of a path layer is a one-cell-wide sub-band of the layer's band. Such a
--- band rasterizes into a 4-connected staircase (see geometry.lua), so the line's
--- cells are already continuous and never overlap other layers. The rasterizer
--- collects them with the curve sample each belongs to (`j`); here they are
--- ordered along the curve by walking from neighbour to neighbour (single-cell
--- spurs at bends and doubled-back cells are left out), and turned into entities:
--- belts pointing at the next cell, undergrounds on long straight runs, pumps.
--- Plain functions on data.
local lib = {}

--- Directions as defines.direction values.
lib.NORTH, lib.EAST, lib.SOUTH, lib.WEST = 0, 4, 8, 12

--- Neighbours further apart along the curve than this (in samples, 0.25 tiles
--- each) normally belong to another stretch of a curve that comes back near itself.
lib.MAX_JUMP = 12

--- ... but on the inside of a tight bend, neighbouring cells see the whole bend:
--- when a line would otherwise end, it may go on forward to a neighbour up to this
--- far along the curve.
lib.MAX_JUMP_INSIDE = 200

--- @class PathCell
--- @field x integer
--- @field y integer
--- @field j integer   # curve sample the cell belongs to

local STEPS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local DIAGONALS = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function key(x, y) return x .. "," .. y end

--- Direction from cell a to the 4-adjacent cell b.
--- @param a PathCell
--- @param b PathCell
--- @return integer
function lib.direction(a, b)
    if b.x > a.x then return lib.EAST end
    if b.x < a.x then return lib.WEST end
    if b.y > a.y then return lib.SOUTH end
    return lib.NORTH
end

--- The line's cells in order along the curve, as continuous segments (a curve that
--- runs into another layer's cells or back near itself can split a line).
--- @param cells PathCell[]
--- @param loop_samples integer|nil  # closed curve: sample count, so that distances
---   along the curve are measured around the loop (the seam joins its two ends)
--- @return PathCell[][]
function lib.segments(cells, loop_samples)
    --- Signed distance along the curve from a to b, in samples.
    local function along(a, b)
        local d = b.j - a.j
        if loop_samples then
            local half = loop_samples / 2
            if d > half then d = d - loop_samples elseif d < -half then d = d + loop_samples end
        end
        return d
    end
    local by_key, order = {}, {}
    for _, c in ipairs(cells) do
        local k = key(c.x, c.y)
        if not by_key[k] then
            by_key[k] = c
            order[#order + 1] = c
        end
    end
    table.sort(order, function(a, b)
        if a.j ~= b.j then return a.j < b.j end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local visited = {}
    --- Unvisited neighbours of c close along the curve (or, with `ahead`, further
    --- on along the curve within MAX_JUMP_INSIDE).
    local function open_neighbours(c, except, steps, ahead)
        local out = {}
        for _, d in ipairs(steps or STEPS) do
            local n = by_key[key(c.x + d[1], c.y + d[2])]
            if n and n ~= except and not visited[n] then
                local gap = along(c, n)
                if math.abs(gap) <= lib.MAX_JUMP or (ahead and gap > 0 and gap <= lib.MAX_JUMP_INSIDE) then
                    out[#out + 1] = n
                end
            end
        end
        return out
    end
    local segments = {}
    for _, start in ipairs(order) do
        if not visited[start] then
            local segment, cur = {}, start
            while cur do
                visited[cur] = true
                segment[#segment + 1] = cur
                local options = open_neighbours(cur)
                if #options == 0 then options = open_neighbours(cur, nil, nil, true) end
                if #options == 0 then
                    -- A one-cell line off to the side of a bend can step diagonally;
                    -- lib.join_corners fills in a corner cell.
                    options = open_neighbours(cur, nil, DIAGONALS)
                end
                local best, best_score
                for _, n in ipairs(options) do
                    -- Prefer going on along the curve, and not into a dead end (a
                    -- spur at a bend) when there is a way that continues.
                    local dead_end = #open_neighbours(n, cur) == 0
                    local d = along(cur, n)
                    local score = (dead_end and 1000 or 0) + (d < 0 and 100 or 0) + math.abs(d)
                    if not best_score or score < best_score then best, best_score = n, score end
                end
                cur = best
            end
            segments[#segments + 1] = segment
        end
    end
    return segments
end

--- Fill in a corner cell wherever a segment steps diagonally, or split it there
--- when neither corner is free.
--- @param segment PathCell[]
--- @param usable fun(x: integer, y: integer): integer|false  # whether a corner cell may be used: 1 free, 2 taken from another line (only if no free one)
--- @param use fun(x: integer, y: integer, j: integer)  # it is used now (j: its sample along the curve)
--- @return PathCell[][]
function lib.join_corners(segment, usable, use)
    local out, current = {}, {}
    for i, c in ipairs(segment) do
        local prev = current[#current]
        if prev and math.abs(c.x - prev.x) + math.abs(c.y - prev.y) == 2 then
            local best, best_rank
            for _, corner in ipairs({ { x = c.x, y = prev.y }, { x = prev.x, y = c.y } }) do
                local rank = usable(corner.x, corner.y)
                if rank and (not best_rank or rank < best_rank) then best, best_rank = corner, rank end
            end
            local joined = best ~= nil
            if best then
                use(best.x, best.y, prev.j)
                current[#current + 1] = { x = best.x, y = best.y, j = prev.j }
            end
            if not joined then
                out[#out + 1] = current
                current = {}
            end
        end
        current[#current + 1] = c
    end
    if #current > 0 then out[#out + 1] = current end
    return out
end

--- @class PathPiece
--- @field kind "line"|"underground_in"|"underground_out"|"pump"
--- @field x number          # entity position
--- @field y number
--- @field direction integer
--- @field w integer|nil      # footprint (pump: 2 x 1 or 1 x 2)
--- @field h integer|nil

--- Entities for one segment (cells in flow order).
--- @param segment PathCell[]
--- @param opts {undergrounds: integer|nil, pipes: boolean, pump_spacing: integer|nil, loop: boolean, taken: (fun(x: integer, y: integer): boolean)|nil}
---   undergrounds: max distance between entrance and exit (nil: none)
---   loop: the last cell feeds the first (closed curve, adjacent ends)
---   taken: cells of other belts, which the last belt must not point into (it would
---          feed them from the side)
--- @return PathPiece[] pieces, integer pumps_missing
function lib.pieces(segment, opts)
    local n = #segment
    -- A line end hemmed in by other belts would feed one of them from the side:
    -- leave such end cells out.
    local trimmed = {}
    if opts.taken and not opts.loop then
        local function way_out(i)
            local last, before = segment[i], segment[i - 1]
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local tx, ty = last.x + d[1], last.y + d[2]
                if not (tx == before.x and ty == before.y) and (trimmed[key(tx, ty)] or not opts.taken(tx, ty)) then return true end
            end
            return false
        end
        while n >= 2 and not way_out(n) do
            trimmed[key(segment[n].x, segment[n].y)] = true
            n = n - 1
        end
        if n < #segment then
            local kept = {}
            for i = 1, n do kept[i] = segment[i] end
            segment = kept
        end
        if n < 2 then return {}, 0 end
    end
    local moves = {}
    for i = 1, n - 1 do moves[i] = lib.direction(segment[i], segment[i + 1]) end
    if n >= 2 then
        if opts.loop then
            moves[n] = lib.direction(segment[n], segment[1])
        else
            -- Straight on, or turn away from other belts.
            local last, before = segment[n], segment[n - 1]
            moves[n] = moves[n - 1]
            if opts.taken then
                local straight = moves[n - 1]
                for _, d in ipairs({ straight, (straight + 4) % 16, (straight + 12) % 16 }) do
                    local step = d == lib.EAST and { 1, 0 } or d == lib.WEST and { -1, 0 } or d == lib.SOUTH and { 0, 1 } or { 0, -1 }
                    local tx, ty = last.x + step[1], last.y + step[2]
                    if not (tx == before.x and ty == before.y) and (trimmed[key(tx, ty)] or not opts.taken(tx, ty)) then
                        moves[n] = d
                        break
                    end
                end
            end
        end
    elseif n == 1 then
        moves[1] = lib.NORTH
    end

    -- What each cell becomes; nil = left empty (between underground ends).
    local kind = {}
    for i = 1, n do kind[i] = "line" end

    -- Pumps (pipes): every `pump_spacing` cells, on the next straight stretch where
    -- the pump (2 cells) has pipe in line on both sides.
    local pump_at, missing = {}, 0
    if opts.pump_spacing then
        local since = 0
        local i = 1
        while i <= n do
            since = since + 1
            if since >= opts.pump_spacing then
                local placed = false
                local p = i
                while p + 2 <= n and not placed do
                    local d = moves[p]
                    if p >= 2 and moves[p - 1] == d and moves[p + 1] == d then
                        pump_at[p] = d
                        placed = true
                        since = 0
                        i = p + 1
                    else
                        p = p + 1
                    end
                end
                if not placed then
                    missing = missing + 1
                    since = 0
                end
            end
            i = i + 1
        end
    end

    -- Undergrounds on straight runs: cells a..b moving in d, entrance fed from
    -- behind (the cell before it moves in d too) and exit feeding forward.
    local pairs_out = {}
    if opts.undergrounds and opts.undergrounds >= 2 then
        local i = 1
        while i <= n - 1 do
            local d = moves[i]
            local k = i
            while k + 1 <= n - 1 and moves[k + 1] == d do k = k + 1 end
            -- cells i..k+1 lie on a straight line in d; entrance from i+1, exit up to k
            local a = i + 1
            while a + 2 <= k do
                local b = math.min(a + opts.undergrounds, k)
                local blocked = false
                for c = a, b do if pump_at[c] or pump_at[c - 1] then blocked = true end end
                if blocked or b - a < 2 then break end
                table.insert(pairs_out, { a, b, d })
                a = b + 1
            end
            i = k + 1
        end
    end
    for _, pair in ipairs(pairs_out) do
        local a, b = pair[1], pair[2]
        kind[a], kind[b] = "underground_in", "underground_out"
        for c = a + 1, b - 1 do kind[c] = nil end
    end

    local pieces = {}
    local i = 1
    while i <= n do
        local c = segment[i]
        if pump_at[i] then
            local d = pump_at[i]
            local nxt = segment[i + 1]
            local horizontal = d == lib.EAST or d == lib.WEST
            pieces[#pieces + 1] = {
                kind = "pump", x = (c.x + nxt.x) / 2 + 0.5, y = (c.y + nxt.y) / 2 + 0.5, direction = d,
                w = horizontal and 2 or 1, h = horizontal and 1 or 2,
            }
            i = i + 2
        else
            if kind[i] then
                local d = moves[i]
                if kind[i] == "underground_in" and opts.pipes then
                    -- A pipe-to-ground points to its pipe connection: back, for an entrance.
                    d = (d + 8) % 16
                end
                pieces[#pieces + 1] = { kind = kind[i], x = c.x + 0.5, y = c.y + 0.5, direction = d }
            end
            i = i + 1
        end
    end
    return pieces, missing
end

return lib
