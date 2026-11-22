data:extend({
    {
        type = "custom-input",
        name = "bezierio-pointer",
        key_sequence = "mouse-button-1",
        consuming = "none"
    }
})

for i=1,9 do 
    data:extend({
        {
            type = "custom-input",
            name = "bezierio-pointer-"..i,
            key_sequence = "ALT + "..i,
            consuming = "game-only",
            action = "spawn-item",
            item_to_spawn = "bezierio-pointer-"..i
        }
    })
end

data:extend({
    {
        type = "custom-input",
        name = "bezierio-pointer-up",
        key_sequence = "ALT + mouse-wheel-up",
        consuming = "none"
    },
    {
        type = "custom-input",
        name = "bezierio-pointer-down",
        key_sequence = "ALT + mouse-wheel-down",
        consuming = "none"
    }
})