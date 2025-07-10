---@class inventoryPeripheral
---@field name string
---@field peripheral ccTweaked.peripheral.Inventory

---@class productRecipe
---@field items string[]
---@field fluids string[]

---@class mixingEntry
---@field product string
---@field cutoff number The percentage threshold of product in the tank at which production is cutoff, its constituents returned, and the mixer released 
---@field recipe productRecipe
---@field facility mixerPeripheral|nil
---@field heatLevel number|nil The heat value. Only acceptable levels are: 0, 1 and 2. Ignored if fluids.heatEnabled is false or nil

---@class heatPair
---@field mixer number
---@field burner number

---@class config
---@field mixing mixingEntry[]
---@field heatPairs heatPair[]

---@class tankPeripheralTank
---@field name string
---@field amount number
---@field capacity number

---@class melterPeripheral
---@field name string
---@field type string
---@field peripheral ccTweaked.peripheral.FluidStorage|ccTweaked.peripheral.Inventory
---@field getTank fun():tankPeripheralTank

---@class mixerPeripheral
---@field name string
---@field type string
---@field burner burnerPeripheral|nil
---@field peripheral ccTweaked.peripheral.FluidStorage|ccTweaked.peripheral.Inventory

---@class tankPeripheral
---@field name string
---@field type string
---@field peripheral ccTweaked.peripheral.FluidStorage
---@field getTank fun():tankPeripheralTank

---@class foundryPeripheral
---@field name string
---@field type string
---@field peripheral ccTweaked.peripheral.FluidStorage

---@class burnerPeripheral
---@field name string
---@field type string
---@field peripheral ccTweaked.peripheral.FluidStorage
---@field refill fun(seedOilTank:ccTweaked.peripheral.FluidStorage)

settings.define("fluids.minimumThreshold",
    {
        ["description"] = "The percentage (0.0 to 1.0) minimum amount of product that needs to be in a tank before it's eligible to be used to create more product",
        ["default"] = .5,
        ["type"] = "number"
    }
)

local minimumThreshold

local foundryName = "tconstruct:scorched_drain"

print("Initializing Fluid Manager")

---@param table table
---@param check any
---@return boolean
local function contains(table, check)
    for i,v in ipairs(table) do
        if v == check then return true end
    end
    return false
end

local function getCreateModTankObject(fluidPeripheral)
    local t = fluidPeripheral.tanks()
    local actualTank = nil -- fluid_tanks can only ever have one tank
    for i,v in pairs(t) do
        actualTank = v
        break;
    end
    return actualTank
end

---@param burner burnerPeripheral
---@param seedOilTank ccTweaked.peripheral.FluidStorage
local function blazeBurnerRefill(burner, seedOilTank)
    seedOilTank.pushFluid(burner.name, nil, "createaddition:seed_oil")
end

---@param name string
---@param wrapped ccTweaked.peripheral.FluidStorage|ccTweaked.peripheral.Inventory
---@return mixerPeripheral
local function createMixerObject(name, wrapped)
    return { ["name"] = name, ["peripheral"] = wrapped, ["type"] = "mixer"  }
end

---@param name string
---@param wrapped ccTweaked.peripheral.FluidStorage
---@return tankPeripheral
local function creatTankObject(name, wrapped)
    return { ["name"] = name, ["peripheral"] = wrapped, ["type"] = "tank", ["getTank"] = function() return getCreateModTankObject(wrapped) end  }
end

---@param name string
---@param wrapped ccTweaked.peripheral.FluidStorage|ccTweaked.peripheral.Inventory
---@return melterPeripheral
local function createMelterObject(name, wrapped)
    return { ["name"] = name, ["peripheral"] = wrapped, ["type"] = "melter", ["getTank"] = function() return getCreateModTankObject(wrapped) end  }
end

---@param name string
---@param wrapped ccTweaked.peripheral.FluidStorage
---@return foundryPeripheral
local function createFoundryObject(name, wrapped)
    return { ["name"] = name, ["peripheral"] = wrapped, ["type"] = "foundry" }
end

---@param name string
---@param wrapped ccTweaked.peripheral.FluidStorage
---@return burnerPeripheral
local function createBurnerObject(name, wrapped)
    local burner = { ["name"] = name, ["peripheral"] = wrapped, ["type"] = "burner" }
    burner.refill = function(sourceTank) blazeBurnerRefill(burner, sourceTank) end
    return burner
end

---@type { [string]: tankPeripheral }
local tanks -- tanks[product] = tank peripheral

---@type mixerPeripheral[]
local freeMixers -- freeMixers[..] = mixer peripheral

---@type tankPeripheral[]
local freeTanks -- freeTanks[..] = tank peripheral

---@type melterPeripheral[]
local melters

---@type tankPeripheral[]
local excessDumpTanks

