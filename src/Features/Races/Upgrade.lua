--=============================================================================
-- RACES: V2 / V3, CYBORG, GHOUL, DRACO V2 / V3
--=============================================================================
--  V2 (Alchemist, Sea 2, 500k Beli): three flowers (two lying around, the
--  third from Swan Pirates), then back to the Alchemist.
--  V3 (Wenlocktoad, 2M Beli), per race:
--    Human    kill Jeremy, Orbitus and Diamond
--    Mink     collect 30 chests
--    Cyborg   hold a fruit (a cheap stored one is taken out)
--    Fishman  a sea beast (Sea 2, by boat)
--    Skypiea  defeat a Skypiea player      Ghoul  defeat any player
--  Cyborg: the Law raid (optionally with a Fist of Darkness first), then the
--  Cyborg Trainer. Ghoul: 100 Ectoplasm + the Cursed Captain's Hellfire
--  Torch, then the Ectoplasm trade. Draco: the Dragon Wizard's ascension
--  (Fire Flowers for V2; a Terrorshark at sea for V3).
--=============================================================================

local Boat = require("Game.Boat")
local ChestHunt = require("Features.ChestHunt")
local Common = require("Features.Stack.Common")
local Duel = require("Features.Races.Duel")
local Enemies = require("Game.Enemies")
local Events = require("Features.Sea.Events")
local Fight = require("Features.Fight")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Raids = require("Features.Raids")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local World = require("Game.World")

local Upgrade = {}

Upgrade.ALCHEMIST_TURN_IN = Vector3.new(-2777.6001, 72.9661407, -3571.42285)
Upgrade.GHOUL_TRADE = Vector3.new(918.615234, 122.202454, 33454.3789)
Upgrade.HUMAN_BOSSES = { "Jeremy", "Orbitus", "Diamond" }
Upgrade.SHIP_MOBS = { "Ship Deckhand", "Ship Steward", "Ship Officer", "Ship Engineer" }
Upgrade.MINK_CHESTS = 30
Upgrade.CYBORG_CHESTS = 20
Upgrade.FISHMAN_SPOT = Vector3.new(753.0653686523438, 0, 6994.5146484375)

local search = Fight.newSearch()
local chests = ChestHunt.new()
local humanDone = {}
local humanTarget
local fistGiven = false

function Upgrade.version()
    local character = Player.character()
    if character and character:FindFirstChild("RaceTransformed") then return 4 end
    if Common.invoke("Wenlocktoad", "1") == -2 then return 3 end
    if Common.invoke("Alchemist", "1") == -2 then return 2 end
    return 1
end

---------------------------------------------------------------------------
-- V2 / V3
---------------------------------------------------------------------------

local function v2(mode)
    if (Player.data("Beli") or 0) < 500000 then
        Movement.stop()
        return "V2 needs 500k Beli"
    end
    local step = Common.invoke("Alchemist", "1")
    if step == 0 then
        Movement.stop()
        if Common.every("Alchemist2", 3) then Services.invoke("Alchemist", "2"); Common.forget() end
        return "Taking the Alchemist's quest"
    end
    if step == 1 then
        for index = 1, 2 do
            if not Common.has("Flower " .. index) then
                local flower = workspace:FindFirstChild("Flower" .. index)
                if flower then
                    Common.goTo(flower.CFrame)
                    Common.touch(flower)
                    return "Picking flower " .. index
                end
                Movement.stop()
                return "Waiting for flower " .. index
            end
        end
        return "Flower 3: " .. Common.farm(mode, { "Swan Pirate" }, search)
    end
    if step == 2 then
        Common.goTo(Upgrade.ALCHEMIST_TURN_IN)
        if Common.near(Upgrade.ALCHEMIST_TURN_IN, 8) and Common.every("Alchemist3", 3) then
            Services.invoke("Alchemist", "3")
            Common.forget()
        end
        return "Giving the flowers to the Alchemist"
    end
    Movement.stop()
    return "Talk to the Alchemist once"
end

local function holdsFruit()
    local player = Services.player()
    for _, container in ipairs({ Player.character(), player and player:FindFirstChild("Backpack") }) do
        for _, tool in ipairs(container and container:GetChildren() or {}) do
            if tool:IsA("Tool") and tool.Name:find("Fruit", 1, true) then return true end
        end
    end
    return false
end

