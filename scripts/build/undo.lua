--- Keeps all actions of one build in a single undo item, although the build is
--- spread over many ticks and the player may do other things in between.
---
--- Undo items are addressed by position from the top of the stack (1 = latest), so
--- the job remembers how many items there were right after it created its own; any
--- items the player adds later push it down by that many.
local lib = {}

--- @class UndoTracking
--- @field count integer|nil    # stack size right after our item was created
--- @field before integer|nil   # stack size before an action that may create it

--- `undo_index` to pass with the next action.
--- @param tracking UndoTracking
--- @param player LuaPlayer
--- @return integer
function lib.index(tracking, player)
    local now = player.undo_redo_stack.get_undo_item_count()
    if tracking.count and now >= tracking.count then
        return now - tracking.count + 1
    end
    -- No item yet (or it was undone): this action starts one.
    tracking.count = nil
    tracking.before = now
    return 0
end

--- Call after the action: notices when it created our item.
--- @param tracking UndoTracking
--- @param player LuaPlayer
function lib.after(tracking, player)
    if tracking.before then
        local now = player.undo_redo_stack.get_undo_item_count()
        if now > tracking.before then
            tracking.count = now
            tracking.before = nil
        end
    end
end

return lib
