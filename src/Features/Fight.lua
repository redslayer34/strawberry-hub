--=============================================================================
-- FIGHT — how every farm mode fights and looks for mobs
--=============================================================================
--  Shared so each mode behaves the same: hold above the mob, bring its pack,
--  let Mastery take over when it is low, and otherwise tour the spawn points
--  of the wanted mobs until one shows up.
--=============================================================================

local Bring = require("Game.Bring")
local Enemies = require("Game.Enemies")
local Mastery = require("Game.Mastery")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local PlayerTweaks = require("Features.PlayerTweaks")
local Settings = require("Core.Settings")

local Fight = {}

Fight.SPAWN_HEIGHT = 60      -- fly this high above a spawn point
Fight.SPAWN_REACHED = 100    -- studs: close enough, mobs stream in

-- Engages `mob` for `mode` (sets mode.target, which the attack loop hits).
-- Returns hasWeapon: false when the chosen weapon is not in the inventory.
-- `weapon` (a ToolTip) replaces the Weapon setting when given.
-- A mob hit this long with its health never going down is left alone for
-- a while (Enemies.ignore): a secret quest's mob, a shielded one...
Fight.NO_DAMAGE_AFTER = 20
-- A mob the character does not get closer to (stuck in a wall, a client
-- position the server does not share) is left alone too.
Fight.NO_PROGRESS_AFTER = 15
Fight.PROGRESS = 10            -- studs closer that count as progress
Fight.NEAR_ENOUGH = 1000       -- ...for a mob closer than this
-- Several mobs in a row hit for nothing: the character itself is out of
-- step with the server (its position there is not the one on screen, as
-- the user found after a reset). It holds still a moment to resync.
Fight.STRIKES = 3
Fight.STRIKE_WINDOW = 180
Fight.RESYNC_TIME = 4
local watched = { mob = nil, since = 0, health = 0, best = math.huge, closerAt = 0 }
local strikes = {}
local resyncUntil, resyncAt = 0, nil

local function strike(mob, seconds)
    Enemies.ignore(mob, seconds)
    watched.mob = nil
    local now, kept = os.clock(), {}
    for _, at in ipairs(strikes) do
        if now - at <= Fight.STRIKE_WINDOW then kept[#kept + 1] = at end
    end
    kept[#kept + 1] = now
    strikes = kept
    if #strikes >= Fight.STRIKES then
        strikes = {}
        resyncUntil = now + Fight.RESYNC_TIME
        local here = Player.position()
        resyncAt = here and CFrame.new(here) or nil
    end
end

-- Whether the character is holding still to resync with the server.
function Fight.resyncing()
    return os.clock() < resyncUntil
end

local function watchDamage(mob)
    local humanoid = mob:FindFirstChildOfClass("Humanoid")
    local root = mob:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return end
    local now = os.clock()
    local distance = Player.distanceTo(root.Position)
    if watched.mob ~= mob then
        watched.mob, watched.since, watched.health = mob, now, humanoid.Health
        watched.best, watched.closerAt = distance, now
        return
    end
    if distance < watched.best - Fight.PROGRESS then
        watched.best, watched.closerAt = distance, now
    end
    -- Only the time spent next to it counts for the damage (not the flight).
    if distance > 40 then
        watched.since, watched.health = now, humanoid.Health
        -- Far away the Router may be going round through a door: only a
        -- mob close by that cannot be reached counts.
        if distance > Fight.NEAR_ENOUGH then watched.closerAt = now end
        if now - watched.closerAt > Fight.NO_PROGRESS_AFTER then strike(mob, 60) end
        return
    end
    watched.closerAt = now
    if humanoid.Health < watched.health then
        watched.since, watched.health = now, humanoid.Health
        strikes = {}
    elseif now - watched.since > Fight.NO_DAMAGE_AFTER then
        strike(mob, 120)
    end
end

function Fight.engage(mode, mob, weapon)
    watchDamage(mob)
    local root = mob.HumanoidRootPart
    if Fight.resyncing() then
        -- Held where it was (not stopped: the float would go, over lava).
        mode.target = nil
        if resyncAt then Movement.to(resyncAt) end
        return true
    end
    Movement.to(root.CFrame * CFrame.new(7, Settings.get("FarmHeight"), 0))
    if Settings.get("BringMob") then
        Bring.run(mob, Settings.get("BringCount"))
    end
    mode.target = mob
    PlayerTweaks.ensureBuso()
    if Mastery.step(mob) then return true end
    return Player.equip(weapon or Settings.get("Weapon")) ~= nil
end

-- "Fighting X" plus a warning when the weapon is missing.
function Fight.status(mob, hasWeapon, suffix, weapon)
    if Fight.resyncing() then return "No damage on " .. Fight.STRIKES .. " mobs: holding still to resync" end
    local text = "Fighting " .. mob.Name .. (suffix or "")
    if not hasWeapon then
        text = text .. " -- no " .. (weapon or Settings.get("Weapon")) .. " in your inventory"
    end
    return text
end

---------------------------------------------------------------------------
-- Spawn tour
---------------------------------------------------------------------------

local Search = {}
Search.__index = Search

function Fight.newSearch()
    return setmetatable({ visited = {}, key = nil }, Search)
end

function Search:reset()
    self.visited = {}
    self.key = nil
end

-- Flies to the next unvisited spawn point of any of `names`. Returns false
-- when no spawn point is known at all (the caller then picks a fallback).
function Search:run(mode, names)
    mode.target = nil
    local key = table.concat(names, "|")
    if key ~= self.key then
        self.key = key
        self.visited = {}
    end

    local points = {}
    for _, name in ipairs(names) do
        for _, point in ipairs(Enemies.spawnPoints(name)) do
            points[#points + 1] = point
        end
    end
    if #points == 0 then return false end

    local point
    for _, candidate in ipairs(points) do
        if not self.visited[candidate] then
            point = candidate
            break
        end
    end
    if not point then
        -- Every spawn visited without a live mob: start the round again.
        self.visited = {}
        point = points[1]
    end

    Movement.to(point.CFrame * CFrame.new(0, Fight.SPAWN_HEIGHT, 0))
    if Player.distanceTo(point.Position) <= Fight.SPAWN_REACHED then
        self.visited[point] = true
    end
    return true
end

return Fight
