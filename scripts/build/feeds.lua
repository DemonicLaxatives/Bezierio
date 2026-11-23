--- Feeding turrets from lines planned by other layers:
---   ammo turrets: an inserter beside the turret, picking up from a belt line and
---     dropping into the turret (the inserter prototype's own pickup and drop
---     positions decide where the belt has to be);
---   fluid turrets: a short pipe stub from one of the turret's fluid connections to
---     a pipe line, never touching another pipe line.
--- Runs when a turret is placed (planner commit), after belts and pipes are
--- planned. Plain functions on planner data.
local lib = {}

--- Longest pipe stub, in cells.
lib.MAX_STUB = 4

local SIDES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

--- Rotate a vector by a direction (0, 4, 8, 12: quarter turns clockwise; map y down).
--- @param v {x: number, y: number}
--- @param direction integer
--- @return {x: number, y: number}
function lib.rotate(v, direction)
    local x, y = v.x or v[1], v.y or v[2]
    for _ = 1, math.floor(direction / 4) % 4 do x, y = -y, x end
    return { x = x, y = y }
end

local function key(x, y) return x .. "," .. y end

--- An inserter for an ammo turret: a free cell beside the turret where the
--- inserter drops into the turret and picks up from a belt cell.
--- @param ctx {occupied: fun(x: integer, y: integer): boolean, belt: fun(x: integer, y: integer): boolean}
--- @param entity PlannedEntity  # the turret
--- @param inserter {pickup: Vector, drop: Vector}  # facing north
--- @return {x: integer, y: integer, direction: integer}|nil
function lib.inserter_spot(ctx, entity, inserter)
    local size = entity.size
    local x0 = math.floor(entity.position.x - size / 2 + 0.5)
    local y0 = math.floor(entity.position.y - size / 2 + 0.5)
    local function inside(px, py)
        return px >= x0 and px < x0 + size and py >= y0 and py < y0 + size
    end
    -- Cells around the footprint, in a fixed order.
    local ring = {}
    for i = 0, size - 1 do
        ring[#ring + 1] = { x0 + i, y0 - 1 }
        ring[#ring + 1] = { x0 + size, y0 + i }
        ring[#ring + 1] = { x0 + size - 1 - i, y0 + size }
        ring[#ring + 1] = { x0 - 1, y0 + size - 1 - i }
    end
    for _, c in ipairs(ring) do
        local cx, cy = c[1], c[2]
        if not ctx.occupied(cx, cy) then
            for _, direction in ipairs({ 0, 4, 8, 12 }) do
                local drop = lib.rotate(inserter.drop, direction)
                local pickup = lib.rotate(inserter.pickup, direction)
                local dx, dy = math.floor(cx + 0.5 + drop.x), math.floor(cy + 0.5 + drop.y)
                local px, py = math.floor(cx + 0.5 + pickup.x), math.floor(cy + 0.5 + pickup.y)
                if inside(dx, dy) and ctx.belt(px, py) then
                    return { x = cx, y = cy, direction = direction }
                end
            end
        end
    end
    return nil
end

local UNIT = { [0] = { x = 0, y = -1 }, [4] = { x = 1, y = 0 }, [8] = { x = 0, y = 1 }, [12] = { x = -1, y = 0 } }

--- The cells a fluid turret's connections want a pipe in.
---
--- Facing straight, the north connections are rotated. Facing diagonally (seen in
--- the game for the flamethrower: facing north-east, its connections are at
--- (-1, 0) pointing west and (0, 1) pointing south), each north connection is
--- turned 45 degrees and rounded to the grid, and points along whichever of the two
--- straight directions beside its turned direction leads out of the turret's square.
--- @param entity PlannedEntity
--- @param ports {x: number, y: number, direction: integer}[]  # facing north, relative to the centre
--- @return {x: integer, y: integer}[]
function lib.fluid_targets(entity, ports)
    local out = {}
    local facing = entity.direction or 0
    local half = entity.size / 2
    for _, port in ipairs(ports) do
        local px, py, d
        if facing % 4 == 0 then
            local p = lib.rotate(port, facing)
            px, py = p.x, p.y
            d = UNIT[(port.direction + facing) % 16]
        else
            local a = facing / 16 * 2 * math.pi
            local c, s = math.cos(a), math.sin(a)
            local x, y = port.x * c - port.y * s, port.x * s + port.y * c
            -- onto the grid of cell centres (whole numbers for an odd size)
            local offset = (entity.size % 2 == 0) and 0.5 or 0
            px, py = math.floor(x - offset + 0.5) + offset, math.floor(y - offset + 0.5) + offset
            local turned = (port.direction + facing) % 16
            -- the straight directions on either side of the turned (diagonal) one
            for _, option in ipairs({ (turned + 14) % 16, (turned + 2) % 16 }) do
                local u = UNIT[option]
                if u and not d and (math.abs(px + u.x) > half or math.abs(py + u.y) > half) then d = u end
            end
            d = d or UNIT[(turned + 14) % 16]
        end
        out[#out + 1] = { x = math.floor(entity.position.x + px + d.x), y = math.floor(entity.position.y + py + d.y) }
    end
    return out
end

--- A pipe stub from one of the targets to a pipe line: a path of free cells (the
--- target included, unless it is already pipe) whose last cell touches the line,
--- and none touching another pipe line.
--- @param ctx {occupied: fun(x: integer, y: integer): boolean, pipe_line: fun(x: integer, y: integer): string|nil}
--- @param targets {x: integer, y: integer}[]
--- @return {x: integer, y: integer}[]|nil  # cells to put pipe in (empty: already connected)
function lib.pipe_stub(ctx, targets)
    for _, t in ipairs(targets) do
        if ctx.pipe_line(t.x, t.y) then return {} end
    end
    for _, t in ipairs(targets) do
        if not ctx.occupied(t.x, t.y) then
            -- Breadth first from the target through free cells.
            --- The pipe line a cell touches, and how many different ones.
            local function lines_touching(x, y)
                local found, count = nil, 0
                for _, side in ipairs(SIDES) do
                    local line = ctx.pipe_line(x + side[1], y + side[2])
                    if line and line ~= found then
                        found = line
                        count = count + 1
                    end
                end
                return found, count
            end
            local queue, parent, seen = { { x = t.x, y = t.y, n = 1 } }, {}, { [key(t.x, t.y)] = true }
            local head = 1
            while queue[head] do
                local c = queue[head]
                head = head + 1
                local line, count = lines_touching(c.x, c.y)
                if count > 1 then
                    -- touches two lines: not here
                elseif line then
                    local path = {}
                    local cur = c
                    while cur do
                        table.insert(path, 1, { x = cur.x, y = cur.y })
                        cur = parent[key(cur.x, cur.y)]
                    end
                    return path
                elseif c.n < lib.MAX_STUB then
                    for _, s in ipairs(SIDES) do
                        local nx, ny = c.x + s[1], c.y + s[2]
                        local k = key(nx, ny)
                        if not seen[k] and not ctx.occupied(nx, ny) then
                            seen[k] = true
                            parent[k] = c
                            queue[#queue + 1] = { x = nx, y = ny, n = c.n + 1 }
                        end
                    end
                end
            end
        end
    end
    return nil
end

return lib
