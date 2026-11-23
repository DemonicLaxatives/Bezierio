--- Marks on the map for the entities a build leaves unpowered or unfed: a coloured
--- frame and an icon on each, for this player only. They are drawn a budgeted
--- number per tick (jobs.lua), and fade by themselves after the player's
--- `highlight_seconds` setting (0: they stay until hidden). Shown after a build,
--- and toggled by clicking the warning in the window. They belong to the plan whose
--- totals and warnings the window shows: an edit that drops the plan hides them.
---
--- The queue lives in controller.work.highlight, the render objects in
--- storage.sprites[i].highlight_<kind>.
local state = require("scripts.state")
local draw = require("scripts.draw")

local lib = {}

--- @alias HighlightKind "unpowered"|"unfed"

--- Work units per mark (two render objects).
lib.COST = 4

local COLORS = {
    unpowered = { r = 1, g = 0.85, b = 0, a = 1 },
    unfed = { r = 1, g = 0.35, b = 0.1, a = 1 },
}
local ICONS = {
    unpowered = "utility/electricity_icon_unplugged",
    ammo = "utility/ammo_icon",
    fluid = "utility/fluid_icon",
}

--- @class HighlightQueue
--- @field items {kind: HighlightKind, gen: integer, mark: PlanMark}[]
--- @field cursor integer
--- @field surface integer      # surface index
--- @field ttl integer|nil      # ticks; nil: until hidden
--- @field gen table<HighlightKind, integer>  # current generation per kind (older items are dropped)

--- @param kind HighlightKind
local function cache_key(kind) return "highlight_" .. kind end

--- @param player LuaPlayer
--- @return integer|nil
local function ttl(player)
    local seconds = state.setting(player.index, "highlight_seconds") --[[@as integer]]
    return seconds > 0 and seconds * 60 or nil
end

--- The plan's marks of a kind.
--- @param plan BuildPlan
--- @param kind HighlightKind
--- @return PlanMark[]
local function marks(plan, kind)
    return (kind == "unpowered" and plan.unpowered_at or plan.unfed_at) or {}
end

--- Whether a kind is shown (or still being drawn).
--- @param player LuaPlayer
--- @param controller Controller
--- @param kind HighlightKind
--- @return boolean
function lib.showing(player, controller, kind)
    local queue = controller.work.highlight
    if queue and queue.gen[kind] then
        for i = queue.cursor, #queue.items do
            local item = queue.items[i]
            if item.kind == kind and item.gen == queue.gen[kind] then return true end
        end
    end
    local objects = state.sprites(player.index)[cache_key(kind)]
    if objects then
        for i = #objects, 1, -1 do
            if objects[i].valid then return true end
        end
    end
    return false
end

--- @param player LuaPlayer
--- @param controller Controller
--- @param kind HighlightKind
function lib.hide(player, controller, kind)
    local queue = controller.work.highlight
    if queue then queue.gen[kind] = nil end
    draw.delete_sprites(player, cache_key(kind))
end

--- Hide every mark (the plan they belong to is gone).
--- @param player LuaPlayer
--- @param controller Controller
function lib.hide_all(player, controller)
    for _, kind in ipairs({ "unpowered", "unfed" }) do lib.hide(player, controller, kind) end
    controller.work.highlight = nil
end

--- Mark the plan's entities of these kinds (replacing marks shown before).
--- @param player LuaPlayer
--- @param controller Controller
--- @param plan BuildPlan
--- @param kinds HighlightKind[]
--- @param surface LuaSurface
function lib.show(player, controller, plan, kinds, surface)
    local queue = controller.work.highlight
    if not queue or queue.surface ~= surface.index then
        if queue then for _, kind in ipairs({ "unpowered", "unfed" }) do lib.hide(player, controller, kind) end end
        queue = { items = {}, cursor = 1, surface = surface.index, gen = {} }
        controller.work.highlight = queue
    end
    queue.ttl = ttl(player)
    for _, kind in ipairs(kinds) do
        lib.hide(player, controller, kind)
        local gen = (queue.last_gen or 0) + 1
        queue.last_gen = gen
        queue.gen[kind] = gen
        for _, mark in ipairs(marks(plan, kind)) do
            queue.items[#queue.items + 1] = { kind = kind, gen = gen, mark = mark }
        end
    end
end

--- Show the kind if hidden, hide it if shown (the warning was clicked).
--- @param player LuaPlayer
--- @param controller Controller
--- @param plan BuildPlan
--- @param kind HighlightKind
function lib.toggle(player, controller, plan, kind)
    if lib.showing(player, controller, kind) then
        lib.hide(player, controller, kind)
    else
        lib.show(player, controller, plan, { kind }, player.surface)
    end
end

--- Draw queued marks, up to the budget.
--- @param player LuaPlayer
--- @param controller Controller
--- @param budget number
--- @return number used
function lib.step(player, controller, budget)
    local queue = controller.work.highlight
    if not queue then return 0 end
    local surface = game.get_surface(queue.surface)
    local used = 0
    local sprites = state.sprites(player.index)
    while surface and queue.items[queue.cursor] and used < budget do
        local item = queue.items[queue.cursor]
        queue.cursor = queue.cursor + 1
        if queue.gen[item.kind] == item.gen then
            local key = cache_key(item.kind)
            sprites[key] = sprites[key] or {}
            local m, half = item.mark, item.mark.size / 2
            local common = { surface = surface, players = { player.index }, time_to_live = queue.ttl }
            local frame = { color = COLORS[item.kind], width = 3, filled = false,
                left_top = { x = m.x - half, y = m.y - half }, right_bottom = { x = m.x + half, y = m.y + half } }
            local icon = { sprite = ICONS[m.icon or item.kind], target = { x = m.x, y = m.y }, x_scale = 0.6, y_scale = 0.6 }
            for k, v in pairs(common) do frame[k], icon[k] = v, v end
            table.insert(sprites[key], rendering.draw_rectangle(frame))
            table.insert(sprites[key], rendering.draw_sprite(icon))
            used = used + lib.COST
        else
            used = used + 0.1
        end
    end
    if not (surface and queue.items[queue.cursor]) then
        -- Everything queued is drawn: keep only the generations, for showing().
        queue.items, queue.cursor = {}, 1
        if not next(queue.gen) then controller.work.highlight = nil end
    end
    return used
end

--- Whether marks are still waiting to be drawn.
--- @param controller Controller
--- @return boolean
function lib.pending(controller)
    local queue = controller.work.highlight
    return queue ~= nil and queue.items[queue.cursor] ~= nil
end

return lib
