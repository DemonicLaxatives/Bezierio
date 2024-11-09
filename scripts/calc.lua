local vect = require("scripts.util")
local util = require("__core__/lualib/util")




--- @class Polynomial2D
--- @field degree integer
--- @field coefficients Vector[]

--- @class BezierCurve
--- @field coordinate_polynomial Polynomial2D
--- @field derivative_polynomial Polynomial2D
--- @field control_points ControlPoints

--- @class ControlPoints
--- @field p1 Vector|nil
--- @field p2 Vector|nil
--- @field v1 Vector|nil
--- @field v2 Vector|nil

local lib = {}

--- Returns two polynomials one for the coordinates and one for the derivatives
--- @param state InterfaceState
--- @return BezierCurve|nil
function lib.calculate_bezier_curve(state)
    local cp = util.table.deepcopy(state.control_points)
    if not cp.p1 or not cp.p2 then
        return nil
    end

    if not cp.v1 then
        cp.v1 = {x = cp.p1.x, y = cp.p1.y}
    end
    cp.v1 = vect.sub(cp.v1, cp.p1)
    if vect.norm(cp.v1) == 0  then
        cp.v1 = vect.normalize(vect.sub(cp.p2, cp.p1))
    end

    if not cp.v2 then
        cp.v2 = {x = cp.p2.x, y = cp.p2.y}
    end
    cp.v2 = vect.sub(cp.v2, cp.p2)
    if vect.norm(cp.v2) == 0 then
        cp.v2 = vect.normalize(vect.sub(cp.p1, cp.p2))
    end

    cp.v1 = vect.scale(cp.v1, state.control_vector_strengh[1]/100)
    cp.v2 = vect.scale(cp.v2, state.control_vector_strengh[2]/100)

    local a = vect.add(vect.sub(cp.v1, cp.v2), vect.scale(vect.sub(cp.p1, cp.p2), 2))
    local b = vect.add(vect.sub(vect.scale(vect.sub(cp.p2, cp.p1), 3), vect.scale(cp.v1, 2)), cp.v2)
    local c = vect.to_vector(cp.v1)
    local d = vect.to_vector(cp.p1)

    local poly1 = {degree = 4, coefficients = {a, b, c, d}}

    local a_ = vect.scale(a, 3)
    local b_ = vect.scale(b, 2)
    local c_ = c

    local poly2 = {degree = 3, coefficients = {a_, b_, c_}}

    return {coordinate_polynomial = poly1, derivative_polynomial = poly2, control_points = cp}
end

--- @param t number 
--- @param poly Polynomial2D
function lib.apply_poly(t, poly)
    local result = {x = 0, y = 0}
    for i = 1, poly.degree do
        result = vect.add(result, vect.scale(poly.coefficients[i], t ^ (poly.degree - i)))
    end
    return result
end

--- @param curve BezierCurve
--- @param t number
--- @return Vector
function lib.get_point(curve, t)
    return lib.apply_poly(t, curve.coordinate_polynomial)
end

--- @param curve BezierCurve
--- @param t number
--- @return Vector
function lib.get_derivative(curve, t)
    return lib.apply_poly(t, curve.derivative_polynomial)
end

