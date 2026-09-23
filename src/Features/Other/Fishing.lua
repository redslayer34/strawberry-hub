--=============================================================================
-- FARMING OTHER: FISHING
--=============================================================================
--  The rod is driven through the game's own fishing remotes, as the
--  reference does:
--
--    FishReplicated.FishingRequest  StartCasting, then CastLineAtLocation
--                                   (point, power 98, isWater); Catching and
--                                   Catch once a fish bites
--    Net "FishingRemote" event      "SpawnFishOnBob" = a fish is on the line
--
--  The cast point is where the reference aims: a ray from the head along the
--  look direction, then straight down to the water. The player fishes at a
--  saved spot (position and facing, kept in StrawberryHub/fishing.json), or
--  at the nearest Golden Vortex event spot when that option is on.
--
--  Extras (loops, they do not move the character): sell fish, open fishing
--  chests, a bigger reel zone, the Angler's quests, Slap Battle timing.
--=============================================================================

local Common = require("Features.Stack.Common")
local Loop = require("Core.Loop")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Fishing = {}

Fishing.FILE = "StrawberryHub/fishing.json"
Fishing.POWER = 98
Fishing.CAST_DELAY = 0.7     -- seconds between StartCasting and the cast
Fishing.BITE_TIMEOUT = 5     -- seconds "Biting" before resetting the rod
Fishing.DEFAULT_BAIT = "Basic Bait"
Fishing.RARITIES = { "Common", "Uncommon", "Rare", "Legendary", "Mythical" }

local spot            -- saved { x, y, z, rx, ry, rz }
local spotLoaded = false
local castAt, bitingSince
local vortex, vortexStand
local connections = {}

---------------------------------------------------------------------------
-- Saved spot
---------------------------------------------------------------------------

local function loadSpot()
    if spotLoaded then return spot end
    spotLoaded = true
    if not (isfile and readfile) then return nil end
    local ok, data = pcall(function()
        if not isfile(Fishing.FILE) then return nil end
        return Services.get("HttpService"):JSONDecode(readfile(Fishing.FILE))
    end)
    if ok and type(data) == "table" and tonumber(data.x) then spot = data end
    return spot
end

function Fishing.spotCFrame()
    local saved = loadSpot()
    if not saved then return nil end
    local position = Vector3.new(saved.x, saved.y, saved.z)
    local ok, rotated = pcall(function()
        return CFrame.new(position) * CFrame.fromOrientation(saved.rx or 0, saved.ry or 0, saved.rz or 0)
    end)
    return ok and rotated or CFrame.new(position)
end

-- Saves where the player stands and looks. Returns the text for the tab.
function Fishing.saveSpot()
    local hrp = Player.hrp()
    if not hrp then return nil end
    local cframe = hrp.CFrame
    local rx, ry, rz = 0, 0, 0
    pcall(function() rx, ry, rz = cframe:ToOrientation() end)
    local p = cframe.Position
    spot, spotLoaded = { x = p.X, y = p.Y, z = p.Z, rx = rx, ry = ry, rz = rz }, true
    if writefile then
        pcall(function()
            if makefolder and isfolder and not isfolder("StrawberryHub") then makefolder("StrawberryHub") end
            writefile(Fishing.FILE, Services.get("HttpService"):JSONEncode(spot))
        end)
    end
    return Fishing.describeSpot()
end

function Fishing.describeSpot()
    local saved = loadSpot()
    if not saved then return "No fishing position saved" end
    return string.format("Position %.1f, %.1f, %.1f", saved.x, saved.y, saved.z)
end

---------------------------------------------------------------------------
-- Rod, bait and remotes
---------------------------------------------------------------------------

function Fishing.rod()
    local character = Player.character()
    local data = character and character:FindFirstChild("FishingRodData", true)
    if data then return data.Parent end
    local player = Services.player()
    local backpack = player and player:FindFirstChild("Backpack")
    for _, tool in ipairs(backpack and backpack:GetChildren() or {}) do
        if tool:FindFirstChild("FishingRodData") then return tool end
    end
    return nil
end

local function request()
    return Services.find(Services.replicated(), "FishReplicated.FishingRequest")
end

local function ask(...)
    local remote = request()
    if not remote then return nil end
    local args = { n = select("#", ...), ... }
    local ok, result = pcall(function()
        return remote:InvokeServer((table.unpack or unpack)(args, 1, args.n))
    end)
    return ok and result or nil