---@type foundryPeripheral
local foundry = nil -- peripheral.find("fluid_storage", "hephaestus:foundry_controller?")
local trash = nil -- peripheral.find("fluid_storage",) fluid trash can

---@type inventoryPeripheral
local itemStorage = nil -- peripheral.find("inventory", "create:") I don't remember what it's called

---@type config
local config = nil
-- config[..] = { ["product"] = productName, ["cutoff"] = (0.0, 1.0), ["recipe"] = {"constituents"..} }

-- !!!!!!!!!!!!!!!!!!!!!!!!!! write the print statements for the script

---@param source mixerPeripheral|melterPeripheral|foundryPeripheral
---@param fluidInfo tankPeripheralTank
local function returnFluid(source, fluidInfo)
    if not fluidInfo or fluidInfo.name == "minecraft:empty" then return end

    local tank = tanks[fluidInfo.name]
    
    if not tank then
        tank = table.remove(freeTanks)
        if not tank then
            printError("No available tanks to push liquid "..fluidInfo.name.. " into")
            return 
        end
        tanks[fluidInfo.name] = tank
    end

    source.peripheral.pushFluid(tank.name, nil, fluidInfo.name)
end

---@param sourceMixer mixerPeripheral
local function emptyMixer(sourceMixer)
    print("Emptying mixer "..sourceMixer.name)
    for ii, tank in pairs(sourceMixer.peripheral.tanks()) do
        if tank and tank.name and tank.name ~= "minecraft:empty" then
            returnFluid(sourceMixer, tank)
        end
    end

    if itemStorage then
        for slot, item in pairs(sourceMixer.peripheral.list()) do
            sourceMixer.peripheral.pushItems(itemStorage.name, slot, item.count)
        end
    end
end

---@param tank tankPeripheralTank
---@return number
local function getRelativeAmount(tank)
    --print("TANK CAPS", tank.amount, tank.capacity)
    return (tank.amount or 0) / (tank.capacity or 1)
end

---@param product mixingEntry
---@return boolean
local function occupyMixerFor(product)
    if product.facility then
        printError("Attempted to occupy a mixer for product ".. product.product .." but it already has a mixer assigned")
        return false
    end
    
    if #freeMixers <= 0 then
        printError("No available mixers for more products")
        return false
    end

    if not product.recipe then 
        printError("The product "..product.product.." does not have a recipe")
        return false
    end

    for i,v in ipairs(product.recipe.fluids) do

        local src = tanks[v]
        if not src then
            printError("The product "..product.product.." requires "..v.." to be created, but there is no tank registered with that fluid")
            return false
        end

        if minimumThreshold >= getRelativeAmount(src.getTank()) then
            printError("Not enough of product "..v.." to mix product "..product.product.." current amount: "..getRelativeAmount(src.getTank())..", expected at least: "..minimumThreshold)
            return false
        end

    end

    local mixer = table.remove(freeMixers)

    if not mixer then
        printError("No available mixers for more products")
        return false
    end
    
    product.facility = mixer
    emptyMixer(mixer)
    print("Occupied mixer "..mixer.name.." for "..product.product)
    return true
end

---@param product mixingEntry
---@return tankPeripheral|nil
local function getTankPeripheralFor(product) 
    local t = tanks[product.product]
    if t then return t end

    if #freeTanks <= 0 then
        printError("Not enough available tanks to occupy for product "..product.product)
        return nil
    end

    print("Attempting to occupy a new tank for product "..product.product)
    t = table.remove(freeTanks)
    if not t then
        printError("Could not occupy a tank for product "..product.product.. ", no available tanks")
        return nil
    end

    tanks[product.product] = t
    return t
end

---@param product mixingEntry
---@return boolean
local function releaseMixerFrom(product)
    if product.facility then
       printError("Attempted to release a mixer from  product "..product.product.." but it has no mixer assigned") 
       return false
    end

    emptyMixer(product.facility)
    table.insert(freeMixers, product.facility)
    print("Released mixer "..product.facility.name.." from product "..product.product)
    product.facility = nil
    return true
end

