local vect = require("scripts.vector_math")
local state = require("scripts.state")
local curve_control = require("scripts.curve_math.control")
local builder = require("scripts.build.builder")

local draw = {}

--- Don't flood the renderer when previewing huge builds.
draw.MAX_PREVIEW_OBJECTS = 4000

local CURVE_COLOR = { r = 0.1, g = 0.3, b = 0.7, a = 1 }
local POINT_COLOR = { r = 0.5, g = 0, b = 0.2, a = 1 }
local HULL_COLOR = { r = 0.5, g = 0, b = 1, a = 1 }
local PREVIEW_ENTITY_COLOR = { r = 0.5, g = 0.5, b = 0, a = 0.25 }
local PREVIEW_TILE_COLOR = { r = 0, g = 0.35, b = 0.15, a = 0.2 }

--- @param player LuaPlayer
--- @param key "curve"|"control_points"|"preview"|nil  # nil clears everything
function draw.delete_sprites(player, key)
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

--- @param player LuaPlayer
--- @param points Vector[]
function draw.curve(player, points)
    local sprites = state.sprites(player.index).curve
    local line = base_params(player)
    line.color = CURVE_COLOR
    line.width = 5
    for i = 1, #points - 1 do
        line.from = points[i]
        line.to = points[i + 1]
        table.insert(sprites, rendering.draw_line(line))
    end
end

--- Control point markers and the control polygon.
--- @param player LuaPlayer
function draw.control_points(player)
    local curve = state.curve(player.index)
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
    for i = 1, state.MAX_CONTROL_POINTS do
        local point = curve.raw_control_points[i]
        if point and point.x and point.y then
            table.insert(defined, point)
            circle.target = point
            table.insert(sprites, rendering.draw_circle(circle))
            label.target = point
            label.text = "P" .. i
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

--- Outline everything the current layers would place.
--- @param player LuaPlayer
--- @param plan BuildPlan
function draw.preview(player, plan)
    local sprites = state.sprites(player.index).preview
    local rect = base_params(player)
    rect.filled = true
    rect.draw_on_ground = true

    local count = 0
    rect.color = PREVIEW_TILE_COLOR
    for _, tile in ipairs(plan.tiles) do
        if count >= draw.MAX_PREVIEW_OBJECTS then return end
        rect.left_top = { x = tile.x + 0.05, y = tile.y + 0.05 }
        rect.right_bottom = { x = tile.x + 0.95, y = tile.y + 0.95 }
        table.insert(sprites, rendering.draw_rectangle(rect))
        count = count + 1
    end

    rect.color = PREVIEW_ENTITY_COLOR
    for _, entity in ipairs(plan.entities) do
        if count >= draw.MAX_PREVIEW_OBJECTS then return end
        local half = entity.size / 2 - 0.05
        rect.left_top = vect.sub(entity.position, { x = half, y = half })
        rect.right_bottom = vect.add(entity.position, { x = half, y = half })
        table.insert(sprites, rendering.draw_rectangle(rect))
        count = count + 1
    end
end

--- Redraw everything for one player according to their toggles.
--- @param player LuaPlayer
function draw.refresh(player)
    draw.delete_sprites(player)
    local ui = state.ui(player.index)
    local curve = state.curve(player.index)

    if ui.draw_curve then
        draw.control_points(player)
        draw.curve(player, curve_control.worldSamples(curve, curve.resolution))
    end
    if ui.preview_build then
        draw.preview(player, builder.plan(curve, state.layers(player.index)))
    end
end

--- Redraw one player if something changed since the last draw.
--- @param player_index integer
function draw.redraw_if_dirty(player_index)
    local controller = storage.controllers[player_index]
    if not (controller and controller.state.dirty) then return end
    controller.state.dirty = false
    controller.curve_cache[0].parameters_changed = false
    local player = game.get_player(player_index)
    if player and player.valid then
        draw.refresh(player)
    end
end

-- All drawing happens here, never inside GUI/input events: heavy work stays in the
-- tick loop, where it can be spread over ticks.
script.on_nth_tick(5, function()
    state.ensure()
    for player_index in pairs(storage.controllers) do
        draw.redraw_if_dirty(player_index)
    end
end)

return draw
