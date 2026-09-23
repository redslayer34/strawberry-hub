--=============================================================================
-- ITEMS: RAINBOW HAKI, YAMA, TUSHITA, TRUE TRIPLE KATANA, YORU MINI
--=============================================================================
--    Rainbow Haki  the Horned Man's five boss quests (HornedMan Bet)
--    Yama          30 Elite Hunters, then the sealed katana on Waterfall
--                  island: kill its Ghosts, click it
--    Tushita       while rip_indra is up, touch the Waterfall hitbox for the
--                  Holy Torch, light the 5 torches, then kill Longma
--    TTK           Oroshi, Saishi and Shizu to 300 mastery (bone mobs), then
--                  the Mysterious Man
--    Yoru Mini     rip_indra True Form: an Elite Hunter's God's Chalice (or
--                  chests), the haki pads, the summon, the fight
--=============================================================================

local ChestHunt = require("Features.ChestHunt")
local Common = require("Features.Stack.Common")
local Data = require("Game.Data")
local EliteHunter = require("Features.Stack.EliteHunter")
local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Summons = require("Features.Stack.Summons")
local World = require("Game.World")

local Swords = {}

Swords.RAINBOW_BOSSES = { "Stone", "Hydra Leader", "Kilo Admiral", "Captain Elephant", "Beautiful Pirate" }
Swords.WATERFALL = Vector3.new(5251.900390625, 17.18115234375, 453.6025390625)
Swords.TUSHITA_GATE = Vector3.new(5677.541015625, 28.533447265625, 357.9483642578125)
Swords.YAMA_ELITES = 30
Swords.TTK_SWORDS = { "Oroshi", "Saishi", "Shizu" }
Swords.TTK_MASTERY = 300

local boneSearch = Fight.newSearch()
local yoruChests = ChestHunt.new()

---------------------------------------------------------------------------
-- Rainbow Haki
---------------------------------------------------------------------------

local function rainbowBoss()
    local title = Common.questTitle()
    for _, boss in ipairs(Swords.RAINBOW_BOSSES) do
        if title:find(boss, 1, true) then return boss end
    end
    return nil
end

Swords.rainbow = Mode({
    name = "Rainbow Haki",
    key = "ItemRainbowHaki",
    sea = 3,
    want = function()
        if Common.invoke("HornedMan") == 1 then return false end
        local boss = rainbowBoss()
        return not boss or Enemies.findBoss(boss) ~= nil
    end,
    idleStatus = "Done, or waiting for the quest boss to spawn",
    tick = function(mode)
        local boss = rainbowBoss()
        if boss then
            local found, inWorld = Enemies.findBoss(boss)
            if found then return Common.fight(mode, found, inWorld) end
            Movement.stop()
            return "Waiting for " .. boss
        end
        local npc = World.npcPosition("Horned Man")
        if not npc then
            Movement.stop()
            return "Horned Man not loaded (Tiki Outpost)"
        end
        Common.goTo(npc)
        if Common.near(npc, 8) and Common.every("HornedManBet", 3) then
            Services.invoke("HornedMan", "Bet")
            Common.forget()
        end
        return "Asking the Horned Man for a quest"
    end,
})

---------------------------------------------------------------------------
-- Yama
---------------------------------------------------------------------------

Swords.yama = Mode({
    name = "Yama",
    key = "ItemYama",
    sea = 3,
    want = function()
        if Common.has("Yama") or Common.itemCount("Yama") > 0 then return false end
        local progress = tonumber(Common.invoke("EliteHunter", "Progress")) or 0
        return progress >= Swords.YAMA_ELITES or EliteHunter.find() ~= nil
    end,
    idleStatus = "Owned, or waiting for an Elite Hunter",
    tick = function(mode)
        local progress = tonumber(Common.invoke("EliteHunter", "Progress")) or 0
        if progress < Swords.YAMA_ELITES then
            local elite, inWorld = EliteHunter.find()
            if not elite then return "Waiting for an Elite Hunter" end
            return string.format("Elites %d/%d: %s", progress, Swords.YAMA_ELITES,
                EliteHunter.run(mode, elite, inWorld))
        end
        local katana = Services.find(workspace, "Map.Waterfall.SealedKatana")
        if not katana then
            Common.goTo(Swords.WATERFALL)
            return "Going to Waterfall island"
        end
        local pivot = Common.pivot(katana)
        if not Common.near(pivot.Position, 50) then
            Common.goTo(pivot)
            return "Going to the sealed katana"
        end
        local ghost = Enemies.nearest("Ghost")
        if ghost then return "Ghosts: " .. Common.fight(mode, ghost, true) end
        local detector = Services.find(katana, "Hitbox.ClickDetector")
        if detector and fireclickdetector and Common.every("YamaClick", 1) then pcall(fireclickdetector, detector) end
        return "Pulling the katana"
    end,
})

