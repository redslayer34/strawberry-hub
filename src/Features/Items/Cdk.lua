--=============================================================================
-- ITEMS: CURSED DUAL KATANA
--=============================================================================
--  Needs Tushita and Yama at 350 mastery. The server tracks two trial lines
--  (CDKQuest Progress Good -> { Good, Evil }): a positive value counts the
--  trials done, a negative one is the trial in progress. Every trial is
--  fought with a sword.
--
--    Good -3  talk to every Luxury Boat Dealer
--    Good -4  defend the Castle on the Sea from a pirate raid
--    Good -5  Cake Queen, then the Heavenly Dimension (torches, mobs, exit)
--    Evil -3  get killed by a Marine Commodore
--    Evil -4  kill the haze-marked mobs (LocalPlayer.QuestHaze)
--    Evil -5  Soul Reaper sends you to the Hell Dimension (torches, mobs, exit)
--
--  Good 4 / Evil 3 and Good 3 / Evil 4 open a pedestal each; 4 / 4 opens
--  the last one and the Cursed Skeleton Boss.
--=============================================================================

local Common = require("Features.Stack.Common")
local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local Events = require("Features.Stack.Events")
local Fight = require("Features.Fight")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Cdk = {}

Cdk.MASTERY = 350
Cdk.CASTLE = Vector3.new(-5543.5327148438, 313.80062866211, -2964.2585449219)
Cdk.SKELETON = Vector3.new(-12341.66796875, 603.3455810546875, -6550.6064453125)
Cdk.RAID_WAIT = 20   -- seconds without a raid before hopping (option)

local SWORD = "Sword"
local search = Fight.newSearch()
local raidMissingSince, dealerIndex = nil, 1

local function owns(name)
    return Common.has(name) or Common.itemCount(name) > 0
end

function Cdk.progress()
    local answer = Common.invoke("CDKQuest", "Progress", "Good")
    if type(answer) ~= "table" then return nil end
    return answer.Good, answer.Evil
end

local function skipDialogue()
    local player = Services.player()
    local dialogue = player and Services.find(player, "PlayerGui.Main.Dialogue")
    if dialogue and dialogue.Visible then
        pcall(function() Services.get("VirtualUser"):Button1Down(Vector2.new(0, 0)) end)
    end
end

local function fightSword(mode, mob, inWorld)
    return Common.fight(mode, mob, inWorld, SWORD)
end

local function nearbyMob(radius)
    local here = Player.position()
    local enemies = workspace:FindFirstChild("Enemies")
    for _, mob in ipairs(enemies and enemies:GetChildren() or {}) do
        if Enemies.isAlive(mob) and here and (mob.HumanoidRootPart.Position - here).Magnitude < radius then
            return mob
        end
    end
    return nil
end

-- Heaven / Hell: exit when it lights up, else kill the mobs, else light
-- the next torch.
local function dimension(mode, mapName, exitColour)
    local map = Services.find(workspace, "Map." .. mapName)
    if not map then return "Waiting for the dimension" end
    local exit = map:FindFirstChild("Exit")
    if exit and Common.colorName(exit) == exitColour then
        Common.goTo(exit.CFrame)
        Common.touch(exit)
        return "Leaving the dimension"
    end
    local mob = nearbyMob(300)
    if mob then return fightSword(mode, mob, true) end
    for index = 1, 3 do
        local torch = map:FindFirstChild("Torch" .. index)
        local prompt = torch and torch:FindFirstChild("ProximityPrompt")
        if prompt and prompt.Enabled then
            Common.goTo(torch.CFrame)
            if Common.near(torch.Position, 5) and fireproximityprompt then pcall(fireproximityprompt, prompt) end
            return "Lighting torch " .. index
        end
    end
    Movement.stop()
    return "Dimension: waiting"
end

local function inside(locationName)
    local location = Services.find(workspace, "_WorldOrigin.Locations." .. locationName)
    return location ~= nil and Player.distanceTo(location.Position) < 1000
end

---------------------------------------------------------------------------
-- Good trials
---------------------------------------------------------------------------

local function boatDealers()
    local found = {}
    for _, root in ipairs({ workspace:FindFirstChild("NPCs"), Services.replicated():FindFirstChild("NPCs") }) do
        for _, npc in ipairs(root and root:GetChildren() or {}) do
            if npc.Name:find("Luxury Boat Dealer", 1, true) then found[#found + 1] = npc end
        end
    end
    return found
end

local function good3()
    local dealers = boatDealers()
    if #dealers == 0 then
        Movement.stop()
        return "No Luxury Boat Dealer loaded"
    end
    if dealerIndex > #dealers then dealerIndex = 1 end
    local npc = dealers[dealerIndex]
    local root = npc:FindFirstChild("HumanoidRootPart")
    if root then
        Common.goTo(root.CFrame)
        if Common.near(root.Position, 10) and Common.every("CdkBoat", 1) then
            Services.invoke("CDKQuest", "BoatQuest", npc)
            dealerIndex = dealerIndex + 1
        end
    else
        dealerIndex = dealerIndex + 1
    end
    return "Talking to the boat dealers"
end

local function good4(mode)
    if Player.distanceTo(Cdk.CASTLE) > 1000 then
        Common.goTo(Cdk.CASTLE)
        return "Going to the Castle for the raid"
    end
    local pirate, inWorld = Events.raider()
    if pirate then
        raidMissingSince = nil
        return fightSword(mode, pirate, inWorld)
    end
    raidMissingSince = raidMissingSince or os.clock()
    if Settings.get("CdkHopRaid") and os.clock() - raidMissingSince >= Cdk.RAID_WAIT then
        raidMissingSince = nil
        Common.hop("no castle raid", true)
    end
    Movement.stop()
    return "Waiting for the castle raid"
end

local function good5(mode)
    if inside("Heavenly Dimension") then return dimension(mode, "HeavenlyDimension", "Cloudy grey") end
    local queen, inWorld = Enemies.findBoss("Cake Queen")
    if queen then return fightSword(mode, queen, inWorld) end
    if Settings.get("CdkHopCakeQueen") then Common.hop("no Cake Queen") end
    Movement.stop()
    return "Waiting for Cake Queen"
end

---------------------------------------------------------------------------
-- Evil trials
---------------------------------------------------------------------------

local function evil3()
    local commodore = Enemies.nearest("Marine Commodore")
    if commodore then
        Common.goTo(commodore.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3))
        return "Letting a Marine Commodore win"
    end
    local spawn = Enemies.spawnPoints("Marine Commodore")[1]
    if spawn then Common.goTo(spawn.CFrame * CFrame.new(0, 60, 0)) else Movement.stop() end
    return "Looking for a Marine Commodore"
