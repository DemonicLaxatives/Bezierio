--- All rendering: control points, the curve, and the build preview.
---
--- Drawing follows the planner job (see jobs.lua): curve segments are drawn as
--- samples appear and the preview fills in as placements are found, a budgeted
--- amount per tick.
local vect = require("scripts.vector_math")
local state = require("scripts.state")

local lib = {}

--- Don't flood the renderer when previewing huge builds.
lib.MAX_PREVIEW_OBJECTS = 4000

--- Curve segments are at least this long (samples are denser than needed for drawing).
lib.CURVE_SEGMENT = 0.5

--- Work units per render object, for budgeting.
lib.COST = { line = 2, rectangle = 2 }

local CURVE_COLOR = { r = 0.1, g = 0.3, b = 0.7, a = 1 }
local POINT_COLOR = { r = 0.5, g = 0, b = 0.2, a = 1 }
local HULL_COLOR = { r = 0.5, g = 0, b = 1, a = 1 }
local PREVIEW_ENTITY_COLOR = { r = 0.5, g = 0.5, b = 0, a = 0.25 }
local PREVIEW_TILE_COLOR = { r = 0, g = 0.35, b = 0.15, a = 0.2 }

--- @param player LuaPlayer
--- @param key "curve"|"control_points"|"preview"|nil  # nil clears everything
function lib.delete_sprites(player, key)
    local sprites = state.sprites(player.index)
    for cache_key, cache in pairs(sprites) do
        if key == nil or key == cache_key then
            for _, obj in pairs(cache) do
                if obj.valid then obj.destroy() end
            end
            sprites[cache_key] = {}
        end
    end
end

--- @param player LuaPlayer
local function base_params(player)
    return { surface = player.surface, players = { player.index }, visible = true }
end

--- Control point markers and the control polygon.
--- @param player LuaPlayer
--- @param curve Curve
local function draw_control_points(player, curve)
    local sprites = state.sprites(player.index).control_points

    local circle = base_params(player)
    circle.color = POINT_COLOR
    circle.radius = 0.5
    circle.width = 10
    circle.filled = false

    local label = base_params(player)
    label.color = { r = 1, g = 1, b = 1, a = 1 }
    label.scale = 3

    local defined = {}
    local indices = {}
    for idx in pairs(curve.points) do table.insert(indices, idx) end
    table.sort(indices)
    for _, idx in ipairs(indices) do
        local point = curve.points[idx]
        if point.x and point.y then
            table.insert(defined, point)
            circle.target = point
            table.insert(sprites, rendering.draw_circle(circle))
            label.target = point
            label.text = "P" .. idx
            table.insert(sprites, rendering.draw_text(label))
        end
    end

    local line = base_params(player)
    line.color = HULL_COLOR
    line.width = 2
    line.dash_length = 0.5
    line.gap_length = 0.25
    for i = 1, #defined - 1 do
        line.from = defined[i]
        line.to = defined[i + 1]
        table.insert(sprites, rendering.draw_line(line))
    end
end

--- Start over: clear everything and draw what doesn't depend on the planner.
--- @param player LuaPlayer
--- @param controller Controller
function lib.reset(player, controller)
    lib.delete_sprites(player)
    controller.work.draw = state.new_draw_progress()
    if controller.ui.draw_curve then
        draw_control_points(player, controller.curve)
    end
end

--- @param player LuaPlayer
--- @param progress DrawProgress
--- @param points Vector[]
--- @param sampling_done boolean
--- @param budget number
--- @return number used, boolean caught_up
local function step_curve(player, progress, points, sampling_done, budget)
    local used = 0
    local sprites = state.sprites(player.index).curve
    local line = base_params(player)
    line.color = CURVE_COLOR
    line.width = 5
    while progress.curve_cursor <= #points and used < budget do
        local p = points[progress.curve_cursor]
        local last = progress.curve_last
        if not last then
            progress.curve_last = p
        elseif vect.distance(last, p) >= lib.CURVE_SEGMENT then
            line.from, line.to = last, p
            table.insert(sprites, rendering.draw_line(line))
            progress.curve_last = p
            used = used + lib.COST.line
        end
        progress.curve_cursor = progress.curve_cursor + 1
    end
    if sampling_done and progress.curve_cursor > #points and not progress.curve_finished then
        local last, p = progress.curve_last, points[#points]
        if last and p and (last.x ~= p.x or last.y ~= p.y) then
            line.from, line.to = last, p
            table.insert(sprites, rendering.draw_line(line))
            used = used + lib.COST.line
        end
        progress.curve_finished = true
    end
    return used, progress.curve_finished
end

--- @param player LuaPlayer
--- @param progress DrawProgress
--- @param plan BuildPlan
--- @param budget number
--- @return number used, boolean caught_up
local function step_preview(player, progress, plan, budget)
    local used = 0
    local sprites = state.sprites(player.index).preview
    local rect = base_params(player)
    rect.filled = true
    rect.draw_on_ground = true

    while used < budget and progress.preview_count < lib.MAX_PREVIEW_OBJECTS do
        if progress.preview_tiles < #plan.tiles then
            local tile = plan.tiles[progress.preview_tiles + 1]
            rect.color = PREVIEW_TILE_COLOR
            rect.left_top = { x = tile.x + 0.05, y = tile.y + 0.05 }
            rect.right_bottom = { x = tile.x + 0.95, y = tile.y + 0.95 }
            progress.preview_tiles = progress.preview_tiles + 1
        elseif progress.preview_entities < #plan.entities then
            local entity = plan.entities[progress.preview_entities + 1]
            local half = entity.size / 2 - 0.05
            rect.color = PREVIEW_ENTITY_COLOR
            rect.left_top = vect.sub(entity.position, { x = half, y = half })
            rect.right_bottom = vect.add(entity.position, { x = half, y = half })
            progress.preview_entities = progress.preview_entities + 1
        else
            break
        end
        table.insert(sprites, rendering.draw_rectangle(rect))
        progress.preview_count = progress.preview_count + 1
        used = used + lib.COST.rectangle
    end
    local all_drawn = progress.preview_count >= lib.MAX_PREVIEW_OBJECTS
        or (progress.preview_tiles >= #plan.tiles and progress.preview_entities >= #plan.entities)
    return used, plan.done and all_drawn
end

--- Draw whatever the planner has produced since last time.
--- @param player LuaPlayer
--- @param controller Controller
--- @param plan_job PlannerJob|nil
--- @param budget number
--- @return number used, boolean caught_up
function lib.step(player, controller, plan_job, budget)
    local ui, progress = controller.ui, controller.work.draw
    if not plan_job then return 0, true end
    local used, caught_up = 0, true
    if ui.draw_curve then
        local u, done = step_curve(player, progress, plan_job.points, plan_job.stage ~= "sample", budget)
        used, caught_up = used + u, caught_up and done
    end
    if ui.preview_build then
        local u, done = step_preview(player, progress, plan_job.plan, budget - used)
        used, caught_up = used + u, caught_up and done
    end
    return used, caught_up
end

return lib
