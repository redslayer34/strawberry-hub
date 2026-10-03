--=============================================================================
-- ITEMS: RAINBOW HAKI, YAMA, TUSHITA, TRUE TRIPLE KATANA, YORU MINI
--=============================================================================
--    Rainbow Haki  the Horned Man's five boss quests (HornedMan Bet)
--    Yama          30 Elite Hunters, then the sealed katana on Waterfall
--                  island: kill its Ghosts, click it
--    Tushita       while rip_indra is up, the Holy Torch at the Hydra
--                  waterfall door, the 5 torches in order, then Longma
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
        if Common.owns("Yama") then return false end
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

-- The wiki and the sources (Teddy's Tushita, Banana's GetTushita):
--   1. rip_indra True Form summoned and left alive (the torch is only out
--      then; Longma drops Tushita only for a puzzle done that way);
--   2. the Holy Torch, at the Hydra Island waterfall door (Teddy stands on
--      TORCH_SPOT; Banana touches the Waterfall hitbox, even from the nil
--      instances when the island is not loaded);
--   3. the five torches of the Floating Turtle, in order, within 5 minutes:
--      TushitaProgress("Torch", n) for each one still unlit
--      (TushitaProgress().Torches);
--   4. the gate opens (Map.Turtle.TushitaGate gone, OpenedDoor): Longma.
Swords.TORCH_SPOT = Vector3.new(5712.98681640625, 18.041336059570312, 253.65997314453125)
Swords.TORCH_HITBOX = Vector3.new(5713.5376, 38.383118, 255.2017)

local function tushitaHitbox()
    local island = Services.find(workspace, "Map.Waterfall.IslandModel")
    local hitbox = island and island:FindFirstChild("Hitbox", true)
    if hitbox then return hitbox end
    -- Banana: out of streaming range the hitbox sits in the nil instances.
    local ok, found = pcall(function()
        for _, node in ipairs(getnilinstances and getnilinstances() or {}) do
            if node.Name == "Hitbox" and node:IsA("BasePart")
                and (node.Position - Swords.TORCH_HITBOX).Magnitude < 1 then
                return node
            end
        end
    end)
    return ok and found or nil
end

local function tushitaProgress()
    local progress = Common.invoke("TushitaProgress")
    return type(progress) == "table" and progress or {}
end

-- The Floating Turtle gate is open: OpenedDoor, or (Teddy) the TushitaGate
-- gone from a loaded Turtle.
local function gateOpen(progress)
    if progress.OpenedDoor then return true end
    local turtle = Services.find(workspace, "Map.Turtle")
    return turtle ~= nil and turtle:FindFirstChild("TushitaGate") == nil and progress.OpenedDoor == nil
        and next(progress) ~= nil
end

local function ripIndraUp()
    local boss, inWorld = Enemies.findBoss("rip_indra True Form")
    return boss ~= nil and inWorld == true
end

Swords.tushita = Mode({
    name = "Tushita",
    key = "ItemTushita",
    sea = 3,
    want = function()
        if Common.owns("Tushita") then return false end
        local progress = tushitaProgress()
        if gateOpen(progress) then return Enemies.findBoss("Longma") ~= nil end
        if Common.has("Holy Torch") then return true end
        -- Only while rip_indra is up (an island merely not loaded is no
        -- reason to fly there: back and forth in the user's video).
        if ripIndraUp() then return true end
        local hitbox = tushitaHitbox()
        return hitbox ~= nil and hitbox:FindFirstChild("TouchInterest") ~= nil
    end,
    idleStatus = "Owned, or waiting for rip_indra / Longma",
    tick = function(mode)
        mode.target = nil
        local progress = tushitaProgress()
        if gateOpen(progress) then
            local longma, inWorld = Enemies.findBoss("Longma")
            if longma then return Common.fight(mode, longma, inWorld) end
            Movement.stop()
            return "Waiting for Longma"
        end
        if Common.has("Holy Torch") then
            Common.equip("Holy Torch")
            Movement.stop()
            if Common.every("TushitaTorches", 2) then
                -- Teddy: each torch still unlit, in order.
                local torches = type(progress.Torches) == "table" and progress.Torches or nil
                for torch = 1, 5 do
                    if not torches or not torches[torch] then
                        Services.invoke("TushitaProgress", "Torch", torch)
                    end
                end
                Common.forget()
            end
            local lit = 0
            for torch = 1, 5 do
                if type(progress.Torches) == "table" and progress.Torches[torch] then lit = lit + 1 end
            end
            return "Lighting the torches (" .. lit .. "/5, 5 minutes)"
        end
        -- The Holy Torch at the waterfall door, while rip_indra is up.
        local hitbox = tushitaHitbox()
        if hitbox and Common.near(hitbox.Position, 25) then Common.touch(hitbox) end
        Common.goTo(Swords.TORCH_SPOT)
        if not Common.near(Swords.TORCH_SPOT, 25) then return "Going to the Hydra waterfall door" end
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
    want = function() return not Common.owns("Dark Dagger") end,
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