---------------------------------------------------------------------------
-- Tushita
---------------------------------------------------------------------------

local function tushitaHitbox()
    return Services.find(workspace, "Map.Waterfall.IslandModel")
        and workspace.Map.Waterfall.IslandModel:FindFirstChild("Hitbox", true)
end

local function tushitaProgress()
    local progress = Common.invoke("TushitaProgress")
    return type(progress) == "table" and progress or {}
end

Swords.tushita = Mode({
    name = "Tushita",
    key = "ItemTushita",
    sea = 3,
    want = function()
        if Common.has("Tushita") or Common.itemCount("Tushita") > 0 then return false end
        if tushitaProgress().OpenedDoor then return Enemies.findBoss("Longma") ~= nil end
        local hitbox = tushitaHitbox()
        return not hitbox or hitbox:FindFirstChild("TouchInterest") ~= nil or Common.has("Holy Torch")
    end,
    idleStatus = "Owned, or waiting for rip_indra / Longma",
    tick = function(mode)
        if tushitaProgress().OpenedDoor then
            local longma, inWorld = Enemies.findBoss("Longma")
            if longma then return Common.fight(mode, longma, inWorld) end
            Movement.stop()
            return "Waiting for Longma"
        end
        local hitbox = tushitaHitbox()
        if not hitbox then
            Common.goTo(Swords.TUSHITA_GATE)
            return "Going to the Tushita gate"
        end
        if Common.has("Holy Torch") then
            Common.equip("Holy Torch")
            Movement.stop()
            if Common.every("TushitaTorches", 3) then
                for torch = 1, 5 do Services.invoke("TushitaProgress", "Torch", torch) end
                Common.forget()
            end
            return "Lighting the torches"
        end
        Common.goTo(hitbox.CFrame)
        if Common.near(hitbox.Position, 8) then Common.touch(hitbox) end
        return "Taking the Holy Torch"
    end,
})

---------------------------------------------------------------------------
-- True Triple Katana
---------------------------------------------------------------------------

function Swords.ttkNext()
    for _, sword in ipairs(Swords.TTK_SWORDS) do
        if Common.masteryOf(sword) < Swords.TTK_MASTERY then return sword end
    end
    return nil
end

Swords.ttk = Mode({
    name = "True Triple Katana",
    key = "ItemTTK",
    sea = 3,
    want = function() return not Common.has("True Triple Katana") end,
    idleStatus = "Owned",
    tick = function(mode)
        local sword = Swords.ttkNext()
        if not sword then
            Movement.stop()
            if Common.every("TTKBuy", 3) then
                Services.invoke("MysteriousMan", "2")
                Services.invoke("LoadItem", "True Triple Katana")
            end
            return "Getting the True Triple Katana"
        end
        if not Common.has(sword) then
            Movement.stop()
            if Common.every("TTKLoad", 3) then Services.invoke("LoadItem", sword) end
            return "Taking " .. sword .. " out"
        end
        Common.equip(sword)
        local mob = Enemies.nearest(Data.BONE_MOBS)
        local status
        if mob then
            status = Fight.status(mob, Fight.engage(mode, mob, "Sword"), nil, "Sword")
        elseif boneSearch:run(mode, Data.BONE_MOBS) then
            status = "Looking for bone mobs"
        else
            status = "Waiting for bone mobs"
        end
        return string.format("%s %d/%d: %s", sword, Common.masteryOf(sword), Swords.TTK_MASTERY, status)
    end,
    stop = function() boneSearch:reset() end,
})

---------------------------------------------------------------------------
-- Yoru Mini (Dark Dagger)
---------------------------------------------------------------------------

Swords.yoru = Mode({
    name = "Yoru Mini",
    key = "ItemYoru",
    sea = 3,
    want = function() return Common.itemCount("Dark Dagger") == 0 and not Common.has("Dark Dagger") end,
    idleStatus = "Owned",
    tick = function(mode)
        local indra, inWorld = Enemies.findBoss("rip_indra True Form")
        if indra then return Common.fight(mode, indra, inWorld) end
        if Common.has("God's Chalice") then
            return Summons.run(mode, true, true)
        end
        local elite, eliteInWorld = EliteHunter.find()
        if elite then return "Chalice: " .. EliteHunter.run(mode, elite, eliteInWorld) end
        local hopAfter = Settings.get("OtherChestHopAfter")
        if Settings.get("ItemYoruHop") and yoruChests.collected >= hopAfter then
            Movement.stop()
            if Common.hop("chests for a chalice", true) then yoruChests:reset() end
            return "Chests done: hopping"
        end
        yoruChests:step(false)
        return string.format("Chests for a chalice (%d)", yoruChests.collected)
    end,
})

function Swords.reset()
    boneSearch:reset()
    yoruChests:reset()
end

return Swords
