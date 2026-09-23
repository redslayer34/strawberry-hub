--=============================================================================
-- STACK: CHESTS — collect chests when God's Chalice / Fist of Darkness spawn
--=============================================================================
--  The game spawns one of the two items in a chest every 4 hours of server
--  time. The reference computes the next spawn from the oldest location's
--  "TimeIn" attribute (it subtracts 25200 from tick() because its author's
--  clock was UTC+7; the server clock is UTC, so os.time() is used here).
--
--  From 5 seconds before the spawn, up to MAX_CHESTS chests are collected,
--  nearest first, giving up on one after GIVE_UP seconds. With no chest in
--  range the player spawns are toured so more stream in. It stops early
--  once one of the items is in the backpack.
--=============================================================================

local Common = require("Features.Stack.Common")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Chests = { name = "Chests" }

Chests.CYCLE = 4 * 3600
Chests.OPEN_BEFORE = 5
Chests.MAX_CHESTS = 10
Chests.GIVE_UP = 5
Chests.ITEMS = { "God's Chalice", "Fist of Darkness" }

local collecting, collected = false, 0
local current, reachedAt
local ignored, visitedSpawns = {}, {}

-- Test hook: the clock the spawn is computed with.
Chests.now = function()
    local ok, now = pcall(function() return workspace:GetServerTimeNow() end)
    if ok and type(now) == "number" then return now end
    return os.time()
end

-- Seconds until the next spawn, or nil when the server has not said.
function Chests.spawnIn()
    local locations = Services.find(workspace, "_WorldOrigin.Locations")
    if not locations then return nil end
    local oldest
    for _, location in ipairs(locations:GetChildren()) do
        local timeIn = location:GetAttribute("TimeIn")
        if type(timeIn) == "number" and (not oldest or timeIn < oldest) then oldest = timeIn end
    end
    if not oldest then return nil end
    local elapsed = Chests.now() - oldest
    return Chests.CYCLE - elapsed % Chests.CYCLE
end

local function hasItem()
    for _, name in ipairs(Chests.ITEMS) do
        if Common.has(name) then return true end
    end
    return false
end

-- Opens the collecting window at spawn time; closes it when done.
local function update()
    if not collecting then
        local left = Chests.spawnIn()
        if left and left <= Chests.OPEN_BEFORE then
            collecting, collected = true, 0
            current, reachedAt = nil, nil
            ignored, visitedSpawns = {}, {}
        end
    elseif collected >= Chests.MAX_CHESTS or hasItem() then
        collecting = false
    end
end

function Chests.enabled()
    return Settings.get("StackChests") == true
end

function Chests.want()
    update()
    return collecting
end

local function usable(chest)
    return chest and chest.Parent and not ignored[chest] and not chest:GetAttribute("IsDisabled")
end

local function nearestChest()
    local here = Player.position()
    if not here then return nil end
    local best, bestDistance
    local ok, tagged = pcall(function()
        return Services.get("CollectionService"):GetTagged("_ChestTagged")
    end)
    for _, chest in ipairs(ok and tagged or {}) do
        if usable(chest) then
            local distance = (chest.Position - here).Magnitude
            if not bestDistance or distance < bestDistance then best, bestDistance = chest, distance end
        end
    end
    return best
end

local function nextSpawn()
    local spawns = Services.find(workspace, "_WorldOrigin.PlayerSpawns.Pirates")
    if not spawns then return nil end
    for _, model in ipairs(spawns:GetChildren()) do
        local part = model:FindFirstChild("Part")
        if part and not visitedSpawns[model] then return model, part end
    end
    visitedSpawns = {}
    return nil
end

function Chests.tick(mode)
    mode.target = nil
    if not usable(current) then
        current, reachedAt = nearestChest(), nil
        if current then collected = collected + 1 end
    end

    if current then
        Common.goTo(current.CFrame)
        if Common.near(current.Position, 5) then
            Common.touch(current)
            reachedAt = reachedAt or os.clock()
            if os.clock() - reachedAt >= Chests.GIVE_UP then ignored[current] = true end
        end
        return string.format("Collecting chest %d/%d", collected, Chests.MAX_CHESTS)
    end

    local model, part = nextSpawn()
    if not model then return "No chest found" end
    Common.goTo(part.CFrame)
    if Common.near(part.Position, 100) then visitedSpawns[model] = true end
    return "Looking for chests"
end

function Chests.describe()
    local left = Chests.spawnIn()
    if not left then return "Chalice / Fist spawn: unknown" end
    left = math.floor(left)
    return string.format("Chalice / Fist spawn in %d:%02d:%02d",
        math.floor(left / 3600), math.floor(left % 3600 / 60), left % 60)
end

function Chests.reset()
    collecting, collected = false, 0
    current, reachedAt = nil, nil
    ignored, visitedSpawns = {}, {}
end

return Chests
