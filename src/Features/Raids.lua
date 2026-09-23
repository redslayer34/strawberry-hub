--=============================================================================
-- RAIDS — solo raids and multi-account raids (Sea 2 and Sea 3)
--=============================================================================
--  A raid is: buy a Special Microchip from the raid NPC (RaidsNpc Select),
--  press the summoner's button (RaidSummon2.Button.Main), then clear the
--  numbered islands. Inside a raid the game shows the RaidTimer HUD and the
--  islands appear as "Island N" locations.
--
--  Multi Raid runs the hub on several accounts in the same server: the
--  buyer purchases the chip and presses the button once every selected
--  account stands on a slot of the summoner's circle; the others take a
--  free slot and fight along.
--=============================================================================

local Common = require("Features.Stack.Common")
local Enemies = require("Game.Enemies")
local Events = require("Features.Stack.Events")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Raids = {}

Raids.CASTLE = Vector3.new(-5500, 314, -2855)
Raids.MIN_LEVEL = 1100
Raids.ISLAND_RANGE = 3000
Raids.FIGHT_RANGE = 400
Raids.SLOT_RANGE = 10
Raids.AFTER_RAID = 5        -- seconds before pressing the button again
Raids.BUY_TRIES = 3         -- chip purchases without a chip before backing off
Raids.BACKOFF = 60
Raids.CHEAP_FRUIT = 1000000 -- fruits under this price may pay for the chip

local lastRaidAt, lastKill = -math.huge, -math.huge
local buyTries, backoffUntil = 0, nil

-- Raid names for the list, from ReplicatedStorage.Raids.
function Raids.names()
    local data = Services.module("Raids")
    local names, seen = {}, {}
    if type(data) == "table" then
        for _, group in pairs(data) do
            for _, name in pairs(type(group) == "table" and group or {}) do
                if type(name) == "string" and not seen[name] then
                    seen[name] = true
                    names[#names + 1] = name
                end
            end
        end
    end
    if #names == 0 then names = { "Flame", "Ice", "Quake", "Light", "Dark", "Spider", "Rumble", "Magma",
        "Buddha", "Sand", "Phoenix", "Dough" } end
    table.sort(names)
    return names
end

---------------------------------------------------------------------------
-- Raid state
---------------------------------------------------------------------------

