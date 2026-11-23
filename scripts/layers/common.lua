--- Pieces shared by several layer types.
local lib = {}

--- Layer 0 bands are centred on the curve, so a radius r band is 2r-1 tiles wide;
--- side bands are r tiles wide.
--- @param layer Layer
--- @return number
function lib.band_thickness(layer)
    if layer.idx == 0 then
        return 2 * layer.radius - 1
    end
    return layer.radius
end

--- @type LayerField
lib.checkerboard = { name = "checkerboard", widget = "slider", min = -10, max = 10, default = 0 }

--- @type LayerField
lib.radius = { name = "radius", widget = "slider", min = 1, max = 10, default = 1 }

--- Red and green wire checkboxes (poles, land mines).
lib.red_wire = { name = "red_wire", widget = "checkbox", default = false }
lib.green_wire = { name = "green_wire", widget = "checkbox", default = false }

--- Path layers (belts, pipes): how many parallel lines.
--- @type LayerField
lib.lines = { name = "lines", widget = "slider", min = 1, max = 8, default = 1 }

--- Path layers: which way along the curve things flow.
--- @type LayerField
lib.flow = { name = "flow", widget = "choice", options = { "forward", "backward" }, label_prefix = "bezierio-flow", default = "forward" }

--- Path layers: the lines side by side, `line_gap` empty cells between them.
--- @param layer Layer
--- @return number
function lib.path_thickness(layer)
    local lines = layer.lines or 1
    return lines + (lines - 1) * (layer.line_gap or 0)
end

--- The item that builds an entity (for the totals), if any.
--- @param prototype LuaEntityPrototype
--- @return string|nil
function lib.item_for(prototype)
    local items = prototype.items_to_place_this
    return items and items[1] and items[1].name or nil
end

--- A spacing slider: from the entity's size up to `max(layer)`.
--- @param max fun(layer: Layer): integer
--- @param default fun(layer: Layer): integer|nil
--- @return LayerField
function lib.spacing(max, default)
    return {
        name = "spacing", widget = "slider",
        min = function(layer) return layer.size end,
        max = function(layer) return math.max(layer.size, max(layer)) end,
        default = default or function(layer) return layer.size end,
    }
end

--- The direction (0..15, as defines.direction: north 0, clockwise) nearest to a
--- vector, among `count` evenly spaced ones (4, 8 or 16).
--- @param v Vector  # map coordinates: y points down (south)
--- @param count integer
--- @return integer
function lib.direction(v, count)
    local angle = math.atan2(v.x, -v.y) -- clockwise from north
    local step = 2 * math.pi / count
    local index = math.floor(angle / step + 0.5) % count
    return index * (16 / count)
end

--- Turrets that can't turn all the way round face away from the curve (or towards it).
--- @type LayerField
lib.facing = {
    name = "facing", widget = "choice", options = { "outward", "inward" }, label_prefix = "bezierio-facing",
    default = "outward",
    visible_if = function(layer) return layer.turn_limited == true end,
}

--- Turrets' targeting priorities: what they shoot first, in order (entity names),
--- and whether they shoot anything else at all. Not for artillery (the game has no
--- priority list for it).
--- @type LayerField
lib.priority_targets = {
    name = "priority_targets", widget = "targets", default = nil,
    visible_if = function(layer) return layer.can_prioritise == true end,
}
--- @type LayerField
lib.ignore_unprioritised = {
    name = "ignore_unprioritised", widget = "checkbox", default = false,
    visible_if = function(layer) return layer.can_prioritise == true and layer.priority_targets ~= nil end,
}

--- Derived values for turrets: whether they turn all the way round, in how many
--- directions they can be built, and what ammo they take.
--- @param layer Layer
--- @param prototype LuaEntityPrototype
function lib.init_turret(layer, prototype)
    local attack = prototype.attack_parameters
    layer.turn_limited = attack ~= nil and (attack.turn_range or 1) < 1 or nil
    layer.directions = (prototype.flags and prototype.flags["building-direction-8-way"]) and 8 or 4
    layer.tile_w, layer.tile_h = prototype.tile_width, prototype.tile_height
    layer.can_prioritise = prototype.type ~= "artillery-turret" or nil
end

--- Facing and footprint for turrets: rotate limited ones to face outward (or
--- inward), and place non-square ones on their own grid within the square the
--- planner reserved. Facing straight, a w x h turret (flamethrower 2x3) needs a
--- whole-number centre along its even side. Facing diagonally, its footprint is the
--- size x size square minus corners (seen in the game for the flamethrower: 3x3
--- without two opposite corners, centred like the 3x3 square), so the reserved
--- square's centre is right.
--- @param layer Layer
--- @param entity PlannedEntity
--- @param info PlacementInfo
--- @param directions integer|nil  # limit to this many directions (fed fluid turrets: 4)
function lib.decorate_turret(layer, entity, info, directions)
    if layer.can_prioritise and layer.priority_targets then
        entity.priority_targets = layer.priority_targets
        entity.ignore_unprioritised = layer.ignore_unprioritised == true
    end
    local direction = 0
    if layer.turn_limited then
        local v = info.outward
        if layer.facing == "inward" then v = { x = -v.x, y = -v.y } end
        direction = lib.direction(v, math.min(layer.directions or 4, directions or 16))
        entity.direction = direction
    end
    local w, h = layer.tile_w or layer.size, layer.tile_h or layer.size
    if w ~= h and direction % 4 == 0 then
        if direction == 4 or direction == 12 then w, h = h, w end
        -- The reserved square's centre is on the grid for `size`; an even side
        -- needs a whole-number centre, an odd one a half.
        local pos = entity.position
        local function fit(c, side)
            local whole = c == math.floor(c)
            if (side % 2 == 0) ~= whole then return c - 0.5 end
            return c
        end
        entity.position = { x = fit(pos.x, w), y = fit(pos.y, h) }
    end
end

return lib
