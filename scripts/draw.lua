local vect = require("scripts/util")
local calc = require("scripts/calc")

local draw = {}


--- @param player LuaPlayer
--- @param key string|nil
function draw.delete_sprites(player, key)
    if not key then
        local sprite_cache = storage.sprites[player.index]
        for key, elem in pairs(sprite_cache) do
            if elem then
                for _, obj in pairs(elem) do
                    obj.destroy()
                end
            end
            sprite_cache[key] = {}
        end
    else
        local sprite_cache = storage.sprites[player.index][key]
        for _, obj in pairs(sprite_cache) do
            obj.destroy()
        end
        sprite_cache = {}
    end
end

--- @param player LuaPlayer
--- @param points Vector[]
--- @param color Color|nil
--- @param width number|nil
--- @param append boolean|nil
--- @param size integer|nil
function draw.curve(player, points, color, width, append, size)
    local sprites = storage.sprites[player.index].curve
    if not append then
        draw.delete_sprites(player, "curve")
        sprites = {}
    end

    if size then
        local offset = {x = 0.95 * size/2, y = 0.95 * size/2}
        local square = {}
        square.color = { r = 0.5, g = 0.5, b = 0, a = 0.2 }
        square.filled = true
        square.force = player.force
        square.surface = player.surface
        square.time_to_live = 60*60*5
        square.visible = true
        for _, point in pairs(points) do
            square.left_top = vect.sub(point, offset)
            square.right_bottom = vect.add(point, offset)
            table.insert(sprites, rendering.draw_rectangle(square))
        end
    end

    local line = {}
    line.color = color or { r = 0.5, g = 0, b = 0.2, a = 1 }
    line.width = width or 20
    line.force = player.force
    line.surface = player.surface
    line.time_to_live = 60*60*5
    line.visible = true

    for i = 1, #points - 1 do
        line.from = points[i]
        line.to = points[i + 1]
        table.insert(sprites, rendering.draw_line(line))
    end

    local point_marker = {}
    point_marker.color = { r = 1, g = 0, b = 0, a = 1 }
    point_marker.radius = 0.2
    point_marker.filled = true
    point_marker.force = player.force
    point_marker.surface = player.surface
    point_marker.time_to_live = 60*60*5
    point_marker.visible = true

    for _, point in pairs(points) do
        point_marker.target = point
        table.insert(sprites, rendering.draw_circle(point_marker))
    end
    storage.sprites[player.index].curve = sprites
end

--- @param player LuaPlayer
function draw.points(player)
    
    local state = storage.controllers[player.index].state
    local control_points = state.raw_control_points

    local sprites = storage.sprites[player.index].control_points

    if not state.draw_curve then return end

    local circle = {}
    circle.color = { r = 0.5, g = 0, b = 0.2, a = 1 }
    circle.radius = 0.5
    circle.width = 10
    circle.force = player.force
    circle.surface = player.surface
    circle.time_to_live = 60*60*5
    circle.visible = true
    circle.fill = false

    local point_label = {}
    point_label.color = { r = 1, g = 1, b = 1, a = 1 }
    point_label.scale = 3
    point_label.force = player.force
    point_label.surface = player.surface
    point_label.time_to_live = 60*60*5
    point_label.visible = true

    for i, point in pairs(control_points) do
        if point then
            circle.target = point
            table.insert(sprites, rendering.draw_circle(circle))
            point_label.target = point
            point_label.text = "P"..tostring(i)
            table.insert(sprites, rendering.draw_text(point_label))
        end
    end
    storage.sprites[player.index].control_points = sprites
end

--- @param player LuaPlayer
function draw.lines(player)
    local state = storage.controllers[player.index].state
    local control_points = calc.filter_control_points(state.raw_control_points)

    local sprites = storage.sprites[player.index].control_points

    if not state.draw_curve then return end

    local line = {}
    line.color = {r = 0.5, g = 0, b = 1}
    line.width = 5
    line.force = player.force
    line.surface = player.surface
    line.time_to_live = 60*60*5
    line.visible = true

    for i = 1, #control_points - 1 do
        line.from = control_points[i]
        line.to = control_points[i + 1]
        table.insert(sprites, rendering.draw_line(line))
    end
    storage.sprites[player.index].control_points = sprites
end

--- @param player LuaPlayer
function draw.control_points(player)
    draw.delete_sprites(player, "control_points")
    draw.points(player)
    draw.lines(player)
end

script.on_nth_tick(5, function()
    for _, player in pairs(game.players) do
        if not storage.controllers[player.index] then return end
        local state = storage.controllers[player.index].state
        if state.draw_curve then
            if not state.parameters_changed then return end
            draw.control_points(player)
            local curve = calc.generate_bezier_curve(state)
            if curve then
                local curve_points = calc.get_curve_points(curve, 1.414)
                local raser_curve_points, indices = calc.rasterize(curve_points, state.build_spacing)
                local curve_points_ = {}
                for _, i in pairs(indices) do
                    table.insert(curve_points_, curve_points[i])
                end
                draw.curve(player, raser_curve_points, { r = 0.5, g = 0.1, b = 0.2, a = 0.7 }, 15, false, state.build_spacing)
                draw.curve(player, curve_points_, { r = 0.5, g = 0, b = 0.7, a = 1 }, 5, true)
            else
                draw.delete_sprites(player)
            end
            state.parameters_changed = false
        end
    end
end)



return draw