--- @param curve BezierCurve
--- @param threshold_low number
--- @param threshold_high number
--- @return Vector[]
function lib.get_curve_points(curve, threshold_low, threshold_high)
    local MAX_ITERATIONS = 1000
    local curve_points = {curve.control_points.p1}
    local norm_derivative = vect.norm(lib.get_derivative(curve, 0))
    local dt = 1 / norm_derivative
    local t = dt
    local curve_point, norm_d_p
    local i = 0
    while (t <= 1)  and (i < MAX_ITERATIONS) do
        i = i + 1
        curve_point = lib.get_point(curve, t)
        local d_p = vect.sub(curve_point, curve_points[#curve_points])
        norm_d_p = vect.norm(d_p)

        if norm_d_p > threshold_high then
            t = t - dt*(1 - 1/norm_d_p)
        -- elseif norm_d_p < threshold_low then
        --     t = t + dt
        else
            table.insert(curve_points, curve_point)
            norm_derivative = vect.norm(lib.get_derivative(curve, t))

            if norm_derivative == 0 then
                dt = 1 - t
            else
                dt = 1 / norm_derivative
            end

            t = t + dt
        end
    end
    if i == MAX_ITERATIONS then
        game.print("Bezierio W: Maximum iterations reached.")
    end

    if curve_points[#curve_points] ~= curve.control_points.p2 then
        table.insert(curve_points, curve.control_points.p2)
    end
    return curve_points
end

--- @param num number
--- @param odd boolean
--- @return number
function lib.odd_round(num, odd)
    if odd then
        return math.floor(num) + 0.5
    end
    return math.floor(num + 0.5)
end

--- @param vector Vector
--- @param odd boolean
--- @return Vector
function lib.odd_round_vector(vector, odd)
    return {x = lib.odd_round(vector.x, odd), y = lib.odd_round(vector.y, odd)}
end

--- @param curve_points Vector[]
--- @param size integer
--- @return Vector[], integer[]
function lib.rasterize(curve_points, size)
    local odd = size % 2 == 1
    local quantized_curve_points = {lib.odd_round_vector(curve_points[1], odd)}
    local offset = vect.to_vector({x = size, y = size})

    local inices = {1}
    local j = 1
    for i, point in pairs(curve_points) do
        if i == 1 then goto continue end
        local quantized_point = lib.odd_round_vector(point, odd)
        local dp = vect.sub(quantized_point, quantized_curve_points[j])
        local dp_abs = vect.abs(dp)
        local db_sign = vect.sign(dp)
        local size_offset = vect.sub(offset, dp_abs)

        if not vect.all_gt(size_offset, 0) then
            for key, elem in pairs(size_offset) do
                if elem < 0 then
                    quantized_point[key] = quantized_point[key] - elem * db_sign[key]
                end
            end
            table.insert(inices, i)
            table.insert(quantized_curve_points, quantized_point)
            j = j + 1
        end
        ::continue::
    end
    return quantized_curve_points, inices
end

-- function lib.rasterize(curve_points)
--     local p1 = math.round(curve_points[1])
--     local p2, p3
--     local rounded_curve_points = { p1 }

--     for i = 1, #curve_points - 2 do
--         p2 = p3 or math.round(curve_points[i + 1])
--         p3 = math.round(curve_points[i + 2])

--         if p3 == p2 then goto continue end

--         local dp23 = math.sub(p3, p2)
--         local dp21 = math.sub(p1, p2)
--         local is_colinear = math.cross(dp23, dp21) == 0

--         if is_colinear then goto continue end

--         local is_at_full_angle = dp23.x == 0 or dp23.y == 0
--         local is_at_half_angle = math.abs(dp23.x / dp23.y) == 0

--         if not is_at_full_angle and not is_at_full_angle then
--             local elongation_axis
--             if math.abs(dp23.x) == 1 then
--                 elongation_axis = "y"
--             elseif math.abs(dp23.y) == 1 then
--                 elongation_axis = "x"
--             else
--                 game.print("Bezierio W: Something that is not supposed to happen, happened.")
--                 goto continue
--             end
--             local elongation = math.abs(dp23[elongation_axis])
--             local elongation_sign = dp23[elongation_axis] / elongation

--             p2[elongation_axis] = p2[elongation_axis] + elongation_sign * (elongation - 1)
--         end

--         ::add_point::
--         table.insert(rounded_curve_points, p2)
--         p1 = p2
--         ::continue::
--     end
--     if p3 ~= p1 then
--         table.insert(rounded_curve_points, p3)
--     end
--     return rounded_curve_points
-- end

return lib