---@param productInfo mixingEntry
---@return boolean
local function mixProduct(productInfo)
    if not productInfo.facility then
        printError("Tried to mix product "..productInfo.product..", but it has no facility")
        return false
    end

    local productStorage = getTankPeripheralFor(productInfo)

    if not productStorage then
        printError("Could not get a storage tank for product "..productInfo.product..", releasing mixer")
        releaseMixerFrom(productInfo)
        return false
    end

    if getRelativeAmount(productStorage.getTank()) >= (productInfo.cutoff or .8) then
        printError("Cutting off and relasing mixer for product "..productInfo.product.." since it has "..getRelativeAmount(productStorage.getTank()).." and a cutoff threshold of "..(productInfo.cutoff or .8))
        releaseMixerFrom(productInfo)
        return false
    end

    local mixer = productInfo.facility.peripheral
    print("Performing mixing routine for "..productInfo.product)

    local constituentsLiquids = {}
    
    for __, constituentLiquid in ipairs(productInfo.recipe.fluids) do
        constituentsLiquids[constituentLiquid] = 1
    end

    for _, tank in ipairs(mixer.tanks()) do -- we top off all the liquids and extract the product
        if tank.name ~= "minecraft:empty" then
        
            if tank.name == productInfo.product then
                print("Extracting resulting product "..tank.name)
                returnFluid(productInfo.facility, tank)
    
            elseif type(constituentsLiquids[tank.name]) ~= "number" then
                print("Extracting unused product "..tank.name)
                returnFluid(productInfo.facility, tank)
    
            elseif getRelativeAmount(tank) < 1.0 then
                local src = tanks[tank.name]
                
                if not src then
                    printError("No source product "..tank.name.." available, releasing mixer for product "..productInfo.product)
                    releaseMixerFrom(productInfo)
                    return true
                end
                
                if minimumThreshold > getRelativeAmount(src.getTank()) then 
                    printError("Source product "..tank.name.." is too low, releasing mixer for product "..productInfo.product)
                    releaseMixerFrom(productInfo)
                    return true
                end
                
                print("Pushing source product "..src.getTank().name.." to mixer to produce "..productInfo.product)
                constituentsLiquids[tank.name] = 0
                src.peripheral.pushFluid(productInfo.facility.name, tank.capacity - tank.amount, tank.name)
            end
            
        end
    end

    for constituent, val in pairs(constituentsLiquids) do
        if val > 0 then
            local src = tanks[constituent]
            if not src then
                printError("No source product "..constituent.." available, releasing mixer for product "..productInfo.product)
                releaseMixerFrom(productInfo)
                return true
            end
            if minimumThreshold > getRelativeAmount(src.getTank()) then 
                printError("Source product "..constituent.." is too low, releasing mixer for product "..productInfo.product)
                releaseMixerFrom(productInfo)
                return true
            end
            print("Pushing source product "..src.getTank().name.." to mixer to produce "..productInfo.product)
            src.peripheral.pushFluid(productInfo.facility.name, 1000, constituent)
        end
    end

    local constituentsItems = {}
    for __, constituenItem in ipairs(productInfo.recipe.items) do
        constituentsItems[constituenItem] = 0
    end
    for slot, item in ipairs(mixer.list()) do -- we top off all the items
        local deets = mixer.getItemDetail(slot)
        if not deets then
            printError("Could not get item details for item["..slot.."]:"..item.name.." from mixer "..productInfo.facility.name)
            return false
        end
        
        if item.count < deets.maxCount then
            if itemStorage then
                for storageSlot, storageItem in ipairs(itemStorage.peripheral.list()) do
                    if storageItem.name == item.name then
                        local amn = deets.maxCount - item.count
                        if amn > storageItem.count then amn = storageItem.count end
                        print("Pushing "..amn.." items of '"..item.name.."' from storage into mixer")
                        itemStorage.peripheral.pushItems(productInfo.facility.name, storageSlot, amn)
                        break
                    end 
                end
            end
        end
    end

    if productInfo.heatLevel and productInfo.heatLevel > 0 then
        local seedOilTank = tanks["createaddition:seed_oil"]
        if not seedOilTank then
            printError("Could not find a seed oil tank to turn on heater to mix product "..productInfo.product)
            releaseMixerFrom(productInfo)
            return false
        end

        assert(productInfo.facility.burner)
        productInfo.facility.burner.refill(seedOilTank.peripheral)
    end

    return true

    -- this function is responsible for filling, topping off, and extracting product. It's a reentrant function
    -- It's also responsible for cutting off production and releasing mixers
end

---comment
---@param product tankPeripheral
local function dumpExcess(product)
    ---@type tankPeripheral
    
    local pt = product.getTank()

    local dump
    for i,v in ipairs(excessDumpTanks) do
        if v.getTank().name == "minecraft:empty" then
            dump = v
            break
        end
    end

    if not dump then
        printError("Could not find an empty dump tank to dump excess of product "..pt.name.." into")
        return false
    end

    dump.peripheral.pullFluid(product.name, pt.capacity * 0.2)
    print("Dumped off excess of product "..pt.name)
end

local function mixAllProducts()
    term.clear()
    term.setCursorPos(1,1)
    -- this function is responsible for occupying mixers, and performing mixing on all pending productions

    print("Attempting to dump off excess products")

    for i,v in pairs(tanks) do
        if i ~= "createaddition:seed_oil" and getRelativeAmount(v.getTank()) > .90 then
            dumpExcess(v)
        end
    end

    print("Attempting to extract from melters and foundry")

    for i,v in ipairs(melters) do
        returnFluid(v, v.getTank())
    end

    if foundry then
        for i,v in ipairs(foundry.peripheral.tanks()) do
            returnFluid(foundry, v)
        end
    end

    print("Performing product mixing routine for all products")
    
    for i,v in ipairs(config.mixing) do
        if not v.facility then
            occupyMixerFor(v)
        else
            mixProduct(v)
        end
    end

    print("Finished iteration of product mixing routine for all products")
