--- 2D vector helpers. Vectors are {x = number, y = number}.
local lib = {}

--- @class Vector
--- @field x number
--- @field y number

--- Helpers for plain numbers.
lib.scalar = {}

--- Round to n decimal places.
--- @param x number
--- @param n integer|nil
--- @return number
function lib.scalar.round(x, n)
  local m = 10 ^ (n or 0)
  return math.floor(x * m + 0.5) / m
end

--- @param p1 Vector
--- @param p2 Vector
--- @return Vector
function lib.add(p1, p2)
  return { x = p1.x + p2.x, y = p1.y + p2.y }
end

--- @param p1 Vector
--- @param p2 Vector
--- @return Vector
function lib.sub(p1, p2)
  return { x = p1.x - p2.x, y = p1.y - p2.y }
end

--- @param k number
--- @param p Vector
--- @return Vector
function lib.scale(k, p)
  return { x = k * p.x, y = k * p.y }
end

--- @param p1 Vector
--- @param p2 Vector
--- @return number
function lib.dot(p1, p2)
  return p1.x * p2.x + p1.y * p2.y
end

--- @param v Vector
--- @return number
function lib.norm(v)
  return math.sqrt(v.x * v.x + v.y * v.y)
end

--- @param p1 Vector
--- @param p2 Vector
--- @return number
function lib.distance(p1, p2)
  return lib.norm(lib.sub(p1, p2))
end

--- Unit vector in the same direction; the zero vector stays zero.
--- @param v Vector
--- @return Vector
function lib.normalize(v)
  local length = lib.norm(v)
  if length == 0 then return { x = 0, y = 0 } end
  return lib.scale(1 / length, v)
end

--- Rotated 90° (to the right of the direction of travel in Factorio's y-down world).
--- @param v Vector
--- @return Vector
function lib.perpendicular(v)
  return { x = -v.y, y = v.x }
end

return lib
