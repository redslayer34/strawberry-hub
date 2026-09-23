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

function newWorld.enabled()
    return Settings.get("StackNewWorld") == true and Player.sea() == 1 and Player.level() >= 700
end

function newWorld.want()
    return Common.invoke("DressrosaQuestProgress", "Dressrosa") ~= nil
end

local function iceDoor()
    return Services.find(workspace, "Map.Ice.Door")
end

function newWorld.tick(mode)
    mode.target = nil
    local progress = Common.invoke("DressrosaQuestProgress", "Dressrosa")
    if progress == 0 then
        Movement.stop()
        if Common.every("TravelDressrosa", 10) then Services.invoke("TravelDressrosa") end
        return "Travelling to Sea 2"
    end

    local door = iceDoor()
    if door and door.CanCollide then
        if not Common.has("Key") then
            Common.goTo(World.DETECTIVE)
            if Common.near(World.DETECTIVE) and Common.every("Detective", 2) then
                Services.invoke("DressrosaQuestProgress", "Detective")
                Common.forget()
            end
            return "Getting the key from the detective"
        end
        Common.equip("Key")
        Common.goTo(door.CFrame)
        return "Opening the Ice door"
    end

    local admiral, inWorld = Enemies.findBoss("Ice Admiral")
    if admiral then return Common.fight(mode, admiral, inWorld) end
    Movement.stop()
    return "Waiting for Ice Admiral"
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

local function questTitle()
    local player = Services.player()
    local title = player and Services.find(player, "PlayerGui.Main.Quest.Container.QuestTitle.Title")
    return title and tostring(title.Text) or ""
end

local function bartilo(mode, progress)
    if progress == 0 then
        local title = questTitle()
        if title:find("Swan Pirates", 1, true) and title:find("50", 1, true) then
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

function thirdWorld.tick(mode)
    local step, progress = stage()
    if step == "bartilo" then return bartilo(mode, progress) end
    mode.target = nil

    if step == "trevor" then
        local names, tools = valuableFruits()
        local fruit = heldFruit(tools)
        if not fruit then
            local stored = storedFruit(names)
            if stored and Common.every("LoadFruit", 3) then Services.invoke("LoadFruit", stored) end
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