local function v3(mode)
    local step = Common.invoke("Wenlocktoad", "1")
    if step == 0 or step == 2 then
        Movement.stop()
        if Common.every("Wenlocktoad", 3) then
            Services.invoke("Wenlocktoad", step == 0 and "2" or "3")
            Common.forget()
        end
        return step == 0 and "Taking the V3 quest" or "Turning in the V3 quest"
    end
    if step == -1 then
        Movement.stop()
        return "V3 needs 2M Beli"
    end
    local race = Player.data("Race")
    if race == "Human" then
        -- A boss that was being fought and is gone again counts as killed.
        if humanTarget and not Enemies.findBoss(humanTarget) then
            humanDone[humanTarget], humanTarget = true, nil
        end
        for _, name in ipairs(Upgrade.HUMAN_BOSSES) do
            if not humanDone[name] then
                local boss, inWorld = Enemies.findBoss(name)
                if boss then
                    if inWorld then humanTarget = name end
                    return "Human V3: " .. Common.fight(mode, boss, inWorld)
                end
            end
        end
        Movement.stop()
        return "Human V3: waiting for Jeremy, Orbitus or Diamond"
    end
    if race == "Mink" then
        chests:step(false)
        return string.format("Mink V3: chests %d/%d", chests.collected, Upgrade.MINK_CHESTS)
    end
    if race == "Cyborg" then
        Movement.stop()
        if not holdsFruit() then
            local fruit = Raids.cheapFruit()
            if fruit and Common.every("CyborgFruit", 3) then Services.invoke("LoadFruit", fruit) end
            return "Cyborg V3: taking a fruit out"
        end
        return "Cyborg V3: holding a fruit"
    end
    if race == "Fishman" then
        local beast = Events.anySeaBeast()
        if beast then return "Fishman V3: " .. Events.fight(mode, beast) end
        return "Fishman V3: " .. Events.patrol(Upgrade.FISHMAN_SPOT, "the sea beasts", "Brigade")
    end
    local accept = race == "Skypiea" and function(player)
        local data = player:FindFirstChild("Data")
        local playerRace = data and data:FindFirstChild("Race")
        return playerRace and playerRace.Value == "Skypiea"
    end or nil
    local target = Duel.pick(accept)
    if not target then
        Movement.stop()
        Common.hop("no player for the V3 quest")
        return race .. " V3: no target here"
    end
    return race .. " V3: " .. (Duel.fight(mode, target) or "next target")
end

Upgrade.v2v3 = Mode({
    name = "Race V2-V3",
    key = "RaceV2V3",
    want = function() return Upgrade.version() < 3 end,
    idleStatus = "Already V3",
    tick = function(mode)
        if not Common.travel(2) then return "Travelling to Sea 2" end
        if Upgrade.version() == 1 then return v2(mode) end
        return v3(mode)
    end,
    stop = function()
        search:reset()
        Boat.stop()
    end,
})

---------------------------------------------------------------------------
-- Cyborg
---------------------------------------------------------------------------

local function lawButton()
    return Services.find(workspace, "Map.CircleIsland.RaidSummon.Button.Main.ClickDetector")
end

local function pressLaw()
    local detector = lawButton()
    if detector and fireclickdetector and Common.every("CyborgButton", 1) then pcall(fireclickdetector, detector) end
end

Upgrade.cyborg = Mode({
    name = "Cyborg",
    key = "RaceCyborg",
    want = function() return Common.invoke("CyborgTrainer", "Check") ~= 2 end,
    idleStatus = "Cyborg bought",
    tick = function(mode)
        if not Common.travel(2) then return "Travelling to Sea 2" end
        if Common.invoke("CyborgTrainer", "Check") then
            Movement.stop()
            if Common.every("CyborgBuy", 3) then Services.invoke("CyborgTrainer", "Buy"); Common.forget() end
            return "Buying the Cyborg race"
        end
        if Settings.get("RaceCyborgFist") and not fistGiven and not Enemies.findBoss("Order") then
            if Common.has("Fist of Darkness") then
                pressLaw()
                if not Common.has("Fist of Darkness") then fistGiven = true end
                return "Giving the Fist of Darkness"
            end
            if Settings.get("RaceCyborgHop") and chests.collected >= Upgrade.CYBORG_CHESTS then
                Movement.stop()
                if Common.hop("chests for a fist", true) then chests:reset() end
                return "Chests done: hopping"
            end
            chests:step(false)
            return string.format("Chests for a Fist of Darkness (%d)", chests.collected)
        end
        if Common.has("Core Brain") or Common.has("Microchip") then
            pressLaw()
            Movement.stop()
            return "Pressing the Law button"
        end
        local order, inWorld = Enemies.findBoss("Order")
        if order then return Common.fight(mode, order, inWorld) end
        Movement.stop()
        if (Player.data("Fragments") or 0) >= 1000 and Common.every("CyborgChip", 3) then
            Services.invoke("BlackbeardReward", "Microchip", "2")
            Common.forget()
        end
        return "Buying a Microchip"
    end,
})

---------------------------------------------------------------------------
-- Ghoul
---------------------------------------------------------------------------

local function ghoulDone()
    return Player.data("Race") == "Ghoul" or Common.invoke("Ectoplasm", "BuyCheck", 4, true) == 2
end

