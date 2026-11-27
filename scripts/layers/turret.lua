local common = require("scripts.layers.common")
local feeds = require("scripts.build.feeds")

--- Ammo, fluid and artillery turrets, spaced along the middle of their band.
--- Turrets that can't turn all the way round (flamethrower, railgun) face outward
--- or inward; ammo turrets can request ammo (an insert plan on the ghost, or loaded
--- straight away when building instantly) and get an inserter feeding them from a
--- belt layer; fluid turrets can be piped to a pipe layer (build/feeds.lua).
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
        common.priority_targets,
        common.ignore_unprioritised,
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
            name = "inserter", widget = "item", default = nil,
            item_filters = { { filter = "place-result", elem_filters = { { filter = "type", type = "inserter" } } } },
            visible_if = function(layer) return layer.ammo_inventory ~= nil end,
            valid = function(layer, value)
                if not prototypes then return true end
                local item = prototypes.item[value]
                return item ~= nil and item.place_result ~= nil and item.place_result.type == "inserter"
            end,
        },
        {
            name = "pipe_feed", widget = "checkbox", default = false,
            visible_if = function(layer) return layer.fluid_ports ~= nil end,
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
        -- Fluid connections, facing north (fluid turrets).
        layer.fluid_ports = nil
        if prototype.type == "fluid-turret" then
            local ports = {}
            for _, box in ipairs(prototype.fluidbox_prototypes or {}) do
                for _, connection in ipairs(box.pipe_connections or {}) do
                    local p = connection.positions and connection.positions[1]
                    if p and connection.connection_type == "normal" then
                        ports[#ports + 1] = { x = p.x or p[1], y = p.y or p[2], direction = connection.direction }
                    end
                end
            end
            if #ports > 0 then layer.fluid_ports = ports end
        end
        -- Where an inserter can drop into it: its collision box, facing north.
        local box = prototype.collision_box
        layer.turret_box = box and {
            left = box.left_top.x or box.left_top[1], top = box.left_top.y or box.left_top[2],
            right = box.right_bottom.x or box.right_bottom[1], bottom = box.right_bottom.y or box.right_bottom[2],
        } or nil
        -- The chosen inserter's reach, facing north (pickup side).
        layer.inserter_name, layer.inserter_pickup, layer.inserter_drop, layer.inserter_power = nil, nil, nil, nil
        local item = layer.inserter and prototypes.item[layer.inserter]
        local inserter = item and item.place_result
        if inserter and inserter.type == "inserter" then
            layer.inserter_name = inserter.name
            local p, d = inserter.inserter_pickup_position, inserter.inserter_drop_position
            layer.inserter_pickup = { x = p.x or p[1], y = p.y or p[2] }
            layer.inserter_drop = { x = d.x or d[1], y = d.y or d[2] }
            layer.inserter_power = inserter.electric_energy_source_prototype ~= nil or nil
        end
    end,
    --- @param layer Layer
    --- @param entity PlannedEntity
    --- @param info PlacementInfo
    decorate = function(layer, entity, info)
        common.decorate_turret(layer, entity, info)
        if layer.ammo and layer.ammo_inventory then
            entity.ammo = { name = layer.ammo, quality = "normal", count = layer.ammo_count or 10, inventory = layer.ammo_inventory }
        end
    end,
    --- Whether the turret gets an inserter or a pipe stub.
    --- @param layer Layer
    --- @return boolean
    wants_feed = function(layer)
        return (layer.inserter_name ~= nil and layer.ammo_inventory ~= nil) or (layer.pipe_feed == true and layer.fluid_ports ~= nil)
    end,
    --- Whether its feed would fit with the turret at this spot.
    --- @param layer Layer
    --- @param entity PlannedEntity
    --- @param ctx FeedContext
    --- @return boolean
    can_attach = function(layer, entity, ctx)
        if layer.inserter_name and layer.ammo_inventory then
            return feeds.inserter_spot(ctx, entity, { pickup = layer.inserter_pickup, drop = layer.inserter_drop, box = layer.turret_box }) ~= nil
        elseif layer.pipe_feed and layer.fluid_ports then
            return feeds.pipe_stub(ctx, feeds.fluid_targets(entity, layer.fluid_ports)) ~= nil
        end
        return true
    end,
    --- After the turret is placed: its inserter or pipe stub.
    --- @param layer Layer
    --- @param entity PlannedEntity
    --- @param ctx FeedContext
    attach = function(layer, entity, ctx)
        if layer.inserter_name and layer.ammo_inventory then
            local spot = feeds.inserter_spot(ctx, entity, { pickup = layer.inserter_pickup, drop = layer.inserter_drop, box = layer.turret_box })
            if spot then
                ctx.add({ name = layer.inserter_name, x = spot.x, y = spot.y, direction = spot.direction, power = layer.inserter_power, item = layer.inserter })
            else
                ctx.unfed(entity, "ammo")
            end
        elseif layer.pipe_feed and layer.fluid_ports then
            local stub = feeds.pipe_stub(ctx, feeds.fluid_targets(entity, layer.fluid_ports))
            if stub then
                for _, c in ipairs(stub) do ctx.add_pipe(c.x, c.y) end
            else
                ctx.unfed(entity, "fluid")
            end
        end
    end,
}
