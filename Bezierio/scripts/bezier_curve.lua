math2d = require("__core__/lualib/math2d")
local Table = require('__stdlib__/stdlib/utils/table')

local to_vector = math2d.position.ensure_xy
local add = math2d.position.add
local sub = math2d.position.subtract
local scale = math2d.position.multiply_scalar
local norm = math2d.position.vector_length

function math2d.position.scalar_product(p1, p2)
    p1 = math2d.position.ensure_xy(p1)
    p2 = math2d.position.ensure_xy(p2)

    return p1.x * p2.x + p1.y * p2.y
end

local scalar_prod = math2d.position.scalar_product

function math.round(x)
    return math.floor(x + 0.5)
end

function math2d.position.round(pos)
    pos = to_vector(pos)
    return { x = math.round(pos.x), y = math.round(pos.y) }
end

function math2d.position.is_zero(vector)
    vector = math2d.position.ensure_xy(vector)
    return vector
end

function math2d.position.cross_prod(vec1, vec2)
    vec1 = math2d.position.ensure_xy(vec1)
    vec2 = math2d.position.ensure_xy(vec2)

    return vec1.x * vec2.y - vec1.y * vec2.x
end

function math2d.position.rotate_by_90(vector)
    vector = math2d.position.ensure_xy(vector)
    return { x = -vector.y, y = vector.x }
end

local cross = math2d.position.cross_prod
local rot90 = math2d.position.rotate_by_90
local round = math2d.position.round

Curve = {}

function Curve.DrawCurve(target, points)
    local line        = {}

    line.color        = { r = 0.5, g = 0, b = 0.2, a = 1 }
    line.width        = 20
    line.from         = target.entity
    line.to           = target.entity
    line.force        = target.entity.force
    line.surface      = target.entity.surface
    line.time_to_live = 60*60*5
    line.visible      = true

    local ids         = {}
    for i = 1, #points - 1 do
        line.from_offset = add(points[i], target.reference_point)
        line.to_offset = add(points[i + 1], target.reference_point)

        id = rendering.draw_line(line)
        table.insert(ids, id)
    end
    return ids
end

function Curve.DrawVector(target, point, vector)
    point             = add(point, target.reference_point)
    local line        = {}

    line.color        = { r = 0, g = 0.5, b = 0, a = 1 }
    line.width        = 20
    line.from         = target.entity
    line.to           = target.entity
    line.force        = target.entity.force
    line.surface      = target.entity.surface
    line.time_to_live = 60*60*5
    line.visible      = true

    line.from_offset  = point
    line.to_offset    = add(point, vector)

    local ids         = {}
    table.insert(ids, rendering.draw_line(line))

    return ids
end

