--=============================================================================
-- STACK: AUTO WORLD — the quests that open Sea 2 and Sea 3
--=============================================================================
--  Both follow the reference step by step, reading the quest progress from
--  the server each time (cached by Common.invoke).
--
--  New World (Sea 1, level 700): the detective gives the key, the key opens
--  the Ice door, the Ice Admiral dies, then TravelDressrosa.
--
--  Third World (Sea 2, level 1500): Bartilo's three stages (50 Swan
--  Pirates, Jeremy, the plates), Trevor wants a fruit worth 1M or more
--  (it is given away), Don Swan, rip_indra, then TravelZou.
--=============================================================================

local Common = require("Features.Stack.Common")
local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local Fruits = require("Features.Fruits")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local World = {}

World.DETECTIVE = Vector3.new(4852.2895507813, 5.651451587677, 718.53070068359)
World.BARTILO = Vector3.new(-456.28952, 73.0200958, 299.895966)
World.PLATES = Vector3.new(-1835.65, 10.4325, 1679.75)
World.TREVOR = Vector3.new(-339.79840087891, 331.86065673828, 643.83178710938)
World.INDRA_START = Vector3.new(-1926.78772, 12.1678171, 1739.80884)
World.FRUIT_PRICE = 1000000

---------------------------------------------------------------------------
-- New World
---------------------------------------------------------------------------

local newWorld = { name = "New World" }
World.newWorld = newWorld

-- Teddy's spots: the Ice Admiral's room, and the door when not loaded.
World.ADMIRAL_ROOM = Vector3.new(1212.38342, 21.3974915, -1429.6394)
World.ICE_DOOR = Vector3.new(1288.73328, 35.8959961, -1361.06274)

function newWorld.enabled()
    return Settings.get("StackNewWorld") == true and Player.sea() == 1 and Player.level() >= 700
end

local function iceDoor()
    return Services.find(workspace, "Map.Ice.Door")
end

-- The quest's progress, Teddy's way: DressrosaQuestProgress with no
-- argument answers a table (UsedKey, KilledIceBoss...). Older servers
-- answered a number to ("Dressrosa"), 0 once the Ice Admiral was dead:
-- read as { KilledIceBoss = true }. Always a table.
function newWorld.progress()
    local answer = Common.invoke("DressrosaQuestProgress")
    local progress = {}
    if type(answer) == "table" then
        for key, value in pairs(answer) do progress[key] = value end
    elseif Common.invoke("DressrosaQuestProgress", "Dressrosa") == 0 then
        progress.KilledIceBoss = true
    end
    local door = iceDoor()
    if door and (not door.CanCollide or door.Transparency == 1) then progress.UsedKey = true end
    return progress
end

-- At the Ice Admiral's room and no admiral: waiting is not a job, the farm
-- goes on (and with a hop allowed, another server: "Hop Find Ice Admiral").
-- Found empty, the room is looked at again only after ADMIRAL_RECHECK
-- seconds (no flying back and forth between the farm and the room).
World.ADMIRAL_RECHECK = 120
local emptyUntil = nil

local function waitingForAdmiral(progress)
    if progress.KilledIceBoss or not progress.UsedKey then return false end
    if Enemies.findBoss("Ice Admiral") then
        emptyUntil = nil
        return false
    end
    if emptyUntil and os.clock() < emptyUntil then return true end
    if Player.distanceTo(World.ADMIRAL_ROOM) <= 300 then
        emptyUntil = os.clock() + World.ADMIRAL_RECHECK
        return true
    end
    return false
end

-- Test hook.
function World.resetNewWorld() emptyUntil = nil end

function newWorld.want()
    return not waitingForAdmiral(newWorld.progress())
end

function newWorld.hop()
    if newWorld.enabled() and waitingForAdmiral(newWorld.progress()) then return "no Ice Admiral" end
    return nil
end

