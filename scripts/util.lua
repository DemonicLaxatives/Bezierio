math2d = require("__core__.lualib.math2d")
util = require("__core__.lualib.util")

local lib = {}
--- @class Vector
--- @field public x number
--- @field public y number

function math.sign(x)
  return x > 0 and 1 or x < 0 and -1 or 0
end

lib.rotation_matrix_90 =  {{0, -1}, {1, 0}}

--- @param num number
--- @return integer
function lib.num_round(num)
  -- if num >= 0 then
      return math.floor(num + 0.5)
  -- else
      -- return math.ceil(num - 0.5)
  -- end
end

--- @param vector Vector
--- @return Vector
function lib.round(vector)
  return {x = lib.num_round(vector.x), y = lib.num_round(vector.y)}
end

--- @param vector number[]
--- @return Vector
function lib.to_vector(vector)
  return math2d.position.ensure_xy(vector)
end

--- @param v1 Vector
--- @param v2 Vector
--- @return Vector
function lib.add(v1, v2)
  return math2d.position.add(v1, v2)
end

--- @param v1 Vector
--- @param v2 Vector
--- @return Vector
function lib.sub(v1, v2)
  return math2d.position.subtract(v1, v2)
end

--- @param vector Vector
--- @param scalar number
--- @return Vector
function lib.scale(vector, scalar)
  return math2d.position.multiply_scalar(vector, scalar)
end

--- @param vector Vector
--- @return number
function lib.norm(vector)
  return math2d.position.vector_length(vector)
end

--- @param vector Vector
--- @return Vector
function lib.normalize(vector)
  return lib.scale(vector, 1 / lib.norm(vector))
end

--- @param vector1 Vector
--- @param vector2 Vector
--- @return number
function lib.cross(vector1, vector2)
  return vector1.x * vector2.y - vector1.y * vector2.x
end

--- @param vector1 Vector
--- @param vector2 Vector
--- @return number
function lib.dot(vector1, vector2)
  return vector1.x * vector2.x + vector1.y * vector2.y
end

--- @param vector Vector
--- @param angle_in_deg number
--- @return Vector
function lib.rotate_vector(vector, angle_in_deg)
  return math2d.position.rotate_vector(vector, angle_in_deg)
end

--- @param vector Vector
--- @return Vector
function lib.abs(vector)
  return {x = math.abs(vector.x), y = math.abs(vector.y)}
end

--- @param vector Vector
--- @param num number
--- @return boolean
function lib.all_gt(vector, num)
  return vector.x > num and vector.y > num
end

--- @param vector Vector
--- @return boolean
function lib.any_zero(vector)
  return vector.x == 0 or vector.y == 0
end

--- @param vector Vector
--- @return Vector
function lib.sign(vector)
  return {x = math.sign(vector.x), y = math.sign(vector.y)}
end

return lib