end

---@param name string
---@return number
local function getId(name)
    local m = string.sub(string.match(name, "_%d+", 1), 2)
    local n = tonumber(m)
    assert(n, "Could not obtain a valid id from peripheral "..name)
    return n
end

local function reloadTankConfig()
    print("-------- Loading tank config")
    print("Reading mixer settings")
    minimumThreshold = settings.get("fluids.minimumThreshold", 0.5)

    melters = {}
    tanks = {}
    freeMixers = {}
    freeTanks = {}
    excessDumpTanks = {}
    config = loadfile("setup.lua")()

    local mixerIds = {}
    local burnerIds = {}

    local foundTanks = false
    assert(type(config) == "table", "config is unexpectedly nil or not a table")

    print("Finding peripherals")
    local _ = peripheral.find("fluid_storage", function (name, wrapped)
       if string.find(name, "create:fluid_tank", 1, true) then
        assert(type(wrapped) == "table")
        ---@diagnostic disable-next-line: param-type-mismatch
        local peri = creatTankObject(name, wrapped)
        foundTanks = true

        local actualTank = peri.getTank()

        if not actualTank or actualTank.name == "minecraft:empty" then 
            print("Found empty tank "..name)
            table.insert(freeTanks, peri)
        else
            print("Found tank "..name.." with "..actualTank.name)
            tanks[actualTank.name] = peri
        end

        return true
        elseif string.find(name, "create:basin", 1, true) then
            ---@diagnostic disable-next-line: param-type-mismatch
            local peri = createMixerObject(name, wrapped)
            table.insert(freeMixers, peri)
            mixerIds[getId(name)] = peri;
            
        elseif string.find(name, "ae2:sky_stone_tank", 1, true) then
            ---@diagnostic disable-next-line: param-type-mismatch
            local peri = creatTankObject(name, wrapped)
            table.insert(excessDumpTanks, peri)

        elseif string.find(name, "tconstruct:seared_melter", 1, true) then
            ---@diagnostic disable-next-line: param-type-mismatch
            local peri = createMelterObject(name, wrapped)
            table.insert(melters, peri)
        
        elseif string.find(name, "createaddition:liquid_blaze_burner", 1, true) then
            ---@diagnostic disable-next-line: param-type-mismatch
            local peri = createBurnerObject(name, wrapped)
            burnerIds[getId(name)] = peri;

        elseif string.find(name, foundryName, 1, true) then
            ---@diagnostic disable-next-line: param-type-mismatch
            local peri = createFoundryObject(name, wrapped)
            foundry = peri
        end

       return false
    end)

    assert(foundTanks, "Could not find any fluid tanks")

    assert(freeMixers and #freeMixers > 0, "Could not find any mixers")
    
    print("Emptying "..#freeMixers.." mixers")
    for i,v in ipairs(freeMixers) do
        emptyMixer(v)
    end

    if config.heatPairs then
        print("Pairing up mixers and burners")
        for i,hp in ipairs(config.heatPairs) do
            ---@type mixerPeripheral
            local m = mixerIds[hp.mixer]
    
            ---@type burnerPeripheral
            local b = burnerIds[hp.burner]
            if m and b then
                m.burner = b
                print("Paired mixer "..hp.mixer.." with burner "..hp.burner)
            end
        end

        for i,v in ipairs(freeMixers) do
            if not v.burner then error("Not all mixers have burners attached to them. Please make sure all mixers have burners or disable burners by setting heatPairs to nil") end;
        end
    end

    print("Loaded tank config and scanned peripherals")
end

local lastReload = os.clock()

return function()
    reloadTankConfig()
    while true do
        if (os.clock() - lastReload) > 60 then reloadTankConfig(); lastReload = os.clock() end
        mixAllProducts()
        os.sleep(3)
    end
end

-- Each mixer gets a product assigned to it
-- It takes from the tanks and deposits into the mixer UP TO A SINGLE BLOCK AT A TIME
-- Whenever it detects product, it tops it off and extracts the product into its respective tank

-- It first scans ALL tanks, empty tanks can be reassigned at the discretion of the software

-- remove ALL fluid filters from the foundry, the software is also responsible for them

-- Scanning the mixers would be more complicated, try to empty all liquids into their respective tanks first
-- For any undescribed liquids (water, lava) throw them into the trash
-- For any undescribed liquids that are not in the trash list, throw an error

