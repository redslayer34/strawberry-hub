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
function Fight.engage(mode, mob, weapon)
    local root = mob.HumanoidRootPart
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
