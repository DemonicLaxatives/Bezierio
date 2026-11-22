local lib = {}

--- Turn off for release
--- @type boolean
lib.debug = true

--- @param message string
function lib.print(message)
    if lib.debug then
        game.print(message)
    end
end

--- @param data table
function lib.print_table(data)
    if lib.debug then
        game.print(serpent.block(data))
    end
end

--- @param input any
function lib.check_nil(input)
    if lib.debug then
        if input == nil then
            error("nil value detected")
        end
    end
end

return lib