function newWorld.tick(mode)
    mode.target = nil
    local progress = newWorld.progress()
    if progress.KilledIceBoss then
        Movement.stop()
        if Common.every("TravelDressrosa", 10) then
            Services.invoke("DressrosaQuestProgress", "Detective")
            Services.invoke("TravelDressrosa")
            Common.forget()
        end
        return "Travelling to Sea 2"
    end

    if not progress.UsedKey then
        if not Common.has("Key") then
            Common.goTo(World.DETECTIVE)
            if Common.every("Detective", 2) then
                -- Teddy asks from anywhere first, then at the detective.
                Services.invoke("DressrosaQuestProgress", "Detective")
                Common.forget()
            end
            return "Getting the key from the detective"
        end
        local door = iceDoor()
        local where = door and door.Position or World.ICE_DOOR
        local key = Common.equip("Key")
        Common.goTo(CFrame.new(where))
        if door and Common.near(where, 20) and Common.every("UseKey", 1) then
            Common.touch(door, key)
            Services.invoke("DressrosaQuestProgress", "UseKey")
            Common.forget()
        end
        return "Opening the Ice door"
    end

    local admiral, inWorld = Enemies.findBoss("Ice Admiral")
    if admiral then return Common.fight(mode, admiral, inWorld) end
    -- Going to his room loads him.
    Common.goTo(World.ADMIRAL_ROOM)
    return "Moving to the Ice Admiral's room"
end

---------------------------------------------------------------------------
-- Third World
---------------------------------------------------------------------------

local thirdWorld = { name = "Third World" }
World.thirdWorld = thirdWorld
local swanSearch = Fight.newSearch()

function thirdWorld.enabled()
    return Settings.get("StackThirdWorld") == true and Player.sea() == 2 and Player.level() >= 1500
end

-- Fruits Trevor accepts: worth FRUIT_PRICE or more. `names` maps the
-- storage name ("Leopard-Leopard") to its price, `tools` the tool names
-- ("Leopard Fruit").
local function valuableFruits()
    local list = Common.invoke("GetFruits", false)
    local names, tools = {}, {}
    if type(list) ~= "table" then return names, tools end
    for _, fruit in ipairs(list) do
        if type(fruit) == "table" and type(fruit.Name) == "string" and (tonumber(fruit.Price) or 0) >= World.FRUIT_PRICE then
            names[fruit.Name] = tonumber(fruit.Price)
            tools[(fruit.Name:match("^[^%-]+") or fruit.Name) .. " Fruit"] = true
        end
    end
    return names, tools
end

local function heldFruit(tools)
    local player = Services.player()
    for _, container in ipairs({ Player.character(), player and player:FindFirstChild("Backpack") }) do
        for _, child in ipairs(container and container:GetChildren() or {}) do
            if child:IsA("Tool") and tools[child.Name] then return child end
        end
    end
    return nil
end

-- The cheapest valuable fruit stored in the inventory.
local function storedFruit(names)
    local best, bestPrice
    for _, item in ipairs(Common.inventory()) do
        local price = item.type == "Blox Fruit" and names[item.name]
        if price and (not bestPrice or price < bestPrice) then best, bestPrice = item.name, price end
    end
    return best
end

-- What is left to do, from the server's answers.
local function stage()
    local bartilo = Common.invoke("BartiloQuestProgress", "Bartilo")
    if bartilo == nil then return nil end
    if bartilo ~= 3 then return "bartilo", bartilo end
    local trevor = Common.invoke("TalkTrevor", "1")
    if trevor ~= 0 then return "trevor" end
    local zquest = Common.invoke("ZQuestProgress", "Check")
    if not zquest then return "donswan" end
    if zquest == 0 then return "indra" end
    if zquest == 1 and Common.invoke("ZQuestProgress", "Zou") == 0 then return "travel" end
    return nil
end

