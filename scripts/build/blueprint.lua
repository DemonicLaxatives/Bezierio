--- Turns a finished plan into a blueprint in the player's cursor, as a resumable
--- job: the blueprint data is collected a budgeted amount per tick, and the last
--- step writes it into the cursor.
---
--- With a source, the blueprint carries the curve and preset it was made from:
--- tags on its first entity (a description holds at most 500 characters), and a
--- note in the description; the Load button reads them back (gui/control.lua).
---
--- The blueprint uses absolute snapping with a grid the size of the build, offset
--- so that it snaps exactly onto where the plan was previewed (and stamps further
--- copies end to end).
local wires = require("scripts.build.wires")

local lib = {}

--- The description of a blueprint that carries its curve and preset.
lib.NOTE =
"Made with Bézierio. To get its curve and preset back, hold this blueprint and click Load from generated blueprint in the Bézierio window."

--- Work units per item, for budgeting.
lib.COST = { entity = 1, tile = 1, wire = 1, write = 0.5 }

--- @class BlueprintSource
--- @field curve string    # curve export string
--- @field preset string   # preset export string

--- @class BlueprintJob: WireWalk
--- @field kind "blueprint"
--- @field player_index integer
--- @field plan BuildPlan
--- @field label string
--- @field source BlueprintSource|nil
--- @field stage "bounds"|"entities"|"tiles"|"wires"|"write"|"done"
--- @field cursor integer
--- @field min_x number|nil                    # bounds: the plan's extent
--- @field min_y number|nil
--- @field max_x number|nil
--- @field max_y number|nil
--- @field origin {x: integer, y: integer}|nil   # world position of blueprint (0, 0)
--- @field size {x: integer, y: integer}|nil
--- @field entities BlueprintEntity[]
--- @field tiles Tile[]
--- @field result {entities: integer, tiles: integer}|nil
--- @field error string|nil                     # locale key suffix, when it couldn't be written

--- @param player LuaPlayer
--- @param plan BuildPlan  # must be done
--- @param label string
--- @param source BlueprintSource|nil
--- @return BlueprintJob
function lib.new_job(player, plan, label, source)
    local chain_keys = wires.chain_keys(plan)
    return {
        kind = "blueprint",
        player_index = player.index,
        plan = plan,
        label = label,
        source = source,
        stage = "bounds",
        cursor = 1,
        chain_keys = chain_keys,
        chain_cursor = 1,
        entities = {},
        tiles = {},
        min_x = math.huge,
        min_y = math.huge,
        max_x = -math.huge,
        max_y = -math.huge,
    }
end

