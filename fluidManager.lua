---@class inventoryPeripheral
---@field name string
---@field peripheral ccTweaked.peripheral.Inventory

---@class productRecipe
---@field items string[]
---@field fluids string[]

---@class configEntry
---@field product string
---@field cutoff number The percentage threshold of product in the tank at which production is cutoff, its constituents returned, and the mixer released 
---@field recipe productRecipe
---@field facility mixerPeripheral|nil

---@class tankPeripheralTank
---@field name string
---@field amount number
---@field capacity number

---@class mixerPeripheral
---@field name string
---@field peripheral ccTweaked.peripheral.FluidStorage|ccTweaked.peripheral.Inventory

---@class tankPeripheral
---@field name string
---@field peripheral ccTweaked.peripheral.FluidStorage
---@field getTank fun():tankPeripheralTank

settings.define("fluids.products", 
    { 
        ["description"] = "A table describing the metals to mix as well as their recipes",
        ["default"] = nil,
        ["type"] = "table"
    }
)

settings.define("fluids.minimumThreshold",
    {
        ["description"] = "The percentage (0.0 to 1.0) minimum amount of product that needs to be in a tank before it's eligible to be used to create more product",
        ["default"] = .5,
        ["type"] = "number"
    }
)

local minimumThreshold = 0.75

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

---@param name string
---@param wrapped ccTweaked.peripheral.FluidStorage|ccTweaked.peripheral.Inventory
---@return mixerPeripheral
local function createMixerObject(name, wrapped)
    return { ["name"] = name, ["peripheral"] = wrapped  }
end

---@param name string
---@param wrapped ccTweaked.peripheral.FluidStorage
---@return tankPeripheral
local function creatTankObject(name, wrapped)
    return { ["name"] = name, ["peripheral"] = wrapped, ["getTank"] = function() return getCreateModTankObject(wrapped) end  }
end

---@type { [string]: tankPeripheral }
local tanks = {} -- tanks[product] = tank peripheral

---@type mixerPeripheral[]
local freeMixers = {} -- freeMixers[..] = mixer peripheral

---@type tankPeripheral[]
local freeTanks = {} -- freeTanks[..] = tank peripheral

local foundry = nil -- peripheral.find("fluid_storage", "hephaestus:foundry_controller?")
local trash = nil -- peripheral.find("fluid_storage",) fluid trash can

---@type inventoryPeripheral
local itemStorage = nil -- peripheral.find("inventory", "create:") I don't remember what it's called

---@type configEntry[]
local config = nil
-- config[..] = { ["product"] = productName, ["cutoff"] = (0.0, 1.0), ["recipe"] = {"constituents"..} }

-- !!!!!!!!!!!!!!!!!!!!!!!!!! write the print statements for the script

---@param sourceMixer mixerPeripheral
---@param fluidInfo tankPeripheralTank
local function returnFluid(sourceMixer, fluidInfo)
    local tank = tanks[fluidInfo.name]
    
    if not tank then
        tank = table.remove(freeTanks)
        if not tank then
            printError("No available tanks to push liquid "..fluidInfo.name.. " into")
            return 
        end
        tanks[fluidInfo.name] = tank
    end

    sourceMixer.peripheral.pushFluid(tank.name, nil, fluidInfo.name)
end

---@param sourceMixer mixerPeripheral
local function emptyMixer(sourceMixer)
    print("Emptying mixer "..sourceMixer.name)
    for ii, tank in pairs(sourceMixer.peripheral.tanks()) do
        if not (tank and tank.name and tank.name ~= "minecraft:empty") then 
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
    return (tank.amount or 0) / (tank.capacity or 1)
end

---@param product configEntry
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

        if minimumThreshold <= getRelativeAmount(src.getTank()) then
            printError("Not enough of product "..v.." to mix product "..product.product)
            return false
        end

    end

    local mixer = table.remove(freeMixers)

    if not mixer then
        printError("No available mixers for more products")
        return false
    end
    
    product.facility = mixer
    print("Occupied mixer "..mixer.name.." for "..product.product)
    return true
end

---@param product configEntry
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

---@param product configEntry
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

---@param productInfo configEntry
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
        printError("Cutting off and relasing mixer for product "..productInfo.product)
        releaseMixerFrom(productInfo)
        return false
    end

    local mixer = productInfo.facility.peripheral
    print("Performing mixing routine for "..productInfo.product)

    local constituentsLiquids = {}
    for __, constituentLiquid in ipairs(productInfo.recipe.fluids) do
        constituentsLiquids[constituentLiquid] = 0
    end
    for _, tank in ipairs(mixer.tanks()) do -- we top off all the liquids and extract the product
        if tank.name == productInfo.product then
            print("Extracting resulting product "..productInfo.product)
            returnFluid(productInfo.facility, tank)
        end

        if not contains(productInfo.recipe.fluids, tank.name) then
            print("Extracting unused product "..productInfo.product)
            returnFluid(productInfo.facility, tank)
        end

        if getRelativeAmount(tank) < 1.0 then
            local src = tanks[tank.name]
            if not src or minimumThreshold > getRelativeAmount(src.getTank()) then 
                printError("Source product "..src.getTank().name.." is too low, releasing mixer for product "..productInfo.product)
                releaseMixerFrom(productInfo)
                return true
            end
            print("Pushing source product "..src.getTank().name.." to mixer to produce "..productInfo.product)
            src.peripheral.pushFluid(productInfo.facility.name, tank.capacity - tank.amount, tank.name)
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

    return true

    -- this function is responsible for filling, topping off, and extracting product. It's a reentrant function
    -- It's also responsible for cutting off production and releasing mixers
end

local function mixAllProducts()
    -- this function is responsible for occupying mixers, and performing mixing on all pending productions
    ---@type configEntry[]
    local notProduced = {}

    print("Performing product mixing routine for all products")
    
    for i,v in pairs(config) do
        if not v.facility then
            table.insert(notProduced, v)
        else
            mixProduct(v)
        end
    end

    if #freeMixers > 0 and #notProduced > 0 then
        for i,v in ipairs(notProduced) do
            occupyMixerFor(v)
            if #freeMixers <= 0 then break end
        end
    end

    print("Finished iteration of product mixing routine for all products")
end

local function reloadTankConfig()
    print("-------- Loading tank config")
    print("Reading mixer settings")
    minimumThreshold = settings.get("fluids.minimumTreshold", 0.75)

    config = settings.get("fluids.products")
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

        if not actualTank then 
            print("Found empty tank "..name)
            table.insert(freeTanks, peri)
        else
            print("Found tank "..name.." with "..peri.getTank().name)
            tanks[actualTank.name] = peri
        end

        return true
        elseif string.find(name, "create:basin", 1, true) then
            ---@diagnostic disable-next-line: param-type-mismatch
            local peri = createMixerObject(name, wrapped)
            print("Found product mixer")
            table.insert(freeMixers, peri)
        end
       return false
    end)

    assert(foundTanks, "Could not find any fluid tanks")

    assert(freeMixers and #freeMixers > 0, "Could not find any mixers")
    
    print("Emptying "..#freeMixers.." mixers")
    for i,v in ipairs(freeMixers) do
        emptyMixer(v)
    end

    print("Loaded tank config and scanned peripherals")
end

local lastReload = os.clock()

return function()
    reloadTankConfig()
    while true do
        if (os.clock() - lastReload) > 60 then reloadTankConfig(); lastReload = os.clock() end
        mixAllProducts()
        os.sleep(1)
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

