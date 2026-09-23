--=============================================================================
-- STACK: CHESTS — collect chests when God's Chalice / Fist of Darkness spawn
--=============================================================================
--  The game spawns one of the two items in a chest every 4 hours of server
--  time. The reference computes the next spawn from the oldest location's
--  "TimeIn" attribute (it subtracts 25200 from tick() because its author's
--  clock was UTC+7; the server clock is UTC, so os.time() is used here).
--
--  From 5 seconds before the spawn, up to MAX_CHESTS chests are collected
--  (Features/ChestHunt: nearest first, spawns toured when none is around).
--  It stops early once one of the items is in the backpack.
--=============================================================================

local ChestHunt = require("Features.ChestHunt")
local Common = require("Features.Stack.Common")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Chests = { name = "Chests" }

Chests.CYCLE = 4 * 3600
Chests.OPEN_BEFORE = 5
Chests.MAX_CHESTS = 10
Chests.ITEMS = { "God's Chalice", "Fist of Darkness" }

local collecting = false
local hunt = ChestHunt.new()

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
            collecting = true
            hunt:reset()
        end
    elseif hunt.collected >= Chests.MAX_CHESTS or hasItem() then
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

function Chests.tick(mode)
    mode.target = nil
    local found = hunt:step(false)
    if found == "chest" then
        return string.format("Collecting chest %d/%d", hunt.collected, Chests.MAX_CHESTS)
    end
    if found == "searching" then return "Looking for chests" end
    return "No chest found"
end

function Chests.describe()
    local left = Chests.spawnIn()
    if not left then return "Chalice / Fist spawn: unknown" end
    left = math.floor(left)
    return string.format("Chalice / Fist spawn in %d:%02d:%02d",
        math.floor(left / 3600), math.floor(left % 3600 / 60), left % 60)
end

function Chests.reset()
    collecting = false
    hunt:reset()
end

return Chests
