local common = require("scripts.layers.common")

--- Ammo, fluid and artillery turrets, spaced along the middle of their band.
--- Turrets that can't turn all the way round (flamethrower, railgun) face outward
--- or inward; ammo turrets can request ammo (an insert plan on the ghost, or loaded
--- straight away when building instantly).
--- @type LayerType
return {
    name = "turret",
    entity_types = { "ammo-turret", "fluid-turret", "artillery-turret" },
    placement = "spaced",
    output = "entity",
    priority = 50,
    fields = {
        common.spacing(function() return 20 end),
        common.facing,
        {
            name = "ammo", widget = "item", default = nil,
            item_filters = { { filter = "type", type = "ammo" } },
            visible_if = function(layer) return layer.ammo_inventory ~= nil end,
            --- Only ammo this turret can fire.
            valid = function(layer, value)
                if not prototypes then return true end
                local item = prototypes.item[value]
                local category = item and item.type == "ammo" and item.ammo_category
                if not category then return false end
                for _, name in ipairs(layer.ammo_categories or {}) do
                    if name == category.name then return true end
                end
                return false
            end,
        },
        {
            name = "ammo_count", widget = "slider", min = 1,
            max = function(layer) return math.max(10, 5 * (layer.ammo_auto or 10)) end,
            default = function(layer) return layer.ammo_auto or 10 end,
            visible_if = function(layer) return layer.ammo_inventory ~= nil end,
        },
    },
    --- @param layer Layer
    --- @param prototype LuaEntityPrototype
    init = function(layer, prototype)
        common.init_turret(layer, prototype)
        local attack = prototype.attack_parameters
        if prototype.type == "ammo-turret" then
            layer.ammo_inventory = "turret_ammo"
        elseif prototype.type == "artillery-turret" then
            layer.ammo_inventory = "artillery_turret_ammo"
        else
            layer.ammo_inventory = nil
        end
        layer.ammo_categories = attack and attack.ammo_categories or {}
        layer.ammo_auto = prototype.automated_ammo_count or 10
    end,
    --- @param layer Layer
    --- @param entity PlannedEntity
    --- @param info PlacementInfo
    decorate = function(layer, entity, info)
        common.decorate_turret(layer, entity, info)
        if layer.ammo and layer.ammo_inventory then
            entity.ammo = { name = layer.ammo, quality = layer.ammo_quality or "normal", count = layer.ammo_count or 10, inventory = layer.ammo_inventory }
        end
    end,
}
