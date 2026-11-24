--- Keeps all actions of one build in a single undo item, although the build is
--- spread over many ticks and the player may do other things in between.
---
--- Undo items are addressed by position from the top of the stack (1 = latest),
--- and the stack holds at most 100: once full, a new item drops the oldest, so
--- its size says nothing. The build's item is found by a tag on its first action
--- instead (`bezierio_build`), looked for from where it was last seen (items the
--- player adds push it down). To tell a new item from the one that was on top, the
--- top one gets a `bezierio_seen` tag before an action that may start ours.
local lib = {}

--- @class UndoTracking
--- @field id string|nil       # our item's tag, once it exists
--- @field at integer|nil      # where it was last seen, from the top
--- @field starting boolean|nil  # the next action may start our item

local OURS, SEEN = "bezierio_build", "bezierio_seen"

--- `undo_index` to pass with the next action.
--- @param tracking UndoTracking
--- @param player LuaPlayer
--- @return integer
function lib.index(tracking, player)
    local stack = player.undo_redo_stack
    local n = stack.get_undo_item_count()
    if tracking.id then
        for i = math.min(tracking.at or 1, n), n do
            if i >= 1 and stack.get_undo_tag(i, 1, OURS) == tracking.id then
                tracking.at = i
                return i
            end
        end
        tracking.id, tracking.at = nil, nil -- undone (or dropped off the bottom)
    end
    -- No item yet: this action starts one, on top of what's there now.
    if n > 0 then stack.set_undo_tag(1, 1, SEEN, true) end
    tracking.starting = true
    return 0
end

--- Call after the action: notices when it started our item.
--- @param tracking UndoTracking
--- @param player LuaPlayer
function lib.after(tracking, player)
    if not tracking.starting then return end
    local stack = player.undo_redo_stack
    if stack.get_undo_item_count() > 0 and not stack.get_undo_tag(1, 1, SEEN) then
        tracking.id = game.tick .. ":" .. player.index
        tracking.at = 1
        tracking.starting = nil
        stack.set_undo_tag(1, 1, OURS, tracking.id)
    end
end

return lib