--- @param job BlueprintJob
--- @return number
function lib.progress(job)
    local plan = job.plan
    local total = 2 * (#plan.entities + #plan.tiles)
    if total == 0 then return 1 end
    local done = 0
    if job.stage == "bounds" then
        done = job.cursor - 1
    elseif job.stage == "entities" then
        done = #plan.entities + #plan.tiles + job.cursor - 1
    elseif job.stage == "tiles" then
        done = 2 * #plan.entities + #plan.tiles + job.cursor - 1
    else
        done = total
    end
    return math.min(1, done / total)
end

--- @param job BlueprintJob
local function grow(job, x1, y1, x2, y2)
    if x1 < job.min_x then job.min_x = x1 end
    if y1 < job.min_y then job.min_y = y1 end
    if x2 > job.max_x then job.max_x = x2 end
    if y2 > job.max_y then job.max_y = y2 end
end

--- The bounding box of everything planned (entities, then tiles, one item each).
--- @param job BlueprintJob
--- @param budget number
--- @return number used
local function step_bounds(job, budget)
    local plan, used = job.plan, 0
    local n_entities = #plan.entities
    local total = n_entities + #plan.tiles
    while job.cursor <= total and used < budget do
        local i = job.cursor
        if i <= n_entities then
            local e = plan.entities[i]
            local half = e.size / 2
            grow(job, e.position.x - half, e.position.y - half, e.position.x + half, e.position.y + half)
        else
            local t = plan.tiles[i - n_entities]
            grow(job, t.x, t.y, t.x + 1, t.y + 1)
        end
        job.cursor = i + 1
        used = used + lib.COST.entity
    end
    if job.cursor > total then
        local ox, oy = math.floor(job.min_x), math.floor(job.min_y)
        job.origin = { x = ox, y = oy }
        job.size = { x = math.max(1, math.ceil(job.max_x) - ox), y = math.max(1, math.ceil(job.max_y) - oy) }
        job.stage, job.cursor = "entities", 1
    end
    return used
end

--- @param job BlueprintJob
--- @param budget number
--- @return number used
local function step_entities(job, budget)
    local plan, used, origin = job.plan, 0, job.origin
    while job.cursor <= #plan.entities and used < budget do
        local i = job.cursor
        local e = plan.entities[i]
        local entry = {
            entity_number = i,
            name = e.name,
            position = { x = e.position.x - origin.x, y = e.position.y - origin.y },
            quality = (e.quality and e.quality ~= "normal") and e.quality or nil,
            direction = (e.direction and e.direction ~= 0) and e.direction or nil,
            color = e.color,
            type = e.belt_type,
            rail_layer = e.rail_layer,
            -- the curve and preset, for loading them back
            tags = (i == 1 and job.source) and { bezierio = { curve = job.source.curve, preset = job.source.preset } } or
                nil,
        }
        if e.priority_targets then
            local list = {}
            for k, name in ipairs(e.priority_targets) do list[k] = { index = k, name = name } end
            entry["priority-list"] = list
            entry["ignore-unprioritised"] = e.ignore_unprioritised == true or nil
        end
        if e.ammo then
            entry.items = { {
                id = { name = e.ammo.name, quality = e.ammo.quality },
                items = { in_inventory = { { inventory = defines.inventory[e.ammo.inventory], stack = 0, count = e.ammo.count } } },
            } }
        end
        job.entities[i] = entry
        job.cursor = i + 1
        used = used + lib.COST.entity
    end
    if job.cursor > #plan.entities then job.stage, job.cursor = "tiles", 1 end
    return used
end

--- @param job BlueprintJob
--- @param budget number
--- @return number used
local function step_tiles(job, budget)
    local plan, used, origin = job.plan, 0, job.origin
    while job.cursor <= #plan.tiles and used < budget do
        local t = plan.tiles[job.cursor]
        job.tiles[job.cursor] = { name = t.name, position = { x = t.x - origin.x, y = t.y - origin.y } }
        job.cursor = job.cursor + 1
        used = used + lib.COST.tile
    end
    if job.cursor > #plan.tiles then job.stage, job.cursor = "wires", 1 end
    return used
end

--- Pole chains: copper between consecutive poles, red and green too if asked.
--- @param job BlueprintJob
--- @param budget number
--- @return number used
local function step_wires(job, budget)
    local ids = defines.wire_connector_id
    local function add(a, b, id)
        local source = job.entities[a]
        source.wires = source.wires or {}
        table.insert(source.wires, { a, id, b, id })
    end
    local used, done = wires.step(job, job.plan, budget, lib.COST.wire,
        function(chain, a, b)
            add(a, b, ids.pole_copper)
            if chain.red then add(a, b, ids.circuit_red) end
            if chain.green then add(a, b, ids.circuit_green) end
        end,
        function(link)
            if link.red then add(link.a, link.b, ids.circuit_red) end
            if link.green then add(link.a, link.b, ids.circuit_green) end
        end)
    if done then job.stage = "write" end
    return used
end

--- Put the blueprint in the cursor. One engine call for the whole blueprint.
--- @param job BlueprintJob
--- @param player LuaPlayer
--- @return number used
local function write(job, player)
    job.stage = "done"
    job.result = { entities = #job.entities, tiles = #job.tiles }
    if #job.entities == 0 and #job.tiles == 0 then
        job.error = "blueprint-empty"
        return 0
    end
    if not player.clear_cursor() then
        job.error = "blueprint-cursor"
        return 0
    end
    local stack = player.cursor_stack
    if not (stack and stack.set_stack { name = "blueprint", count = 1 }) then
        job.error = "blueprint-cursor"
        return 0
    end
    stack.set_blueprint_entities(job.entities, false)
    stack.set_blueprint_tiles(job.tiles)
    stack.label = job.label
    if job.source and job.result.entities > 0 then stack.blueprint_description = lib.NOTE end
    stack.preview_icons = stack.default_icons
    local size, origin = job.size, job.origin
    stack.blueprint_snap_to_grid = { x = size.x, y = size.y }
    stack.blueprint_absolute_snapping = true
    stack.blueprint_position_relative_to_grid = { x = origin.x % size.x, y = origin.y % size.y }
    -- The data now lives in the item; don't keep a second copy in storage.
    job.entities, job.tiles = {}, {}
    return (job.result.entities + job.result.tiles) * lib.COST.write
end

--- Do up to about `budget` units of work.
--- @param job BlueprintJob
--- @param budget number
--- @return boolean done, number used
function lib.step(job, budget)
    local player = game.get_player(job.player_index)
    if not (player and player.valid) then
        job.stage = "done"
        return true, 0
    end
    local used = 0
    if job.stage == "bounds" then used = used + step_bounds(job, budget) end
    if job.stage == "entities" and used < budget then used = used + step_entities(job, budget - used) end
    if job.stage == "tiles" and used < budget then used = used + step_tiles(job, budget - used) end
    if job.stage == "wires" and used < budget then used = used + step_wires(job, budget - used) end
    if job.stage == "write" and used < budget then used = used + write(job, player) end
    return job.stage == "done", used
end

return lib