end
Fishing.ask = ask

function Fishing.baitNames()
    local data = Services.module("FishReplicated.BaitData")
    local names = {}
    if type(data) == "table" and type(data.Types) == "table" then
        for name in pairs(data.Types) do names[#names + 1] = name end
    end
    if #names == 0 then names[1] = Fishing.DEFAULT_BAIT end
    table.sort(names)
    return names
end

local function selectedBait()
    local player = Services.player()
    local data = player and Services.find(player, "Data.FishingData")
    local bait = data and data:GetAttribute("SelectedBait")
    return bait ~= nil and bait ~= "None" and bait or nil
end

local function loadBait()
    local bait = Settings.get("OtherBait")
    if bait == nil or bait == "" then bait = Fishing.DEFAULT_BAIT end
    if not Common.every("FishingBait", 3) then return "Loading " .. bait end
    if Common.itemCount(bait) > 0 then
        Services.invoke("LoadItem", bait, { "Usables" })
    else
        Common.netInvoke("RF/Craft", "Craft", bait, 1, {})
    end
    Common.forget()
    return "Loading " .. bait
end

-- Where the line lands and whether it is water, the reference's way.
-- Replaced in the tests (it needs Roblox raycasts).
Fishing.castPoint = function(hrp, rod)
    local config = Services.module("FishReplicated.FishingClient.Config")
    local waterHeight = Services.module("Util.GetWaterHeightAtLocation")
    if type(config) ~= "table" or type(waterHeight) ~= "function" then return nil end
    local character = hrp.Parent
    local head = character:FindFirstChild("Head")
    local ignore = { character, workspace:FindFirstChild("Characters"), workspace:FindFirstChild("Enemies") }
    local water = waterHeight(hrp.Position)
    local reach = (rod:GetAttribute("MaxLaunchDistance") or config.Rod.MaxLaunchDistance)
        * (0.5 + Fishing.POWER / 201)
    local _, ahead = workspace:FindPartOnRayWithIgnoreList(
        Ray.new(head.Position, hrp.CFrame.LookVector * reach), ignore)
    local below, ground = workspace:FindPartOnRayWithIgnoreList(
        Ray.new(ahead + Vector3.new(0, 3, 0), Vector3.new(0, -500, 0)), ignore)
    if not ground then return nil end
    local point = Vector3.new(ahead.X, math.max(ground.Y, water), ahead.Z)
    local isWater = point.Y <= water
    if below then
        local tagged = Services.get("CollectionService"):HasTag(below, config.WATER_BODY_TAG)
        isWater = tagged or isWater
    end
    return point, isWater
end

-- A fish on the line: the game's own client would play the minigame; the
-- reference answers it straight away.
local function onFishingEvent(player, event)
    if not Settings.get("OtherFishing") then return end
    if player ~= Services.player() or event ~= "SpawnFishOnBob" then return end
    task.spawn(function()
        task.wait(0.2)
        ask("Catching", true, { fastBite = true })
        task.wait(2)
        ask("Catch", 1, 1, 1)
        ask("Catch", 1, 0, 1)
    end)
end

local function listen()
    if connections.fishing then return end
    local remote = Services.netRemote("FishingRemote", true)
    if not remote then return end
    local ok, connection = pcall(function() return remote.OnClientEvent:Connect(onFishingEvent) end)
    if ok then connections.fishing = connection end
end
Fishing.onFishingEvent = onFishingEvent

---------------------------------------------------------------------------
-- Fishing step
---------------------------------------------------------------------------

-- One step with the rod, standing where the player should fish.
local function fish(hrp)
    local rod = Fishing.rod()
    if rod.Parent ~= Player.character() then
        Common.equip(rod.Name)
        return "Equipping the rod"
    end
    listen()

    if (rod:GetAttribute("SkillChargeAlpha") or 0) >= 1 and Common.every("RodSkill", 1) then
        Common.netInvoke("RF/JobToolAbilities", "Z", true)
    end

    local state = rod:GetAttribute("ServerState")
    local now = os.clock()
    if state == nil or state == "ReeledIn" then
        bitingSince = nil
        if not castAt then
            castAt = now
            ask("StartCasting")
            return "Casting"
        end
        if now - castAt < Fishing.CAST_DELAY then return "Casting" end
        castAt = nil
        local ok, point, isWater = pcall(Fishing.castPoint, hrp, rod)
        if not ok or not point then return "No water in front of you" end
        if not ask("CastLineAtLocation", point, Fishing.POWER, isWater) then
            Player.equip("Melee")   -- puts the rod away: the next cast starts clean
            return "Cast refused, retrying"
        end
        return "Line cast"
    end
    if state == "Biting" then
        bitingSince = bitingSince or now
        if now - bitingSince >= Fishing.BITE_TIMEOUT then
            bitingSince = nil
            Player.equip("Melee")
        end
    else
        bitingSince = nil
    end
    return "Fishing: " .. tostring(state)
end

-- The nearest Golden Vortex event spot, and where to stand for it (the
-- nearest solid part whose top is above the water there).
function Fishing.vortex()
    local spots = workspace:FindFirstChild("ActiveFishingSpots")
    local here = Player.position()
    if not spots or not here then return nil end
    local best, bestDistance
    for _, child in ipairs(spots:GetChildren()) do
        if child.Name == "GoldenVortex" then
            local distance = (child.Position - here).Magnitude
            if not bestDistance or distance < bestDistance then best, bestDistance = child, distance end
        end
    end
    return best
end

local function standFor(target)
    local map = workspace:FindFirstChild("Map")
    if not map then return nil end
    local best, bestDistance
    for _, part in ipairs(map:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide and part.Position.Y + part.Size.Y / 2 > target.Y then
            local distance = (part.Position - target).Magnitude
            if not bestDistance or distance < bestDistance then best, bestDistance = part, distance end
        end
    end
    if not best then return nil end
    return Vector3.new(best.Position.X, best.Position.Y + best.Size.Y / 2, best.Position.Z)
end

local function atVortex(hrp, found)
    if found ~= vortex then vortex, vortexStand = found, standFor(found.Position) end
    if not vortexStand then return nil end
    if not Common.near(vortexStand, 5) then
        Common.goTo(vortexStand)
        return "Going to the Golden Vortex"
    end
    Movement.stop()
    local target = found.Position
    local flat = Vector3.new(target.X, hrp.Position.Y, target.Z)
    hrp.CFrame = CFrame.new(hrp.Position, flat)
    return "Vortex: " .. fish(hrp)
end

local function facing(hrp, wanted)
    local ok, dot = pcall(function()
        local a, b = hrp.CFrame.LookVector, wanted.LookVector
        return a.X * b.X + a.Y * b.Y + a.Z * b.Z
    end)
    return not ok or dot > 0.99
end

Fishing.mode = Mode({
    name = "Fishing",
    key = "OtherFishing",
    tick = function()
        local hrp = Player.hrp()
        if not Fishing.rod() then
            Movement.stop()
            return "No fishing rod (buy one from the Angler)"
        end
        if not selectedBait() then
            Movement.stop()
            return loadBait()
        end
        if Settings.get("OtherFishingVortex") then
            local found = Fishing.vortex()
            if found then
                local status = atVortex(hrp, found)
                if status then return status end
            end
        end
        local wanted = Fishing.spotCFrame()
        if not wanted then
            Movement.stop()
            return "Save a fishing position first"
        end
        if not Common.near(wanted.Position, 10) or not facing(hrp, wanted) then
            Common.goTo(wanted)
            return "Going to the fishing spot"
        end
        Movement.stop()
        return fish(hrp)
    end,
    stop = function() castAt, bitingSince = nil, nil end,
})

---------------------------------------------------------------------------
-- Extras
---------------------------------------------------------------------------

local function jobs(...)
    local module = Services.module("JobsReplicated")
    if type(module) ~= "table" or not module.InvokeServer then return nil end
    local args = { n = select("#", ...), ... }
    local ok, result = pcall(module.InvokeServer, (table.unpack or unpack)(args, 1, args.n))
    return ok and result or nil
end
Fishing.jobs = jobs

local function fishingChest()
    local player = Services.player()
    for _, container in ipairs({ Player.character(), player and player:FindFirstChild("Backpack") }) do
        for _, tool in ipairs(container and container:GetChildren() or {}) do
            if tool.Name:find("Chest", 1, true) and tool:FindFirstChild("RemoteEvent") then return tool end
        end
    end
    return nil
end

function Fishing.rarityNames()
    local data = Services.module("Modules.Asset.RarityUtil.RarityData")
    local names = {}
    if type(data) == "table" then
        for _, rarity in pairs(data) do
            if type(rarity) == "table" and type(rarity.Name) == "string" then names[#names + 1] = rarity.Name end
        end
    end
    if #names == 0 then return Fishing.RARITIES end
    table.sort(names)
    return names
end

local function currentQuestName()
    local guide = Services.module("GuideModule")
    local questData = type(guide) == "table" and guide.Data and guide.Data.QuestData
    if type(questData) ~= "table" or type(questData.Task) ~= "table" then return nil end
    return (next(questData.Task))
end

-- Keep the current Angler quest? Quests of an unselected rarity are dropped.
function Fishing.wantedQuest()
    local name = currentQuestName()
    if not name then return false end
    local selected = Settings.get("OtherAnglerRarities") or {}
    if next(selected) == nil then return true end
    for _, rarity in ipairs(Fishing.rarityNames()) do
        if name:find(rarity, 1, true) then return selected[rarity] == true end
    end
    return true
end

local function anglerQuest()
    jobs("FishingNPC", "Angler", "CheckQuest")
    local speak = jobs("FishingNPC", "Angler", "Speak")
    if type(speak) ~= "table" then return end
    if speak.canAccept then
        jobs("FishingNPC", "Angler", "AskQuest")
    elseif speak.FailedAnglerQuest or not Fishing.wantedQuest() then
        Services.invoke("AbandonQuest")
    end
end

-- Slap Battle: the reference's timing, jumping when the cursor meets the
-- target zone.
local function slapBattle()
    if connections.slap then return end
    local player = Services.player()
    local remote = player and player:FindFirstChild("RemoteEvent")
    if not remote then return end
    local bar
    connections.slap = remote.OnClientEvent:Connect(function(kind, start, period, who, _, _, fixed)
        if not Settings.get("OtherSlapBattle") then return end
        if kind == "startBar" and who == player then
            local speed, zoneSpeed = 0.96 / (period * 0.5), 0.2 / (period * 1.5)
            if bar then bar:Disconnect() end
            bar = Services.get("RunService").Heartbeat:Connect(function()
                local now = workspace:GetServerTimeNow()
                local cursor = 0.02 + (now - start) % period * speed
                if cursor >= 0.98 then cursor = 0.98 - (cursor - 0.98) end
                local zone = 0.5
                if not fixed then
                    zone = 0.4 + (now - start) % (period * 3) * zoneSpeed
                    if zone >= 0.6 then zone = 0.6 - (zone - 0.6) end
                end
                if math.abs(cursor - zone) < 0.03 then
                    remote:FireServer("Jump", workspace:GetServerTimeNow())
                end
            end)
            connections.slapBar = bar
        elseif kind == "killBar" and bar then
            bar:Disconnect()
            bar = nil
        end
    end)
end

function Fishing.extrasStep()
    if Settings.get("OtherSellFish") and Common.every("SellFish", 2) then
        jobs("FishingNPC", "SellFish")
    end
    if Settings.get("OtherOpenChests") then
        local chest = fishingChest()
        if chest then
            pcall(function() chest.RemoteEvent:FireServer("Visual") end)
            task.delay(0.1, function()
                pcall(function() chest.RemoteEvent:FireServer("Open") end)
            end)
        end
    end
    if Settings.get("OtherAnglerQuest") and Common.every("AnglerQuest", 2) then
        anglerQuest()
    end
    if Settings.get("OtherSlapBattle") then pcall(slapBattle) end
end

local function reelStep()
    if not Settings.get("OtherReelSize") then return end
    local player = Services.player()
    local zone = player and Services.find(player, "PlayerGui.Fishing_Reeling.Minigame.Container.ReelZone")
    if zone then zone.Size = UDim2.new(0.98, 0, 0.13, 0) end
end

function Fishing.start()
    Loop.start("FishingExtras", 0.5, Fishing.extrasStep)
    Loop.start("ReelZone", 0.1, reelStep)
end

function Fishing.destroy()
    for key, connection in pairs(connections) do
        pcall(function() connection:Disconnect() end)
        connections[key] = nil
    end
end

-- Test hook.
function Fishing.reset()
    Fishing.destroy()
    spot, spotLoaded = nil, false
    castAt, bitingSince, vortex, vortexStand = nil, nil, nil, nil
end

return Fishing
