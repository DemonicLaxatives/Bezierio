local vect = require("scripts/util")
local calc = require("scripts/calc")
local util = require("__core__/lualib/util")

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

function draw.vector(player, key)
    local state = storage.controllers[player.index].state
    local sprites = storage.sprites[player.index][key]
    if sprites then
        draw.delete_sprites(player, key)
    end

    if not state.draw_curve then return end

    -- local control_points = util.table.deepcopy(state.control_points)
    local control_points = state.control_points
    local p1, p2
    if key == "v1" then
        p1 = control_points.p1
        p2 = control_points.v1
    elseif key == "v2" then
        p1 = control_points.p2
        p2 = control_points.v2
    else
        error("Invalid key")
    end

    if not p1 or not p2 then return end

    local line = {
        color = {r = 0.5, g = 0, b = 1},
        width = 2,
        gap_length = 0,
        dash_length = 0,
        players = {player},
        surface = player.surface,
        time_to_live = 60*60*5
    }

    line.from = p1
    line.to = p2
    table.insert(sprites, rendering.draw_line(line))
    
    local vector = vect.sub(p2, p1)
    vector = vect.normalize(vector)
    local arrow_head_1 = vect.rotate_vector(vector, 135)
    local arrow_head_2 = vect.rotate_vector(vector, -135)

    line.from = p2
    line.to = vect.add(p2, arrow_head_1)
    table.insert(sprites, rendering.draw_line(line))

    line.to = vect.add(p2, arrow_head_2)
    table.insert(sprites, rendering.draw_line(line))

    storage.sprites[player.index][key] = sprites
end

--- @param player LuaPlayer
function draw.point(player, key)
    if (not key == "p1") or (not key == "p2") then
        error("Invalid key")
    end
    local state = storage.controllers[player.index].state
    -- local control_points = util.table.deepcopy(state.control_points)
    local control_points = state.control_points
    local point = control_points[key]

    if not point then return end
    local sprites = storage.sprites[player.index][key]
    if sprites then
        draw.delete_sprites(player, key)
    end

    if key == "p1" then
        draw.vector(player, "v1")
    elseif key == "p2" then
        draw.vector(player, "v2")
    end

    if not state.draw_curve then return end

    local circle = {}
    circle.color = { r = 0.5, g = 0, b = 0.2, a = 1 }
    circle.radius = 1
    circle.width = 5
    circle.force = player.force
    circle.surface = player.surface
    circle.time_to_live = 60*60*5
    circle.visible = true
    circle.fill = false

    circle.target = point
    sprites = {rendering.draw_circle(circle),}
    storage.sprites[player.index][key] = sprites
end

--- @param player LuaPlayer
function draw.control_point(player, key)
    if key == "p1" or key == "p2" then
        draw.point(player, key)
    elseif key == "v1" or key == "v2" then
        draw.vector(player, key)
    end
end

script.on_nth_tick(5, function()
    for _, player in pairs(game.players) do
        if not storage.controllers[player.index] then return end
        local state = storage.controllers[player.index].state
        if state.draw_curve then
            if not state.parameters_changed then return end

            local curve = calc.calculate_bezier_curve(state)
            if curve then
                local curve_points = calc.get_curve_points(curve, 0.9, 1.414)
                local raser_curve_points,_ = calc.rasterize(curve_points, state.build_spacing)
                draw.curve(player, raser_curve_points, { r = 0.5, g = 0.1, b = 0.2, a = 0.7 }, 15, false, state.build_spacing)
                draw.curve(player, curve_points, { r = 0.5, g = 0, b = 0.7, a = 1 }, 5, true)
                draw.control_point(player, 'p1')
                draw.control_point(player, 'p2')
            else
                draw.delete_sprites(player)
            end

            state.parameters_changed = false
        end
    end
end)



return draw