local function islands()
    local list = {}
    local locations = Services.find(workspace, "_WorldOrigin.Locations")
    for _, location in ipairs(locations and locations:GetChildren() or {}) do
        local number = tonumber((location.Name:match("^Island (%d+)$")))
        if number and Player.distanceTo(location.Position) < Raids.ISLAND_RANGE then
            list[#list + 1] = { number = number, part = location }
        end
    end
    return list
end

function Raids.inRaid()
    local player = Services.player()
    local timer = player and Services.find(player, "PlayerGui.Main.TopHUDList.RaidTimer")
    return timer ~= nil and timer.Visible == true and #islands() > 0
end

local function lastIsland()
    local best
    for _, island in ipairs(islands()) do
        if not best or island.number > best.number then best = island end
    end
    return best
end

function Raids.button()
    local sea = Player.sea()
    if sea == 3 then return Services.find(workspace, "Map.Boat Castle.RaidSummon2.Button.Main") end
    if sea == 2 then return Services.find(workspace, "Map.CircleIsland.RaidSummon2.Button.Main") end
    return nil
end

local function raidEnemy()
    local here = Player.position()
    local enemies = workspace:FindFirstChild("Enemies")
    if not here or not enemies then return nil end
    local best, bestDistance
    for _, model in ipairs(enemies:GetChildren()) do
        if Enemies.isAlive(model) then
            local distance = (model.HumanoidRootPart.Position - here).Magnitude
            if distance <= Raids.FIGHT_RANGE and (not bestDistance or distance < bestDistance) then
                best, bestDistance = model, distance
            end
        end
    end
    return best
end

-- One step inside a raid.
function Raids.fight(mode)
    lastRaidAt = os.clock()
    local enemy = raidEnemy()
    if enemy then
        if Settings.get("RaidInstantKill") and os.clock() - lastKill >= Settings.get("RaidKillDelay") then
            lastKill = os.clock()
            pcall(function() enemy.Humanoid:ChangeState(Enum.HumanoidStateType.Dead) end)
        end
        return "Raid: " .. Common.fight(mode, enemy, true)
    end
    local island = lastIsland()
    if island then
        local offset = (island.number == 2 and Settings.get("RaidName") == "Phoenix")
            and CFrame.new(300, 60, 0) or CFrame.new(0, 60, 0)
        Common.goTo(island.part.CFrame * offset)
        return "Raid: going to island " .. island.number
    end
    Movement.stop()
    return "Raid: waiting"
end

---------------------------------------------------------------------------
-- Chip
---------------------------------------------------------------------------

local function holdsFruit()
    local player = Services.player()
    for _, container in ipairs({ Player.character(), player and player:FindFirstChild("Backpack") }) do
        for _, tool in ipairs(container and container:GetChildren() or {}) do
            if tool:IsA("Tool") and tool.Name:find("Fruit", 1, true) then return true end
        end
    end
    return false
end

-- A stored fruit cheap enough to pay for a chip.
function Raids.cheapFruit()
    local prices = {}
    local list = Common.invoke("GetFruits", false)
    for _, fruit in ipairs(type(list) == "table" and list or {}) do
        if type(fruit) == "table" and fruit.Name then prices[fruit.Name] = tonumber(fruit.Price) end
    end
    for _, item in ipairs(Common.inventory()) do
        if item.type == "Blox Fruit" and (prices[item.name] or 0) < Raids.CHEAP_FRUIT then return item.name end
    end
    return nil
end

-- Buys a chip. Returns the status, or nil when nothing could be done.
function Raids.buyChip()
    if Player.level() < Raids.MIN_LEVEL then return nil end
    local cheap = Settings.get("RaidCheapFruit") and not holdsFruit() and Raids.cheapFruit()
    if cheap and Common.every("RaidLoadFruit", 3) then
        Services.invoke("LoadFruit", cheap)
        Common.forget()
    end
    if Settings.get("RaidHopFruit") and not holdsFruit() and not cheap then
        local fruit = Events.groundFruit()
        if fruit then
            Common.goTo(fruit.Handle.CFrame)
            if Common.near(fruit.Handle.Position, 5) then Common.touch(fruit.Handle) end
            return "Picking up a fruit for the chip"
        end
        Movement.stop()
        Common.hop("no fruit for a raid chip", true)
        return "No fruit to pay the chip: hopping"
    end
    Movement.stop()
    if Common.every("RaidChip", 3) then
        Services.invoke("RaidsNpc", "Check")
        Services.invoke("RaidsNpc", "Select", Settings.get("RaidName"))
        buyTries = buyTries + 1
        if buyTries >= Raids.BUY_TRIES then
            buyTries, backoffUntil = 0, os.clock() + Raids.BACKOFF
        end
    end
    return "Buying a " .. tostring(Settings.get("RaidName")) .. " chip"
end

local function goToSummoner()
    if Player.sea() == 3 then
        Common.goTo(Raids.CASTLE)
        return "Going to the raid summoner"
    end
    Movement.stop()
    return "Raid summoner not loaded: go to the raid lab once"
end

local function press(button)
    Common.goTo(button.CFrame)
    local detector = button:FindFirstChild("ClickDetector")
    if detector and fireclickdetector and os.clock() - lastRaidAt >= Raids.AFTER_RAID
        and Common.every("RaidPress", 2) then
        pcall(fireclickdetector, detector)
    end
    return "Starting the raid"
end

local function busyBackingOff()
    return backoffUntil ~= nil and os.clock() < backoffUntil
end

---------------------------------------------------------------------------
-- Solo raid
---------------------------------------------------------------------------

Raids.solo = Mode({
    name = "Raid",
    key = "RaidAuto",
    want = function()
        if Raids.inRaid() or Common.has("Special Microchip") then return true end
        return Player.level() >= Raids.MIN_LEVEL and not busyBackingOff()
    end,
    idleStatus = "Level 1100 needed, or waiting after failed chip purchases",
    tick = function(mode)
        if Raids.inRaid() then return Raids.fight(mode) end
        if Common.has("Special Microchip") then
            buyTries = 0
            local button = Raids.button()
            if not button then return goToSummoner() end
            return press(button)
        end
        return Raids.buyChip() or "Level 1100 needed"
    end,
})

---------------------------------------------------------------------------
-- Multi raid
---------------------------------------------------------------------------

local function slots(button)
    local circle = button and button.Parent and button.Parent.Parent
    local list = {}
    for _, child in ipairs(circle and circle:GetChildren() or {}) do
        local hitbox = child:FindFirstChild("Hitbox")
        if hitbox then list[#list + 1] = { model = child, hitbox = hitbox } end
    end
    return list
end
Raids.slots = slots

local function onSlot(position, list)
    for _, slot in ipairs(list) do
        if position and (slot.hitbox.Position - position).Magnitude <= Raids.SLOT_RANGE then return true end
    end
    return false
end

local function freeSlot(list)
    for _, slot in ipairs(list) do
        local colour = slot.model:FindFirstChild("Color")
        if not colour or Common.colorName(colour) ~= "Lime green" then return slot end
    end
    return nil
end

-- True when every selected account stands on a slot.
function Raids.everyoneOnSlots(list)
    local accounts = Settings.get("MultiRaidAccounts") or {}
    local players = Services.get("Players")
    for name, selected in pairs(accounts) do
        if selected then
            local player = players:FindFirstChild(name)
            local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if not root or not onSlot(root.Position, list) then return false end
        end
    end
    return true
end

Raids.multi = Mode({
    name = "Multi Raid",
    key = "MultiRaid",
    tick = function(mode)
        if Raids.inRaid() then return Raids.fight(mode) end
        local button = Raids.button()
        if not button then return goToSummoner() end
        local list = slots(button)

        local buyer = Settings.get("MultiRaidBuyer")
        -- The buyer presses the button; the other accounts hold the slots.
        if Settings.get("MultiRaidSlot") and not buyer and not onSlot(Player.position(), list) then
            local slot = freeSlot(list)
            if slot then
                Common.goTo(slot.hitbox.CFrame * CFrame.new(0, -2, 0))
                return "Taking a raid slot"
            end
        end

        if Common.has("Special Microchip") then
            if not buyer then
                Movement.stop()
                return "Holding a chip: waiting for the buyer"
            end
            if not Raids.everyoneOnSlots(list) then
                Movement.stop()
                return "Waiting for every account on a slot"
            end
            return press(button)
        end
        if buyer then return Raids.buyChip() or "Level 1100 needed" end
        Movement.stop()
        return "Waiting for the buyer to start"
    end,
})

-- Test hook.
function Raids.reset()
    lastRaidAt, lastKill = -math.huge, -math.huge
    buyTries, backoffUntil = 0, nil
end

return Raids