function Curve.CalculateBezierCurve(p1, p2, v1, v2)
    local a, b, c, d, d_p

    d = to_vector(p1)
    c = to_vector(v1)

    p2 = to_vector(p2)
    v2 = to_vector(v2)

    d_p = sub(d, p2)

    a = add(sub(v1, v2), scale(d_p, 2))
    b = add(add(scale(d_p, -3), scale(v1, -2)), v2)

    function get_point(t)
        return add(add(add(scale(a, t ^ 3), scale(b, t ^ 2)), scale(c, t)), d)
    end

    function get_derivative(t)
        return add(add(scale(a, 3 * t ^ 2), scale(b, 2 * t)), c)
    end

    local threshold = 2 ^ 0.5
    local curve_points = { p1 }

    local norm_derivative = norm(get_derivative(0))
    local dt = 1 / norm_derivative
    local t = dt
    local curve_point, norm_d_p
    local i = 0
    while t <= 1 do
        i = i + 1
        curve_point = get_point(t)
        d_p = sub(curve_point, curve_points[#curve_points])
        norm_d_p = norm(d_p)

        if norm_d_p > threshold then
            t = t - dt
            dt = dt / norm_d_p
            t = t + dt
            goto continue
        end
        table.insert(curve_points, curve_point)
        norm_derivative = norm(get_derivative(t))

        if norm_derivative == 0 then
            dt = 1 - t
        else
            dt = 1 / norm_derivative
        end

        t = t + dt
        ::continue::
    end

    if curve_points[#curve_points] ~= p2 then
        table.insert(curve_points, p2)
    end
    return curve_points
end

function Curve.rasterize(curve_points)
    local p1 = round(curve_points[1])
    local p2, p3
    local rounded_curve_points = { p1 }

    for i = 1, #curve_points - 2 do
        p2 = p3 or round(curve_points[i + 1])
        p3 = round(curve_points[i + 2])

        if p3 == p2 then goto continue end

        local dp23 = sub(p3, p2)
        local dp21 = sub(p1, p2)
        local is_colinear = cross(dp23, dp21) == 0

        if is_colinear then goto continue end

        local is_at_full_angle = dp23.x == 0 or dp23.y == 0
        local is_at_half_angle = math.abs(dp23.x / dp23.y) == 0

        if not is_at_full_angle and not is_at_full_angle then
            local elongation_axis
            if math.abs(dp23.x) == 1 then
                elongation_axis = "y"
            elseif math.abs(dp23.y) == 1 then
                elongation_axis = "x"
            else
                game.print("Not supposed to happen")
                goto continue
            end
            local elongation = math.abs(dp23[elongation_axis])
            local elongation_sign = dp23[elongation_axis] / elongation

            p2[elongation_axis] = p2[elongation_axis] + elongation_sign * (elongation - 1)
        end

        ::add_point::
        table.insert(rounded_curve_points, p2)
        p1 = p2
        ::continue::
    end
    if p3 ~= p1 then
        table.insert(rounded_curve_points, p3)
    end
    return rounded_curve_points
end

function Curve.BuildCurve(entity_from, rasterized_points, thickness)
    local p1, p2
    local dp, p0
    local blueprint_inventory
    for _, connector in pairs(entity_from.connectors) do
        if connector.name == "curve-projector-controller" then
            blueprint_inventory = connector.get_inventory(defines.inventory.chest)
        end
    end

    local start = -(math.floor((thickness - 1) / 2))
    local stop = (math.floor(thickness / 2))

    if blueprint_inventory[1] then
        blueprint_inventory[1].clear_blueprint()
        local blueprint_entity_array = {}


        local entity_number = 0

        for i = start, stop do
            table.insert(blueprint_entity_array, {
                name = "stone-wall",
                entity_number = entity_number,
                position = { 0, i },
            })
            entity_number = entity_number + 1
        end

        blueprint_inventory[1].set_blueprint_entities(blueprint_entity_array)
    end

    if blueprint_inventory[2] then
        blueprint_inventory[2].clear_blueprint()
        local blueprint_entity_array = {}

        local entity_number = 0

        for i = start, stop do
            for j = start, stop do
                if i * j >= 0 then
                    if start-1 <= i+j and i+j <= stop+1 then
                        table.insert(blueprint_entity_array, {
                            name = "stone-wall",
                            entity_number = entity_number,
                            position = { i, j },
                        })
                        entity_number = entity_number + 1
                    end
                end
            end
        end

        blueprint_inventory[2].set_blueprint_entities(blueprint_entity_array)
    end

    for i = 1, #rasterized_points - 1 do
        p1 = rasterized_points[i]
        p2 = rasterized_points[i + 1]

        dp = sub(p2, p1)
        p1 = add(entity_from.entity.position, p1)

        if dp.x ~= 0 and dp.y ~= 0 then
            Curve.BuildSlopedLine(entity_from, p1, dp, blueprint_inventory[2])
        else
            Curve.BuildStraightLine(entity_from, p1, dp, blueprint_inventory[1])
        end
    end
end

function Curve.BuildStraightLine(entity_from, p1, dp, blueprint)
    local axis, axs, direction
    if dp.x ~= 0 then
        axis = "x"
        axs = "y"
    else
        axis = "y"
        axs = "x"
    end

    local start = 0
    local stop = dp[axis]
    local step = stop / math.abs(stop)

    if dp.x > 0 then
        direction = 0
    elseif dp.x < 0 then
        direction = 4
    elseif dp.y > 0 then
        direction = 6
    elseif dp.y < 0 then
        direction = 2
    end

    local build_order = {}
    build_order.surface = entity_from.entity.surface
    build_order.force = entity_from.entity.force
    build_order.force_build = true
    build_order.direction = direction

    p1 = add(p1, entity_from.reference_point)

    local position = {}
    position[axs] = p1[axs]

    for i = start, stop, step do
        position[axis] = i + p1[axis]
        build_order.position = position
        blueprint.build_blueprint(build_order)
    end
end

function Curve.BuildSlopedLine(entity_from, p1, dp, blueprint)
    local start = 0
    local stop = dp.x
    local step = {}
    step.x = stop / math.abs(stop)
    step.y = dp.y / math.abs(dp.y)


    if dp.x > 0 and dp.y < 0 then
        dir = 4
    elseif dp.x < 0 and dp.y < 0 then
        dir = 6
    elseif dp.x < 0 and dp.y > 0 then
        dir = 0
    elseif dp.x > 0 and dp.y > 0 then
        dir = 2
    end

    local build_order = {}
    build_order.surface = entity_from.entity.surface
    build_order.force = entity_from.entity.force
    build_order.force_build = true
    build_order.direction = dir

    p1 = add(p1, entity_from.reference_point)

    local position = {}

    j = 0
    for i = start, stop, step.x do
        position.x = p1.x + i
        position.y = p1.y + j
        build_order.position = position
        blueprint.build_blueprint(build_order)
        j = j + step.y
    end
end

return Curve
