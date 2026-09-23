--=============================================================================
-- FARMING OTHER: CHESTS, BERRIES, RAID LAW
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
