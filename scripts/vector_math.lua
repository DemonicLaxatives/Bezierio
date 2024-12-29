local lib = {}
lib.D1 = {}

--- @class Vector
--- @field public x number
--- @field public y number

--- @param x number
--- @return number
function lib.D1.sign(x)
  if x < 0 then
    return -1
  elseif x > 0 then
    return 1
  else
    return 0
  end
end

--- @param x number
--- @param cell_center boolean
--- @return number
function lib.D1.cc_round(x, cell_center)
  if cell_center then
    return math.floor(x) + 0.5
  else
    return math.floor(x + 0.5)
  end
end

--- Round a number to n decimal places
--- @param x number
--- @param n integer|nil
--- @return number
function lib.D1.round(x, n)
  n = n or 0
  local m = 10^n
  return math.floor(x * m + 0.5) / m
end

--- @param p1 Vector
--- @param p2 Vector
--- @return Vector
function lib.add(p1, p2)
  return {x = p1.x + p2.x, y = p1.y + p2.y}
end

--- @param p1 Vector
--- @param p2 Vector
--- @return Vector
function lib.sub(p1, p2)
  return {x = p1.x - p2.x, y = p1.y - p2.y}
end

--- @param k number
--- @param p1 Vector
--- @return Vector
function lib.scale(k, p1)
  return {x = k * p1.x, y = k * p1.y}
end

--- @param p1 Vector
--- @param p2 Vector
--- @return number
function lib.dot(p1, p2)
  return p1.x * p2.x + p1.y * p2.y
end

--- @param p1 Vector
--- @param p2 Vector
--- @return number
function lib.cross(p1, p2)
  return p1.x * p2.y - p1.y * p2.x
end

--- @param vect Vector
--- @return number
function lib.norm(vect)
  return math.sqrt(vect.x*vect.x + vect.y*vect.y)
end

--- @param p1 Vector
--- @param p2 Vector
--- @return number
function lib.distance(p1, p2)
  return lib.norm(lib.sub(p1, p2))
end

--- @param vect Vector
--- @return Vector
function lib.normalize(vect)
  local abs = lib.norm(vect)
  return lib.scale(1/abs, vect)
end

--- @param vect Vector
--- @return Vector
function lib.sign(vect)
  return {x = lib.D1.sign(vect.x), y = lib.D1.sign(vect.y)}
end

--- @param vect Vector
--- @return Vector
function lib.abs(vect)
  return {x = math.abs(vect.x), y = math.abs(vect.y)}
end

--- @param vect Vector
--- @param cell_center boolean
--- @return Vector
function lib.cc_round(vect, cell_center)
  return {x = lib.D1.cc_round(vect.x, cell_center), y = lib.D1.cc_round(vect.y, cell_center)}
end

--- @param vect Vector
--- @param n integer|nil
--- @return Vector
function lib.round(vect, n)
  return {x = lib.D1.round(vect.x, n), y = lib.D1.round(vect.y, n)}
end

return lib

