--=============================================================================
-- STACK: BOSSES — Darkbeard, rip_indra True Form, Soul Reaper, Dough King
--=============================================================================
--  Each boss is fought when it is alive. The summons use the item the boss
--  asks for, the way the reference does:
--
--    Darkbeard    Fist of Darkness, touched on the arena's summoner (Sea 2)
--    Soul Reaper  Hallow Essence, used on the Haunted Castle summoner
--    Dough King   a Sweet Chalice (10 Conjured Cocoa + God's Chalice given
--                 to the Sweet Chalice NPC), then CakePrinceSpawner while
--                 the Cake Land mobs are farmed
--
--  rip_indra's summon is in Summons.lua (it needs the haki pads).
--=============================================================================

local Common = require("Features.Stack.Common")
local Data = require("Game.Data")
local EliteHunter = require("Features.Stack.EliteHunter")
local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Bosses = {}

Bosses.HAUNTED_CASTLE = Vector3.new(-9513.466796875, 142.09776306152344, 5528.83740234375)
Bosses.COCOA_NEEDED = 10

---------------------------------------------------------------------------
-- Darkbeard (Sea 2)
---------------------------------------------------------------------------

local darkbeard = { name = "Darkbeard" }
Bosses.darkbeard = darkbeard

local function darkbeardSummoner()
    return Services.find(workspace, "Map.DarkbeardArena.Summoner.Detection")
end

function darkbeard.enabled()
    return Settings.get("StackDarkbeard") == true and Player.sea() == 2
end

function darkbeard.want()
    if Enemies.findBoss("Darkbeard") then return true end
    return Settings.get("StackSummonDarkbeard") == true and Common.has("Fist of Darkness")
end

function darkbeard.tick(mode)
    local boss, inWorld = Enemies.findBoss("Darkbeard")
    if boss then return Common.fight(mode, boss, inWorld) end

    mode.target = nil
    local summoner = darkbeardSummoner()
    if not summoner then return "Darkbeard's arena is not loaded" end
    Common.goTo(summoner.CFrame)
    if Common.near(summoner.Position, 5) then
        local fist = Common.equip("Fist of Darkness")
        Common.touch(summoner, fist)
    end
    return "Summoning Darkbeard"
end

function darkbeard.hop()
    if Settings.get("StackHopDarkbeard") and not Enemies.findBoss("Darkbeard") and not Common.has("Fist of Darkness") then
        return "no Darkbeard"
    end
    return nil
end

---------------------------------------------------------------------------
-- rip_indra True Form (Sea 3)
---------------------------------------------------------------------------

local ripIndra = { name = "Rip Indra" }
Bosses.ripIndra = ripIndra

function ripIndra.enabled()
    return Settings.get("StackRipIndra") == true and Player.sea() == 3
end

function ripIndra.want()
    return Enemies.findBoss("rip_indra True Form") ~= nil
end

function ripIndra.tick(mode)
    local boss, inWorld = Enemies.findBoss("rip_indra True Form")
    if not boss then return "Not spawned" end
    return Common.fight(mode, boss, inWorld)
end

---------------------------------------------------------------------------
-- Soul Reaper (Sea 3)
---------------------------------------------------------------------------

local soulReaper = { name = "Soul Reaper" }
Bosses.soulReaper = soulReaper

function soulReaper.enabled()
    return Settings.get("StackSoulReaper") == true and Player.sea() == 3
end

function soulReaper.want()
    if Enemies.findBoss("Soul Reaper") then return true end
    return Settings.get("StackSummonSoulReaper") == true and Common.has("Hallow Essence")
end

function soulReaper.tick(mode)
    local boss, inWorld = Enemies.findBoss("Soul Reaper")
    if boss then return Common.fight(mode, boss, inWorld) end

    mode.target = nil
    local summoner = Services.find(workspace, "Map.Haunted Castle.Summoner.Detection")
    if not summoner then
        Common.goTo(Bosses.HAUNTED_CASTLE)
        return "Going to the Haunted Castle"
    end
    Common.goTo(summoner.CFrame)
    if Common.near(summoner.Position) then
        local essence = Common.equip("Hallow Essence")
        if essence then pcall(function() essence:Activate() end) end
        Common.touch(summoner, essence)
    end
    return "Summoning Soul Reaper"
end

---------------------------------------------------------------------------
-- Dough King (Sea 3)
---------------------------------------------------------------------------

local doughKing = { name = "Dough King" }
Bosses.doughKing = doughKing
local cakeSearch, cocoaSearch = Fight.newSearch(), Fight.newSearch()

function doughKing.enabled()
    return Settings.get("StackDoughKing") == true and Player.sea() == 3
end

-- What the summon needs next: "spawn" (Sweet Chalice held), "cocoa",
-- "elite" (a God's Chalice from an elite), or nil (nothing to do now).
local function summonStep()
    if not Settings.get("StackSummonDoughKing") then return nil end
    if Common.has("Sweet Chalice") then return "spawn" end
    -- The NPC trades the chalice and the cocoa by itself when both are held.
    if Common.invoke("SweetChaliceNpc") ~= "Where are the items?" then return nil end
    if Common.itemCount("Conjured Cocoa") < Bosses.COCOA_NEEDED then return "cocoa" end
    if Common.has("God's Chalice") then return nil end
    if EliteHunter.find() then return "elite" end
    return nil
end

function doughKing.want()
    if Enemies.findBoss("Dough King") then return true end
    return summonStep() ~= nil
end

function doughKing.tick(mode)
    local boss, inWorld = Enemies.findBoss("Dough King")
    if boss then return Common.fight(mode, boss, inWorld) end

    local step = summonStep()
    if step == "spawn" then
        if Common.every("CakePrinceSpawner", 2) then Services.invoke("CakePrinceSpawner") end
        return "Summoning: " .. Common.farm(mode, Data.CAKE_MOBS, cakeSearch)
    end
    if step == "cocoa" then
        return string.format("Conjured Cocoa %d/%d: %s", Common.itemCount("Conjured Cocoa"),
            Bosses.COCOA_NEEDED, Common.farm(mode, Data.COCOA_MOBS, cocoaSearch))
    end
    if step == "elite" then
        local elite, eliteInWorld = EliteHunter.find()
        if elite then return "God's Chalice: " .. EliteHunter.run(mode, elite, eliteInWorld) end
    end
    mode.target = nil
    return "Waiting"
end

function doughKing.hop()
    if Settings.get("StackHopDoughKing") and not Enemies.findBoss("Dough King") and summonStep() == nil then
        return "no Dough King"
    end
    return nil
end

function Bosses.reset()
    cakeSearch:reset()
    cocoaSearch:reset()
end

return Bosses
