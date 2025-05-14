---@type configEntry[]
local c = {
    {
        ["cutoff"] = .5,
        ["product"] = "tconstruct:molten_rose_gold",
        ["recipe"] = {
            ["items"] = {},
            ["fluids"] = {
                "tconstruct:molten_gold",
                "tconstruct:molten_copper",
            }
        }
    },
    {
        ["cutoff"] = .8,
        ["product"] = "tconstruct:molten_brass",
        ["recipe"] = {
            ["items"] = {},
            ["fluids"] = {
                "tconstruct:molten_zinc",
                "tconstruct:molten_copper",
            }
        }
    }
}

return c;