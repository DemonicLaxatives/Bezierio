--- All rendering: control points, the curve, and the build preview.
---
--- Drawing follows the planner job (see jobs.lua): curve segments are drawn as
--- samples appear and the preview fills in as placements are found, a budgeted
--- amount per tick.
local vect = require("scripts.vector_math")
local state = require("scripts.state")
local palette = require("scripts.palette")

local lib = {}

--- Don't flood the renderer when previewing huge builds.
lib.MAX_PREVIEW_OBJECTS = 4000

--- Curve segments are at least this long (samples are denser than needed for drawing).
lib.CURVE_SEGMENT = 0.5

--- Work units per render object, for budgeting.
lib.COST = { line = 2, rectangle = 2, destroy = 1, circle = 2 }

local CURVE_COLOR = { r = 0.1, g = 0.3, b = 0.7, a = 1 }
local POINT_COLOR = { r = 0.5, g = 0, b = 0.2, a = 1 }
local HULL_COLOR = { r = 0.5, g = 0, b = 1, a = 1 }
local HELD_COLOR = { r = 1, g = 0.85, b = 0.2, a = 1 }
local WARNING_COLOR = { r = 1, g = 0.1, b = 0.1, a = 0.8 }
local PREVIEW_ENTITY_ALPHA = 0.3
local PREVIEW_TILE_ALPHA = 0.15

--- Retire render objects: they are destroyed a budgeted number per tick by
--- `lib.step_trash`, so clearing a big preview doesn't cost one long tick. They
--- stay visible until then (a tick or two at the default budget).
--- @param player LuaPlayer
--- @param key "curve"|"control_points"|"preview"|nil  # nil clears everything
function lib.delete_sprites(player, key)
    local sprites = state.sprites(player.index)
    sprites.trash = sprites.trash or {}
    for cache_key, cache in pairs(sprites) do
        if cache_key ~= "trash" and (key == nil or key == cache_key) then
            for _, obj in pairs(cache) do
                if obj.valid then table.insert(sprites.trash, obj) end
            end
            sprites[cache_key] = {}
        end
    end
end

--- Destroy retired render objects, up to the budget.
--- @param player_index integer
--- @param budget number
--- @return number used
function lib.step_trash(player_index, budget)
    local sprites = storage.sprites[player_index]
    local trash = sprites and sprites.trash
    if not trash then return 0 end
    local used = 0
    while #trash > 0 and used < budget do
        local obj = table.remove(trash)
        if obj.valid then obj.destroy() end
        used = used + lib.COST.destroy
    end
    return used
end

--- @param player LuaPlayer
local function base_params(player)
    return { surface = player.surface, players = { player.index }, visible = true }
end

--- Control point markers and the control polygon. A point held by the pointer is
--- highlighted.
--- @param player LuaPlayer
--- @param curve Curve
--- @param held integer|nil
local function draw_control_points(player, curve, held)
    local sprites = state.sprites(player.index).control_points

    local circle = base_params(player)
    circle.radius = 0.5
    circle.width = 10
    circle.filled = false

    local label = base_params(player)
    label.color = { r = 1, g = 1, b = 1, a = 1 }
    label.scale = 3

    for i, point in ipairs(curve.points) do
        circle.target = point
        circle.color = (i == held) and HELD_COLOR or POINT_COLOR
        table.insert(sprites, rendering.draw_circle(circle))
        label.target = point
        label.text = "P" .. i
        table.insert(sprites, rendering.draw_text(label))
    end

    local line = base_params(player)
    line.color = HULL_COLOR
    line.width = 2
    line.dash_length = 0.5
    line.gap_length = 0.25
    local points = curve.points
    local count = #points
    for i = 1, count - 1 do
        line.from, line.to = points[i], points[i + 1]
        table.insert(sprites, rendering.draw_line(line))
    end
    if curve.closed and count >= 3 then
        line.from, line.to = points[count], points[1]
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
        draw_control_points(player, controller.curve, controller.ui.held_point)
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
            rect.color = palette.layer_color(tile.layer, PREVIEW_TILE_ALPHA)
            rect.left_top = { x = tile.x + 0.05, y = tile.y + 0.05 }
            rect.right_bottom = { x = tile.x + 0.95, y = tile.y + 0.95 }
            progress.preview_tiles = progress.preview_tiles + 1
        elseif plan.done and (progress.preview_warnings or 0) < #plan.warnings then
            -- Tight bends: drawn once the plan is complete (the list grows while planning).
            progress.preview_warnings = (progress.preview_warnings or 0) + 1
            local circle = base_params(player)
            circle.color = WARNING_COLOR
            circle.radius = 0.6
            circle.width = 3
            circle.filled = false
            circle.target = plan.warnings[progress.preview_warnings]
            table.insert(sprites, rendering.draw_circle(circle))
            progress.preview_count = progress.preview_count + 1
            used = used + lib.COST.circle
            goto continue
        elseif progress.preview_entities < #plan.entities then
            local entity = plan.entities[progress.preview_entities + 1]
            local half = entity.size / 2 - 0.05
            rect.color = palette.layer_color(entity.layer, PREVIEW_ENTITY_ALPHA)
            rect.left_top = vect.sub(entity.position, { x = half, y = half })
            rect.right_bottom = vect.add(entity.position, { x = half, y = half })
            progress.preview_entities = progress.preview_entities + 1
        else
            break
        end
        table.insert(sprites, rendering.draw_rectangle(rect))
        progress.preview_count = progress.preview_count + 1
        used = used + lib.COST.rectangle
        ::continue::
    end
    return used, plan.done and lib.preview_complete(progress, plan)
end

--- Everything in the plan has been drawn (or the cap was reached).
--- @param progress DrawProgress
--- @param plan BuildPlan
--- @return boolean
function lib.preview_complete(progress, plan)
    return progress.preview_count >= lib.MAX_PREVIEW_OBJECTS
        or (progress.preview_tiles >= #plan.tiles and progress.preview_entities >= #plan.entities
            and (progress.preview_warnings or 0) >= #plan.warnings)
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
