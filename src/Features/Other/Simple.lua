--=============================================================================
-- FARMING OTHER: ATTACK ALL, CHESTS, BERRIES, EASTER EGGS, RAID LAW
--=============================================================================
--  The short Farming Other modes of the reference, one Mode each.
--=============================================================================

local ChestHunt = require("Features.ChestHunt")
local Common = require("Features.Stack.Common")
local Enemies = require("Game.Enemies")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Simple = {}

local function tagged(tag)
    local ok, list = pcall(function() return Services.get("CollectionService"):GetTagged(tag) end)
    return ok and list or {}
end

---------------------------------------------------------------------------
-- Attack All Mobs: every mob of the world, bosses included
---------------------------------------------------------------------------

-- A mob of the world: it has a level and a fruit type (players' summons and
-- decorations do not), and is not the Spirit Tree.
function Simple.isWorldMob(model)
    return model.Name ~= "Spirit Tree" and model:GetAttribute("Level") ~= nil
        and model:GetAttribute("FruitType") ~= nil and Enemies.isAlive(model)
end

function Simple.worldMob()
    local here = Player.position()
    if not here then return nil end
    local best, bestDistance
    local enemies = workspace:FindFirstChild("Enemies")
    for _, model in ipairs(enemies and enemies:GetChildren() or {}) do
        if Simple.isWorldMob(model) then
            local distance = (model.HumanoidRootPart.Position - here).Magnitude
            if not bestDistance or distance < bestDistance then best, bestDistance = model, distance end
        end
    end
    if best then return best, true end
    for _, model in ipairs(Services.replicated():GetChildren()) do
        if Simple.isWorldMob(model) then return model, false end
    end
    return nil
end

Simple.attackAll = Mode({
    name = "Attack All",
    key = "OtherAttackAll",
    want = function() return Simple.worldMob() ~= nil end,
    idleStatus = "No mob around",
    tick = function(mode)
        local mob, inWorld = Simple.worldMob()
        if not mob then return "No mob around" end
        return Common.fight(mode, mob, inWorld)
    end,
})

---------------------------------------------------------------------------
-- Auto Chest: collect every chest, hop after N
---------------------------------------------------------------------------

local chestHunt = ChestHunt.new()
Simple.chestHunt = chestHunt

Simple.chest = Mode({
    name = "Auto Chest",
    key = "OtherChest",
    tick = function()
        local hopAfter = Settings.get("OtherChestHopAfter")
        if Settings.get("OtherChestHop") and chestHunt.collected >= hopAfter then
            Movement.stop()
            if Common.hop("chests collected", true) then chestHunt:reset() end
            return string.format("%d chests: hopping", chestHunt.collected)
        end
        local found = chestHunt:step(Settings.get("OtherChestTeleport") == true)
        local count = Settings.get("OtherChestHop")
            and string.format(" (%d/%d before hop)", chestHunt.collected, hopAfter)
            or string.format(" (%d collected)", chestHunt.collected)
        if found == "chest" then return "Collecting chests" .. count end
        if found == "searching" then return "Looking for chests" .. count end
        return "No chest found" .. count
    end,
})

---------------------------------------------------------------------------
-- Berries: bushes with a berry, picked through their prompt
---------------------------------------------------------------------------

-- A bush carries its berries as attributes: an empty bush has none.
local function hasBerry(bush)
    local ok, attributes = pcall(function() return bush:GetAttributes() end)
    return ok and type(attributes) == "table" and next(attributes) ~= nil
end

function Simple.berryBush()
    local here = Player.position()
    if not here then return nil end
    local best, bestDistance
    for _, bush in ipairs(tagged("BerryBush")) do
        if hasBerry(bush) then
            local pivot = Common.pivot(bush.Parent) or Common.pivot(bush)
            local distance = pivot and (pivot.Position - here).Magnitude or math.huge
            if not bestDistance or distance < bestDistance then best, bestDistance = bush, distance end
        end
    end
    return best
end

Simple.berry = Mode({
    name = "Berries",
    key = "OtherBerry",
    want = function() return Simple.berryBush() ~= nil end,
    idle = function()
        if Settings.get("OtherHopBerry") then Common.hop("no berry") end
    end,
    idleStatus = "Waiting for berries",
    tick = function()
        local bush = Simple.berryBush()
        if not bush then return "Waiting for berries" end
        local berry = bush:GetChildren()[1]
        if not berry then
            Common.goTo(Common.pivot(bush.Parent) or Common.pivot(bush))
            return "Going to a berry bush"
        end
        local pivot = Common.pivot(berry)
        Common.goTo(pivot)
        local prompt = berry:FindFirstChild("ProximityPrompt")
        if prompt and fireproximityprompt and Common.near(pivot.Position, 15) and Common.every("Berry", 0.5) then
            pcall(fireproximityprompt, prompt)
        end
        return "Picking a berry"
    end,
})

---------------------------------------------------------------------------
-- Easter eggs (event only)
---------------------------------------------------------------------------

function Simple.egg()
    local here = Player.position()
    if not here then return nil end
    local best, bestDistance, bestPlace
    for _, egg in ipairs(tagged("EasterEgg26")) do
        local place = egg:GetAttribute("CFrame")
        if typeof(place) == "CFrame" then
            local distance = (place.Position - here).Magnitude
            if not bestDistance or distance < bestDistance then best, bestDistance, bestPlace = egg, distance, place end
        end
    end
    return best, bestPlace
end

Simple.easter = Mode({
    name = "Easter Eggs",
    key = "OtherEaster",
    want = function() return Simple.egg() ~= nil end,
    idleStatus = "No egg (event over?)",
    tick = function()
        local _, place = Simple.egg()
        if not place then return "No egg" end
        Common.goTo(place)
        return "Collecting an egg"
    end,
})

function Simple.openEasterShop()
    local shop = Services.module("Controllers.UI.EventShop")
    if type(shop) == "table" and shop.Open then
        return pcall(shop.Open, shop, "Easter2026")
    end
    return false
end

---------------------------------------------------------------------------
-- Raid Law (Sea 2): buy a Microchip, summon Order, kill it
---------------------------------------------------------------------------

Simple.CHIP_PRICE = 1000   -- fragments

local function summonButton()
    return Services.find(workspace, "Map.CircleIsland.RaidSummon.Button.Main")
end

local function hasChip()
    return Common.has("Microchip") or Common.has("Core Brain")
end

Simple.law = Mode({
    name = "Raid Law",
    key = "OtherLaw",
    sea = 2,
    want = function()
        return Enemies.findBoss("Order") ~= nil or hasChip() or (Player.data("Fragments") or 0) >= Simple.CHIP_PRICE
    end,
    idleStatus = "Needs 1000 fragments for a Microchip",
    tick = function(mode)
        local order, inWorld = Enemies.findBoss("Order")
        if order then return Common.fight(mode, order, inWorld) end

        if hasChip() then
            local button = summonButton()
            if button then Common.goTo(button.CFrame) end
            local detector = button and button:FindFirstChild("ClickDetector")
            if detector and fireclickdetector and Common.every("LawSummon", 2) then
                pcall(fireclickdetector, detector)
            end
            return button and "Summoning Order" or "Summon button not loaded"
        end

        Movement.stop()
        if Common.every("LawChip", 3) then
            Services.invoke("BlackbeardReward", "Microchip", "2")
            Common.forget()
        end
        return "Buying a Microchip"
    end,
})

function Simple.reset()
    chestHunt:reset()
end

return Simple