Upgrade.ghoul = Mode({
    name = "Ghoul",
    key = "RaceGhoul",
    want = function() return not ghoulDone() end,
    idleStatus = "Ghoul done",
    tick = function(mode)
        if not Common.travel(2) then return "Travelling to Sea 2" end
        if Common.itemCount("Ectoplasm") < 100 then
            return string.format("Ectoplasm %d/100: %s", Common.itemCount("Ectoplasm"),
                Common.farm(mode, Upgrade.SHIP_MOBS, search))
        end
        if Common.has("Hellfire Torch") then
            Common.goTo(Upgrade.GHOUL_TRADE)
            if Common.near(Upgrade.GHOUL_TRADE, 8) and Common.every("GhoulTrade", 3) then
                Services.invoke("Ectoplasm", "BuyCheck", 4)
                Services.invoke("Ectoplasm", "Buy", 4)
                Common.forget()
            end
            return "Trading for the Ghoul race"
        end
        local captain, inWorld = Enemies.findBoss("Cursed Captain")
        if captain then return Common.fight(mode, captain, inWorld) end
        Movement.stop()
        if Settings.get("RaceGhoulHop") then Common.hop("no Cursed Captain") end
        return "Waiting for the Cursed Captain"
    end,
    stop = function() search:reset() end,
})

---------------------------------------------------------------------------
-- Draco V2 / V3
---------------------------------------------------------------------------

local dracoQuest, dracoShark

local function wizard(command, action)
    return Common.netInvoke("RF/InteractDragonQuest", { NPC = "Dragon Wizard", Command = command, Action = action })
end

local function fireFlower()
    local folder = workspace:FindFirstChild("FireFlowers")
    for _, flower in ipairs(folder and folder:GetChildren() or {}) do
        if flower:IsA("Model") then return flower end
    end
    return nil
end

local function atWizard()
    local npc = World.npcPosition("Dragon Wizard")
    if not npc then
        Movement.stop()
        return false, "Dragon Wizard not loaded (Hydra Island)"
    end
    Common.goTo(CFrame.new(npc) * CFrame.new(0, 4, 4))
    return Common.near(npc, 10), "Going to the Dragon Wizard"
end

Upgrade.draco = Mode({
    name = "Draco V2-V3",
    key = "RaceDraco",
    sea = 3,
    want = function() return Player.data("Race") == "Draco" and not Common.has("Primordial Reign") end,
    idleStatus = "Not Draco, or already V3",
    tick = function(mode)
        local state = type(dracoQuest) == "table" and dracoQuest.AvailableVQuest
        if state == "V2TurnInReady" or state == "V3TurnInReady" then
            local near, status = atWizard()
            if not near then return status end
            wizard("Ascension", "Complete")
            dracoQuest = nil
            return "Completing the ascension"
        end
        if state == "V2InProgress" then
            if Common.itemCount("Fire Flower") < 5 then
                local flower = fireFlower()
                local base = flower and (flower.PrimaryPart or flower:FindFirstChildWhichIsA("BasePart"))
                if base then
                    Common.goTo(base.CFrame)
                    local prompt = flower:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt and fireproximityprompt and Common.near(base.Position, 8) then pcall(fireproximityprompt, prompt, 1) end
                    return "Picking a Fire Flower"
                end
                return "Fire Flowers: " .. Common.farm(mode, { "Forest Pirate" }, search)
            end
            local near, status = atWizard()
            if not near then return status end
            wizard("Ascension", "Complete")
            dracoQuest = nil
            return "Bringing the Fire Flowers"
        end
        if state == "V3InProgress" then
            local shark = Events.find({ Terrorshark = true })
            -- A Terrorshark fought and gone: ask the wizard whether it counted.
            if dracoShark and dracoShark ~= shark and not Events.alive(dracoShark) then
                dracoShark, dracoQuest = nil, nil
                return "Draco V3: Terrorshark down"
            end
            dracoShark = shark or dracoShark
            if shark then return "Draco V3: " .. Events.fight(mode, shark) end
            return "Draco V3: " .. Events.patrol(Boat.ZONES["Zone 6"], "Zone 6")
        end
        local near, status = atWizard()
        if not near then return status end
        if Common.every("DracoSpeak", 2) then
            dracoQuest = wizard("Speak")
            local available = type(dracoQuest) == "table" and dracoQuest.AvailableVQuest
            if available == "V2" or available == "V3" then
                wizard("Ascension", "Begin")
                dracoQuest = wizard("Speak")
            end
        end
        return "Talking to the Dragon Wizard"
    end,
    stop = function()
        search:reset()
        Boat.stop()
    end,
})

function Upgrade.reset()
    search:reset()
    chests:reset()
    humanDone, humanTarget, fistGiven, dracoQuest, dracoShark = {}, nil, false, nil, nil
end

return Upgrade
