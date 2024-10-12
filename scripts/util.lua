local Table = require('__stdlib__/stdlib/utils/table')

local util = {}
util.rotation_matrix_90 =  {{0, -1}, {1, 0}}

local to_vector = math2d.position.ensure_xy
local add = math2d.position.add
local sub = math2d.position.subtract
local scale = math2d.position.multiply_scalar
local norm = math2d.position.vector_length

function util.matmul(m1, m2)
  local mtx = {}

  for i = 1,#m1 do
    mtx[i] = {}
    for j = 1,#m2[1] do
      local num = m1[i][1] * m2[1][j]
      for n = 2,#m1[1] do
        num = num + m1[i][n] * m2[n][j]
      end
      mtx[i][j] = num
    end
  end

  return mtx
end

function util.mat_dot_vect(mat, vector)

  if not mat then return vector end

  local vect = {}
  
  for i, elem_i in pairs(vector) do
      local num = mat[1][i]*elem_i
      for j = 2,#mat do
          num = num + elem_i * mat[j][i]
      end
      vect[i] = num
  end

  return vect
end

function util.cardinal_direction_to_transform(direction)
  direction = direction / 2

  if direction == 0 then
      return nil
  end

  local transform = Table.deep_copy(util.rotation_matrix_90)

  for i = 1, direction do
    transform = util.matmul(util.rotation_matrix_90, transform)
  end

  return transform
end

function util.is_equal(vec1, vec2)
  if xor(not vec1, not vec2) then
    return false
  end
  vec1 = math2d.position.ensure_xy(vec1)
  vec2 = math2d.position.ensure_xy(vec2)

  return (vec1.x == vec2.x) and (vec1.y == vec2.y)
end

return util