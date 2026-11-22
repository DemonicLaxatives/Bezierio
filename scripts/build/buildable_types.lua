local build_utils = require("scripts.build.utils")

--- Buildables are plain data stored in `storage`. They reference prototypes by
--- name only, so a save survives other mods removing/renaming prototypes.
local lib = {}

---@alias BuildableType
---| "nil"
---| "wall"
---| "tile"
---| "electric-pole"
---| "electric-turret"
---| "straight-rail"
---| "roboport"

---@class BaseBuildable
---@field idx integer          # layer index: 0 is centred on the curve, >0 one side, <0 the other
---@field priority integer     # higher priority layers claim contested grid cells first
---@field placed_by string|nil # item name
---@field name string|nil      # entity or tile prototype name
---@field quality string|nil   # quality name
---@field size integer         # footprint in tiles, also the layer's thickness for spaced entities
---@field offset integer       # gap (in tiles) between this layer and the one closer to layer 0
---@field type BuildableType

---@class BuildableParams
---@field idx integer
---@field placed_by string
---@field prototype LuaEntityPrototype|LuaTilePrototype
---@field quality string|nil
---@field offset integer|nil

---@param params BuildableParams
---@return BaseBuildable
function lib.constructBaseBuildable(params)
    return {
        idx = params.idx,
        priority = 0,
        placed_by = params.placed_by,
        name = params.prototype.name,
        quality = params.quality or "normal",
        size = build_utils.getPrototypeSize(params.prototype),
        offset = params.offset or 0,
        type = params.prototype.type,
    }
end

---@class NilBuildable : BaseBuildable
---@field type "nil"

---@param layer integer
---@return NilBuildable
function lib.contructNilBuildable(layer)
    return {
        idx = layer,
        priority = 0,
        placed_by = nil,
        name = nil,
        quality = nil,
        size = 1,
        offset = 0,
        type = "nil",
    }
end

---@class Wall : BaseBuildable
---@field type "wall"
---@field checkerboard integer
---@field radius integer

---@param params BuildableParams
---@return Wall
function lib.constructWall(params)
    ---@class Wall
    local self = lib.constructBaseBuildable(params)
    self.priority = 100
    self.checkerboard = 0
    self.radius = 1
    return self
end

---@class Tile : BaseBuildable
---@field type "tile"
---@field checkerboard integer
---@field radius integer

---@param params BuildableParams
---@return Tile
function lib.constructTile(params)
    ---@class Tile
    local self = lib.constructBaseBuildable(params)
    self.priority = 100
    self.checkerboard = 0
    self.radius = 1
    return self
end

---@class ElectricPole : BaseBuildable
---@field type "electric-pole"
---@field spacing integer
---@field smart_placement boolean
---@field wire_distance integer
---@field connect_with_circuit_wires boolean
---@field reach integer

---@param params BuildableParams
---@return ElectricPole
function lib.constructElectricPole(params)
    ---@class ElectricPole
    local self = lib.constructBaseBuildable(params)
    self.priority = 10
    self.wire_distance = math.floor(params.prototype.get_max_wire_distance(self.quality))
    -- Leave a tile of slack: positions get snapped to the grid after spacing.
    self.spacing = math.max(self.size, self.wire_distance - 1)
    self.smart_placement = false
    self.connect_with_circuit_wires = false
    self.reach = math.floor(params.prototype.get_supply_area_distance(self.quality) or 0)
    return self
end

---@class ElectricTurret : BaseBuildable
---@field type "electric-turret"
---@field spacing integer

---@param params BuildableParams
---@return ElectricTurret
function lib.constructElectricTurret(params)
    ---@class ElectricTurret
    local self = lib.constructBaseBuildable(params)
    self.priority = 50
    self.spacing = self.size
    return self
end

---@class Rail : BaseBuildable
---@field type "straight-rail"
---@field direction_of_travel integer
---@field signal_spacing integer

---@param params BuildableParams
---@return Rail
function lib.constructRail(params)
    ---@class Rail
    local self = lib.constructBaseBuildable(params)
    self.priority = 1
    self.direction_of_travel = 1
    self.signal_spacing = 1
    return self
end

---@class Roboport : BaseBuildable
---@field type "roboport"
---@field spacing integer
---@field logistic_radius integer

---@param params BuildableParams
---@return Roboport
function lib.constructRoboport(params)
    ---@class Roboport
    local self = lib.constructBaseBuildable(params)
    self.priority = 20
    self.logistic_radius = math.floor(params.prototype.logistic_radius or self.size)
    self.spacing = math.max(self.size, self.logistic_radius)
    return self
end

---@alias Buildable Wall|Tile|ElectricPole|ElectricTurret|Rail|Roboport|NilBuildable

local constructors = {
    ["wall"] = lib.constructWall,
    ["tile"] = lib.constructTile,
    ["electric-pole"] = lib.constructElectricPole,
    ["electric-turret"] = lib.constructElectricTurret,
    ["straight-rail"] = lib.constructRail,
    ["roboport"] = lib.constructRoboport,
}

---@param params BuildableParams
---@return Buildable
function lib.constructBuildable(params)
    local constructor = constructors[params.prototype.type]
    if not constructor then
        error("Unsupported entity type: " .. params.prototype.type)
    end
    return constructor(params)
end

--- Numeric fields the GUI is allowed to edit, with their valid range for a buildable.
--- @param buildable Buildable
--- @param field string
--- @return integer|nil min, integer|nil max
function lib.fieldRange(buildable, field)
    if field == "offset" then return 0, 10 end
    if field == "checkerboard" then return -10, 10 end
    if field == "radius" then return 1, 10 end
    if field == "direction_of_travel" then return -1, 1 end
    if field == "signal_spacing" then return 0, 6 end
    if field == "spacing" then
        if buildable.type == "electric-pole" then return buildable.size, buildable.wire_distance end
        if buildable.type == "roboport" then return buildable.size,
                math.max(buildable.size, 2 * buildable.logistic_radius) end
        return buildable.size, math.max(buildable.size, 10)
    end
    return nil, nil
end

return lib
