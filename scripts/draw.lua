local vect = require("scripts.vector_math")
local calc = require("scripts.calc")

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

    -- local point_marker = {}
    -- point_marker.color = { r = 1, g = 0, b = 0, a = 1 }
    -- point_marker.radius = 0.2
    -- point_marker.filled = true
    -- point_marker.force = player.force
    -- point_marker.surface = player.surface
    -- point_marker.time_to_live = 60*60*5
    -- point_marker.visible = true

    -- for _, point in pairs(points) do
    --     point_marker.target = point
    --     table.insert(sprites, rendering.draw_circle(point_marker))
    -- end
    storage.sprites[player.index].curve = sprites
end

--- @param player LuaPlayer
function draw.points(player)
    local state = storage.controllers[player.index].state
    local curve_params = storage.controllers[player.index].curve_params
    if curve_params.degree < 0 then return end
    local control_points = curve_params.raw_control_points

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
            if point.x and point.y then
                circle.target = point
                table.insert(sprites, rendering.draw_circle(circle))
                point_label.target = point
                point_label.text = "P"..tostring(i)
                table.insert(sprites, rendering.draw_text(point_label))
            end
        end
    end
    storage.sprites[player.index].control_points = sprites
end

--- @param player LuaPlayer
function draw.lines(player)
    local state = storage.controllers[player.index].state
    local curve_params = storage.controllers[player.index].curve_params
    if curve_params.degree < 1 then return end
    local p0 = curve_params.p0
    if not p0 then
        error("p0 is nil")
    end
    local control_points = curve_params.control_points
    if not control_points then
        error("control_points is nil")
    end

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
        line.from = vect.add(control_points[i], p0)
        line.to = vect.add(control_points[i + 1], p0)
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

        local curve_params = storage.controllers[player.index].curve_params
        if curve_params.parameters_changed then
            draw.control_points(player)
        end

        if state.draw_curve then
            if not curve_params.parameters_changed then return end
            if curve_params.degree > 0 then
                local curve_points = calc.sampleBezierCurve(curve_params.control_points, 0.5)
                for i = 1, #curve_points do
                    curve_points[i] = vect.add(curve_points[i], curve_params.p0)
                end
                local raser_curve_points = calc.curveRound(curve_points, state.build_spacing)
                -- local raser_curve_points = calc.betterCurveRound(curve_points, state.build_spacing, true, state.build_spacing+1)

                draw.curve(player, raser_curve_points, { r = 0.5, g = 0.1, b = 0.2, a = 0.7 }, 15, false, state.build_spacing)
                draw.curve(player, curve_points , { r = 0.1, g = 0.3, b = 0.7, a = 1 }, 5, true)
            else
                draw.delete_sprites(player, "curve")
            end
            curve_params.parameters_changed = false
        end

    end
end)



return draw