end

local function hazeTarget()
    local player = Services.player()
    local haze = player and player:FindFirstChild("QuestHaze")
    for _, entry in ipairs(haze and haze:GetChildren() or {}) do
        if (tonumber(entry.Value) or 0) > 0 then return entry.Name end
    end
    return nil
end

local function evil4(mode)
    local name = hazeTarget()
    if not name then
        Movement.stop()
        return "Waiting for the haze quest"
    end
    return "Haze: " .. Common.farm(mode, { name }, search)
end

local function evil5(mode)
    if inside("Hell Dimension") then return dimension(mode, "HellDimension", "Olivine") end
    local reaper = Enemies.findBoss("Soul Reaper")
    if reaper then
        Common.goTo(reaper.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3))
        return "Letting Soul Reaper take you to Hell"
    end
    if not Common.has("Hallow Essence") then
        if Common.every("CdkBones", 1) then Services.invoke("Bones", "Buy", 1, 1) end
        return "Hallow Essence: " .. Common.farm(mode, Data.BONE_MOBS, search)
    end
    local summoner = Services.find(workspace, "Map.Haunted Castle.Summoner.Detection")
    if not summoner then
        Common.goTo(Vector3.new(-9513.466796875, 142.09776306152344, 5528.83740234375))
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

local function pedestal(name)
    local part = Services.find(workspace, "Map.Turtle.Cursed." .. name)
    if not part then
        Movement.stop()
        return "Cursed room not loaded"
    end
    Common.goTo(part.CFrame)
    local prompt = part:FindFirstChild("ProximityPrompt")
    if Common.near(part.Position, 10) and prompt and fireproximityprompt and Common.every("CdkPedestal", 1) then
        pcall(fireproximityprompt, prompt)
        Common.forget()
    end
    return "Using " .. name
end

local function finale(mode)
    local gem = Services.find(workspace, "Map.Turtle.Cursed.PlacedGem")
    if gem and gem.Transparency == 0 then
        local boss, inWorld = Enemies.findBoss("Cursed Skeleton Boss")
        if boss then return fightSword(mode, boss, inWorld) end
        Common.goTo(Cdk.SKELETON)
        return "Waiting for the Cursed Skeleton Boss"
    end
    return pedestal("Pedestal3")
end

function Cdk.requirements()
    if not owns("Tushita") or not owns("Yama") then return "Needs Tushita and Yama" end
    if Common.masteryOf("Tushita") < Cdk.MASTERY or Common.masteryOf("Yama") < Cdk.MASTERY then
        return "Needs 350 mastery on Tushita and Yama"
    end
    return nil
end

Cdk.mode = Mode({
    name = "CDK",
    key = "ItemCDK",
    sea = 3,
    want = function()
        return not owns("Cursed Dual Katana") and Cdk.requirements() == nil
    end,
    idleStatus = "Owned, or needs Tushita and Yama at 350 mastery",
    tick = function(mode)
        if not Common.has("Tushita") and not Common.has("Yama") then
            Movement.stop()
            if Common.every("CdkLoad", 3) then Services.invoke("LoadItem", "Tushita") end
            return "Taking Tushita out"
        end
        skipDialogue()
        local good, evil = Cdk.progress()
        if good == nil then return "Reading the CDK progress" end
        if good == 4 and evil == 3 then return pedestal("Pedestal2") end
        if good == 3 and evil == 4 then return pedestal("Pedestal1") end
        if good == 4 and evil == 4 then return finale(mode) end

        if good ~= 4 and good ~= -2 then
            if Common.every("CdkStartGood", 3) then Services.invoke("CDKQuest", "StartTrial", "Good") end
            if good == -3 then return "Good 3: " .. good3() end
            if good == -4 then return "Good 4: " .. good4(mode) end
            if good == -5 then return "Good 5: " .. good5(mode) end
            Movement.stop()
            return "Starting the good trial"
        end
        if Common.every("CdkStartEvil", 3) then Services.invoke("CDKQuest", "StartTrial", "Evil") end
        if evil == -3 then return "Evil 3: " .. evil3() end
        if evil == -4 then return "Evil 4: " .. evil4(mode) end
        if evil == -5 then return "Evil 5: " .. evil5(mode) end
        Movement.stop()
        return "Starting the evil trial"
    end,
    stop = function() search:reset() end,
})

function Cdk.reset()
    search:reset()
    raidMissingSince, dealerIndex = nil, 1
end

return Cdk
