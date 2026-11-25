--- Which items a force has unlocked, for the item pickers: an item is unlocked when
--- a recipe the force has enabled makes it (research enables recipes). An item no
--- recipe makes (one a scenario hands out, say) counts as unlocked, since no
--- technology could unlock it.
local lib = {}

--- item name -> the recipes that make it. Built from the prototypes on first use,
--- so it's the same on every machine and kept out of storage.
--- @type table<string, string[]>|nil
local makers_cache = nil

--- @return table<string, string[]>
local function makers()
    if makers_cache then return makers_cache end
    local out = {}
    for name, recipe in pairs(prototypes.recipe) do
        for _, product in pairs(recipe.products) do
            if product.type == "item" then
                local list = out[product.name]
                if not list then
                    list = {}
                    out[product.name] = list
                end
                list[#list + 1] = name
            end
        end
    end
    makers_cache = out
    return out
end

--- @param force LuaForce
--- @param item string
--- @return boolean
function lib.is_unlocked(force, item)
    local recipes = makers()[item]
    if not recipes then return true end
    local enabled = force.recipes
    for _, name in ipairs(recipes) do
        local recipe = enabled[name]
        if recipe and recipe.enabled then return true end
    end
    return false
end

--- A picker filter offering the unlocked ones of `names`, plus `keep` (the current
--- choice, so a layer set up before, or from a preset, still shows what it holds).
--- @param force LuaForce
--- @param names string[]
--- @param keep string|nil
--- @return ItemPrototypeFilter[]
function lib.filter(force, names, keep)
    local out = {}
    for _, name in ipairs(names) do
        if name == keep or lib.is_unlocked(force, name) then out[#out + 1] = name end
    end
    return { { filter = "name", name = out } }
end

--- The names of the items matching some item prototype filters, sorted.
--- @param filters ItemPrototypeFilter[]
--- @return string[]
function lib.names(filters)
    local names = {}
    for name in pairs(prototypes.get_item_filtered(filters)) do names[#names + 1] = name end
    table.sort(names)
    return names
end

return lib
