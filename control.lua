Curve = require "scripts.bezier_curve"
util = require "scripts.util"

local Event = require('__stdlib__/stdlib/event/event')
local Table = require('__stdlib__/stdlib/utils/table')
local Math = require('__stdlib__/stdlib/utils/math')

local to_vector = math2d.position.ensure_xy
local add = math2d.position.add
local sub = math2d.position.subtract
local scale = math2d.position.multiply_scalar
local norm = math2d.position.vector_length


function toboolean(v)
  return v ~= nil and v ~= false
end

function xor(a, b)
  return toboolean(a) ~= toboolean(b)
end

function TableConcat(t1,t2)
  for i=1,#t2 do
      t1[#t1+1] = t2[i]
  end
  return t1
end


function is_equal(vec1, vec2)
  if xor(not vec1, not vec2) then
    return false
  end
  vec1 = math2d.position.ensure_xy(vec1)
  vec2 = math2d.position.ensure_xy(vec2)

  return (vec1.x == vec2.x) and (vec1.y == vec2.y)
end

local Bezierio = {}
Bezierio.name = "curve-projector"

Bezierio.connectors = {
  ["connector_1"] = { name = "curve-projector-p1", position = { x = -1.5, y = 0 }, direction = 0 },
  ["connector_2"] = { name = "curve-projector-p2", position = { x = 1.5, y = 0 }, direction = 0 },
  ["controller"] = { name =  "curve-projector-controller", position = { x = 0, y = 0 }, direction = 0 },
}

function Bezierio.on_entity_created(event)
  local entity
  if event.entity and event.entity.valid then
    entity = event.entity
  end
  if event.created_entity and event.created_entity.valid then
    entity = event.created_entity
  end

  if entity and entity.name == Bezierio.name then

    curve_projector = {
      entity = entity,
      unit_number = entity.unit_number,
  
      reference_point = { x = 1.5, y = 0 },
      connectors = {},
      connector_activity = {},
  
      curve_params_changed = false,
      curve = {},
      build_params_changed = false,
      raster_curve = {},
    
      build_params = {
        build = false,
        thickness = 1,
        buildable = "stone-wall",
      },

      curve_params = {
        p1 = {0,0},
        p2 = {0,0},
        v1 = {0,0},
        v2 = {0,0},
      },

      inventory = {},
    
      draw = false,
      redraw = false,
      sprite_ids = {},
    }

    local operator = util.cardinal_direction_to_transform(curve_projector.entity.direction)

    for slot, connector_def in pairs(Bezierio.connectors) do
      local position = connector_def.position

      curve_projector.connectors[slot] = curve_projector.entity.surface.create_entity{
        name = connector_def.name,
        force = curve_projector.entity.force,
        position = add(curve_projector.entity.position, util.mat_dot_vect(operator, position)),
        direction = curve_projector.entity.direction,
      }

      curve_projector.connectors[slot].destructible = false
      curve_projector.connectors[slot].active = false
    end

    curve_projector.inventory = curve_projector.connectors["controller"].get_inventory(defines.inventory.chest)
    curve_projector.inventory.insert({ name = "blueprint" })
    curve_projector.inventory.insert({ name = "blueprint" })
    
    curve_projector.entity.rotatable = false
    global.curve_projectors[entity.unit_number] = curve_projector

  end
end

Event.register(defines.events.on_built_entity, Bezierio.on_entity_created)
Event.register(defines.events.on_robot_built_entity, Bezierio.on_entity_created)
Event.register(defines.events.script_raised_built, Bezierio.on_entity_created)
Event.register(defines.events.script_raised_revive, Bezierio.on_entity_created)

function destroy_sprites(ids)
  for _, id in pairs(ids) do
    if id then 
      rendering.destroy(id)
    end
  end
end

function Bezierio.on_entity_removed(event)
  local entity = event.entity
  if global.curve_projectors then
    if entity and entity.valid and entity.name == Bezierio.name then
      local curve_projector = global.curve_projectors[entity.unit_number]
      if curve_projector then
        for slot, connector in pairs(curve_projector.connectors) do
          connector.destroy()
        end
        if curve_projector.line_ids then
          destroy_sprites(curve_projector.sprite_ids)
        end
      end
    end
  end
end

Event.register(defines.events.on_entity_died, Bezierio.on_entity_removed)
Event.register(defines.events.on_robot_mined_entity, Bezierio.on_entity_removed)
Event.register(defines.events.on_player_mined_entity, Bezierio.on_entity_removed)
Event.register(defines.events.script_raised_destroy, Bezierio.on_entity_removed)

function make_signal_table(signals)
  local result = {item = {}, virtual = {}, fluid = {}}
  for _, signal in pairs(signals) do
    local type = signal.signal.type
    local name = signal.signal.name
    result[type][name] = signal.count
  end
  return result
end

function Bezierio.keep_inputs_updated()
  if global.curve_projectors then
    for _, curve_projector in pairs(global.curve_projectors) do
      if not curve_projector.entity.valid then
        Bezierio.on_entity_removed({entity = curve_projector.entity})
      else
        for slot, connector in pairs(curve_projector.connectors) do
          curve_projector.connector_activity[slot] = false

          local signals = connector.get_merged_signals()
          if signals then
            curve_projector.connector_activity[slot] = true
            signals = make_signal_table(signals)
            local virtual = signals["virtual"]
            local items = signals["item"]
            local values = {}

            if slot == "controller" then
              curve_projector.draw =  (virtual["signal-D"]  or 0) ~= 0
              values.build = (virtual["signal-B"]  or 0) ~= 0
              values.thickness = virtual["signal-T"] or 1
              local buildable = curve_projector.build_params.buildable
              local max_count = items[buildable] or -Math.MAXINT

              for item, count in pairs(items) do
                local item_prototype = game.item_prototypes[item]
                local place_result = item_prototype.place_result or item_prototype.place_as_tile_result
                if place_result then
                  if count > max_count then
                    max_count = count
                    if item ~= buildable then
                      buildable = item
                      curve_projector.build_params.buildable = buildable
                      curve_projector.build_params_changed = true
                    end
                  end
                end
              end
              
              if max_count == -Math.MAXINT and (curve_projector.build_params.buildable ~= "stone-wall") then
                curve_projector.build_params.buildable = "stone-wall"
                curve_projector.build_params_changed = true
              end

              for key, value in pairs(values) do
                if curve_projector.build_params[key] then
                  if curve_projector.build_params[key] == value then
                    goto continue
                  end
                end

                curve_projector.build_params[key] = value
                curve_projector.build_params_changed = true
                curve_projector.redraw = true
                ::continue::
              end
            end
        
            if slot == "connector_1" then
              values.p1 = {virtual["signal-X"] or 0, virtual["signal-Y"] or 0}
              values.v1 = {virtual["signal-U"] or 0, virtual["signal-V"] or 0}

            elseif slot == "connector_2" then
              values.p2 = {virtual["signal-X"] or 0, virtual["signal-Y"] or 0}
              values.v2 = {virtual["signal-U"] or 0, virtual["signal-V"] or 0}
            end

            if slot ~= "controller" then
              for key, value in pairs(values) do
                if curve_projector.curve_params[key] then
                  if util.is_equal(curve_projector.curve_params[key], value) then
                    goto continue
                  end
                end

                curve_projector.curve_params[key] = value
                curve_projector.build_params_changed = true
                curve_projector.curve_params_changed = true
                curve_projector.redraw = true
                ::continue::
              end
            end

          end
        end
      end
    end
  end
end

function Bezierio.on_60th_tick()
  if global.curve_projectors then
    for unit_number, curve_projector in pairs(global.curve_projectors) do
      if not curve_projector.entity.valid then
        Bezierio.on_entity_removed({entity = curve_projector.entity})
      else
        local connector_activity = curve_projector.connector_activity["connector_1"] and  curve_projector.connector_activity["connector_2"]
        local controller_activity = curve_projector.connector_activity["controller"]

        local p1 = curve_projector.curve_params.p1
        local p2 = curve_projector.curve_params.p2
        local v1 = curve_projector.curve_params.v1
        local v2 = curve_projector.curve_params.v2
        
        if connector_activity and curve_projector.curve_params_changed then
          curve_projector.curve = Curve.CalculateBezierCurve(p1, p2, v1, v2)
          curve_projector.curve_params_changed = false
          curve_projector.redraw = true
        end

        if curve_projector.redraw or not curve_projector.draw then
          if curve_projector.line_ids then 
            destroy_sprites(curve_projector.line_ids)
          end
          curve_projector.redraw = true
        end

        if curve_projector.redraw and curve_projector.draw then
          local curve = Table.deep_copy(curve_projector.curve)
          curve_projector.line_ids = Curve.DrawCurve(curve_projector, curve)
          TableConcat(curve_projector.line_ids, Curve.DrawVector(curve_projector, p1, v1))
          TableConcat(curve_projector.line_ids, Curve.DrawVector(curve_projector, p2, v2))
          curve_projector.curve_params_changed = false
          curve_projector.redraw = false
        end


        local build_bool = curve_projector.build_params.build 
        build_bool = build_bool and curve_projector.build_params_changed
        build_bool = build_bool and curve_projector.build_params.thickness
        build_bool = build_bool and #curve_projector.curve > 0
        build_bool = build_bool and curve_projector.connector_activity["controller"]

        if build_bool then
          local curve = Table.deep_copy(curve_projector.curve)
          Curve.BuildCurve(curve_projector, Curve.rasterize(curve))
          curve_projector.build_params_changed = false
        end

      end

    end
  end
end

Event.register(-60, Bezierio.on_60th_tick)
Event.register(-1 , Bezierio.keep_inputs_updated)

Event.on_init(function()
  global.curve_projectors = {}
end)

return Bezierio
