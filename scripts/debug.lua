--- Development output. Set `lib.debug = false` for releases.
local lib = {}

--- @type boolean
lib.debug = true

--- @param message string
function lib.print(message)
    if lib.debug then
        game.print(message)
    end
end

return lib
