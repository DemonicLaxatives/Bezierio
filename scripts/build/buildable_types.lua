local build_utils = require("scripts.build.utils")

local lib = {}

---@alias BuildableType
---| "wall"
---| "tile"
---| "electric-pole"
---| "electric-turret"
---| "straight-rail"
---| "roboport"

---@class BaseBuildable
---@field idx integer
---@field priority integer
---@field placed_by string
---@field prototype LuaEntityPrototype|LuaTilePrototype
---@field quality LuaQualityPrototype
---@field size integer
---@field offset integer
---@field type BuildableType

---@param params table<string, any>
---@return BaseBuildable
function lib.constructBaseBuildable(params)
    local params_copy = {}
    params_copy.idx = params.idx
    params_copy.priority = 0
    params_copy.placed_by = params.placed_by
    params_copy.prototype = params.prototype
    params_copy.quality = params.quality
    params_copy.size = build_utils.getPrototypeSize(params_copy.prototype)
    if params.offset then
        params_copy.offset = params.offset
    else
        params_copy.offset = 0
    end
    params_copy.type = params.type
    return params_copy
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
    prototype = nil,
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

---@param params table<string, any>
---@return Wall
function lib.constructWall(params)
    ---@class Wall : BaseBuildable
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

---@param params table<string, any>
---@return Tile
function lib.constructTile(params)
    ---@class Tile : BaseBuildable
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

---@param params table<string, any>
---@return ElectricPole
function lib.constructElectricPole(params)
    ---@class ElectricPole : BaseBuildable
    local self = lib.constructBaseBuildable(params)
    self.priority = 10
    self.wire_distance = self.prototype.get_max_circuit_wire_distance(self.quality)
    self.spacing = self.wire_distance
    self.smart_placement = false
    self.connect_with_circuit_wires = false
    self.reach = self.prototype.get_supply_area_distance(self.quality)
    return self
end

---@class ElectricTurret : BaseBuildable
---@field type "electric-turret"
---@field spacing integer

---@param params table<string, any>
---@return ElectricTurret
function lib.constructElectricTurret(params)
    ---@class ElectricTurret : BaseBuildable
    local self = lib.constructBaseBuildable(params)
    self.priority = 50
    self.spacing = self.size
    return self
end

---@class Rail : BaseBuildable
---@field type "straight-rail"
---@field direction_of_travel integer
---@field signal_spacing integer

---@param params table<string, any>
---@return Rail
function lib.constructRail(params)
    ---@class Rail : BaseBuildable
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

---@param params table<string, any>
---@return Roboport
function lib.constructRoboport(params)
    ---@class Roboport : BaseBuildable
    local self = lib.constructBaseBuildable(params)
    self.priority = 20
    self.logistic_radius = self.prototype.logistic_radius
    self.spacing = self.logistic_radius
    return self
end

---@alias Buildable Wall|Tile|ElectricPole|ElectricTurret|Rail|Roboport|NilBuildable

---@param params table<string, any>
---@return Buildable
function lib.constructBuildable(params)
    local type = params.prototype.type
    if type == "wall" then
        return lib.constructWall(params)
    elseif type == "tile" then
        ---@diagnostic disable-next-line
        return lib.constructTile(params)
    elseif type == "electric-pole" then
        return lib.constructElectricPole(params)
    elseif type == "electric-turret" then
        return lib.constructElectricTurret(params)
    elseif type == "straight-rail" then
        return lib.constructRail(params)
    elseif type == "roboport" then
        return lib.constructRoboport(params)
    else
        error("Unsupported entity type: "..type)
    end
end

return lib