-- Trevor's step with no fruit worth 1M to give: what the Kaitun buys or
-- hops for (Teddy's Swan Door Hop).
function World.needsTrevorFruit()
    if Player.sea() ~= 2 then return false end
    local step = stage()
    if step ~= "trevor" then return false end
    local names, tools = valuableFruits()
    return heldFruit(tools) == nil and storedFruit(names) == nil
end

-- The cheapest fruit worth 1M or more on sale, and its price.
function World.cheapestTrevorFruit()
    local list = Common.invoke("GetFruits", false)
    local best, bestPrice
    for _, fruit in ipairs(type(list) == "table" and list or {}) do
        local price = type(fruit) == "table" and tonumber(fruit.Price) or 0
        if fruit.OnSale and price >= World.FRUIT_PRICE and (not bestPrice or price < bestPrice) then
            best, bestPrice = fruit.Name, price
        end
    end
    return best, bestPrice
end

function thirdWorld.want()
    local step, progress = stage()
    if step == "trevor" then
        local names, tools = valuableFruits()
        return heldFruit(tools) ~= nil or storedFruit(names) ~= nil
    end
    if step == "donswan" then return Enemies.findBoss("Don Swan") ~= nil end
    -- Jeremy spawns on his own: until then the main farm goes on.
    if step == "bartilo" and progress == 1 then return Enemies.findBoss("Jeremy") ~= nil end
    return step ~= nil
end

local function bartilo(mode, progress)
    if progress == 0 then
        if Common.questHas("Swan Pirate", 50) then
            return "Bartilo: " .. Common.farm(mode, { "Swan Pirate" }, swanSearch)
        end
        mode.target = nil
        Common.goTo(World.BARTILO)
        if Common.near(World.BARTILO) and Common.every("BartiloQuest", 3) then
            Services.invoke("StartQuest", "BartiloQuest", 1)
            Common.forget()
        end
        return "Bartilo: taking the quest"
    end
    if progress == 1 then
        local jeremy, inWorld = Enemies.findBoss("Jeremy")
        if jeremy then return "Bartilo: " .. Common.fight(mode, jeremy, inWorld) end
        mode.target = nil
        Movement.stop()
        return "Bartilo: waiting for Jeremy"
    end

    -- Stage 2: step on the plates the game lights up.
    mode.target = nil
    if not Common.near(World.PLATES, 100) then
        Common.goTo(World.PLATES)
        return "Bartilo: going to the plates"
    end
    local plates = Services.find(workspace, "Map.Dressrosa.BartiloPlates")
    for index = 1, 8 do
        local plate = plates and plates:FindFirstChild("Plate" .. index)
        if plate and Common.colorName(plate) == "Sand yellow" then
            Common.goTo(plate.CFrame)
            Common.touch(plate)
            Common.forget()
            return "Bartilo: plate " .. index
        end
    end
    return "Bartilo: plates"
end

-- Bartilo's quest is the "Colosseum Quest": the Alchemist (Race V2)
-- answers nothing until it is done. Shared with Races/Upgrade.
-- The progress: 0 (Swan Pirates), 1 (Jeremy), 2 (plates), 3 done, or nil.
function World.bartiloProgress()
    return Common.invoke("BartiloQuestProgress", "Bartilo")
end

-- Jeremy is not up: nothing to do on the quest for now.
function World.bartiloWaiting()
    return World.bartiloProgress() == 1 and Enemies.findBoss("Jeremy") == nil
end

World.bartilo = bartilo

function thirdWorld.tick(mode)
    local step, progress = stage()
    if step == "bartilo" then return bartilo(mode, progress) end
    mode.target = nil

    if step == "trevor" then
        local names, tools = valuableFruits()
        local fruit = heldFruit(tools)
        if not fruit then
            local stored = storedFruit(names)
            if stored and Common.every("LoadFruit", 3) then
                Fruits.keep(stored, 120)
                Services.invoke("LoadFruit", stored)
            end
            Movement.stop()
            return "Trevor: taking a fruit out of the inventory"
        end
        Common.goTo(World.TREVOR)
        if Common.near(World.TREVOR, 5) and Common.every("Trevor", 3) then
            Common.equip(fruit.Name)
            Services.invoke("TalkTrevor", "1")
            Services.invoke("TalkTrevor", "2")
            Services.invoke("TalkTrevor", "3")
            Common.forget()
        end
        return "Trevor: giving " .. fruit.Name
    end

    if step == "donswan" then
        local swan, inWorld = Enemies.findBoss("Don Swan")
        if swan then return "Don Swan: " .. Common.fight(mode, swan, inWorld) end
        Movement.stop()
        return "Waiting for Don Swan"
    end

    if step == "indra" then
        local island = Services.find(workspace, "Map.IndraIsland.Part")
        local farFromIsland = not island or Player.distanceTo(island.Position) > 1000
        local indra = Enemies.nearest("rip_indra")
        if indra then return "rip_indra: " .. Common.fight(mode, indra, true) end
        if farFromIsland then
            Common.goTo(World.INDRA_START)
            if Common.near(World.INDRA_START, 5) and Common.every("ZQuestBegin", 3) then
                Services.invoke("ZQuestProgress", "Begin")
                Common.forget()
            end
            return "Starting the rip_indra fight"
        end
        Movement.stop()
        return "Waiting for rip_indra"
    end

    if step == "travel" then
        Movement.stop()
        if Common.every("TravelZou", 10) then Services.invoke("TravelZou") end
        return "Travelling to Sea 3"
    end
    Movement.stop()
    return "Done"
end

function World.reset()
    swanSearch:reset()
end

return World
