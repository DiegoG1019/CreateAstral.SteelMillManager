---@param mixer number
---@param burner number
---@return heatPair
local function heatPair(mixer, burner)
    return { ["mixer"] = mixer, ["burner"] = burner }
end

---@type config
local c = {
    ["mixing"] = {
        {
            ["cutoff"] = 1,
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
            ["cutoff"] = 1,
            ["product"] = "tconstruct:molten_brass",
            ["recipe"] = {
                ["items"] = {},
                ["fluids"] = {
                    "tconstruct:molten_zinc",
                    "tconstruct:molten_copper",
                }
            },
            ["heatLevel"] = 1
        },
        {
            ["cutoff"] = 1,
            ["product"] = "tconstruct:molten_electrum",
            ["recipe"] = {
                ["items"] = {},
                ["fluids"] = {
                    "tconstruct:molten_silver",
                    "tconstruct:molten_gold",
                }
            },
            ["heatLevel"] = 1
        }
    },
    ["heatPairs"] = {
        heatPair(2, 5),
        heatPair(3, 6),
        heatPair(4, 7),
        heatPair(5, 8),
        heatPair(6, 9),
        heatPair(7, 10),
        heatPair(8, 11),
        heatPair(9, 12),
        heatPair(10, 13),
        heatPair(11, 14),
        heatPair(12, 15),
        heatPair(13, 16),
        heatPair(14, 17),
        heatPair(15, 18),
        heatPair(16, 19),
        heatPair(17, 20),
        heatPair(18, 21),
        heatPair(19, 4),
        heatPair(20, 3),
        heatPair(21, 2),
        heatPair(22, 1),
        heatPair(23, 0),
    }
}

return c;