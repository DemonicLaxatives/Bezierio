local vect = require("scripts.util")
local util = require("__core__/lualib/util")
local coefficients = require("scripts/generated/curve_coefficients")

--- @class Polynomial2D
--- @field degree integer
--- @field coefficients Vector[]

--- @class BezierCurve
--- @field coordinate_polynomial Polynomial2D
--- @field derivative_polynomial Polynomial2D
--- @field control_points Vector[]

local lib = {}

function lib.filter_control_points(points)
    local filtered_points = {}
    --- TODO: Offset relative to the first point
    for _, point in pairs(points) do
        if point then
            table.insert(filtered_points, {x = point.x, y = point.y})
        end
    end
    return filtered_points
end

--- @param poly Polynomial2D
--- @return Polynomial2D
function lib.get_derivative_poly(poly)
    local derivative = {degree = poly.degree - 1, coefficients = {}}
    for i, coeff in pairs(poly.coefficients) do
        if i > 1 then
            table.insert(derivative.coefficients, vect.scale(coeff, i-1))
        end
    end
    return derivative
end

--- Returns two polynomials one for the coordinates and one for the derivatives
--- @param state InterfaceState
--- @return BezierCurve|nil
function lib.generate_bezier_curve(state)
    local cp = lib.filter_control_points(state.raw_control_points)
    local error_state, params = pcall(coefficients.get_coefficients, cp)
    if not error_state then return end
    if not params then return end
    --- @type Polynomial2D
    local curve_poly = {coefficients = params, degree = #params - 1}
    local curve = {
        coordinate_polynomial = curve_poly,
        derivative_polynomial = lib.get_derivative_poly(curve_poly),
        control_points = cp,
    }
    return curve
end

--- @param t number 
--- @param poly Polynomial2D
function lib.apply_poly(t, poly)
    local result = {x = 0, y = 0}
    for i, coeff in pairs(poly.coefficients) do
        local term = vect.scale(coeff, t^(i-1))
        result = vect.add(result, term)
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
--- @param threshold_high number
--- @return Vector[]
function lib.get_curve_points(curve, threshold_high)
    local MAX_ITERATIONS = 1000
    local control_points = lib.filter_control_points(curve.control_points)
    local curve_points = {control_points[1]}
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

    if curve_points[#curve_points] ~= curve.control_points then
        table.insert(curve_points, control_points[#control_points])
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
    local rounded_curve_points = {lib.odd_round_vector(curve_points[1], odd)}

    local indices = {1}
    table.remove(curve_points, 1)
    local j = 1
    for i, point in pairs(curve_points) do
        local rounded_point = lib.odd_round_vector(point, odd)
        local dp = vect.sub(rounded_point, rounded_curve_points[j])
        local dp_abs = vect.abs(dp)
        local db_sign = vect.sign(dp)
        local size_offset = {x = size - dp_abs.x, y = size - dp_abs.y}

        local insert = false
        for key, elem in pairs(size_offset) do
            if elem <= 0 then
                insert = true
                rounded_point[key] = rounded_point[key] - elem * db_sign[key]
            end
        end
        if insert then
            table.insert(indices, i)
            table.insert(rounded_curve_points, rounded_point)
            j = j + 1
        end
    end
    return rounded_curve_points, indices
end

return lib