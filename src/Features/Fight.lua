--=============================================================================
-- FIGHT — how every farm mode fights and looks for mobs
--=============================================================================
--  Shared so each mode behaves the same: hold above the mob, bring its pack,
--  let Mastery take over when it is low, and otherwise tour the spawn points
--  of the wanted mobs until one shows up.
--=============================================================================

local Bring = require("Game.Bring")
local Enemies = require("Game.Enemies")
local IslandLoader = require("Game.IslandLoader")
local Mastery = require("Game.Mastery")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local PlayerTweaks = require("Features.PlayerTweaks")
local Services = require("Core.Services")
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
Fight.MOB_MAX_NEAR = 60       -- a normal mob still up after this long next to it: bugged
Fight.REAL_DROP = 0.01         -- a health drop counts from 1 % of MaxHealth
-- The attack loop only sends the network hits. Some mobs (the Lava
-- Pirates, for the user) take no damage until a real click: the user's
-- own click unstuck them. So a real click is made while a mob does not
-- lose health.
Fight.NUDGE_AFTER = 4
Fight.NUDGE_EVERY = 3
Fight.nudging = false
-- One record per mob (weak keys): switching between copies of a bugged mob
-- no longer starts the count again.
local records = setmetatable({}, { __mode = "k" })
local strikes = {}
local resyncUntil, resyncAt = 0, nil
Fight.lastIgnored = nil      -- { name, at } for the status

local function strike(mob, seconds)
    Enemies.ignore(mob, seconds)
    records[mob] = nil
    Fight.lastIgnored = { name = mob.Name, at = os.clock() }
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

-- What a player's click does: the tool used, and a mouse click.
function Fight.realClick()
    pcall(function()
        local tool = Player.equippedTool()
        if tool then tool:Activate() end
    end)
    pcall(function()
        local user = Services.get("VirtualUser")
        user:CaptureController()
        user:Button1Down(Vector2.new(0, 0))
        user:Button1Up(Vector2.new(0, 0))
    end)
end

-- Whether the character is holding still to resync with the server.
function Fight.resyncing()
    return os.clock() < resyncUntil
end

local function watchDamage(mob)
    Fight.nudging = false
    local humanoid = mob:FindFirstChildOfClass("Humanoid")
    local root = mob:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return end
    local now = os.clock()
    local distance = Player.distanceTo(root.Position)
    local record = records[mob]
    if not record then
        records[mob] = { last = now, near = 0, low = humanoid.Health, lowerAt = now, best = distance, closerAt = now }
        return
    end
    local dt = math.min(now - record.last, 1)
    record.last = now
    if distance < record.best - Fight.PROGRESS then
        record.best, record.closerAt = distance, now
    end
    -- Only the time spent next to it counts for the damage (not the flight).
    if distance > 40 then
        record.lowerAt = now
        -- Far away the Router may be going round through a door: only a
        -- mob close by that cannot be reached counts.
        if distance > Fight.NEAR_ENOUGH then record.closerAt = now end
        if now - record.closerAt > Fight.NO_PROGRESS_AFTER then strike(mob, 60) end
        return
    end
    record.closerAt = now
    record.near = record.near + dt
    -- No drop for a while: a real click, as the player would.
    if now - record.lowerAt >= Fight.NUDGE_AFTER and not Mastery.active(mob) then
        Fight.nudging = true
        if not record.nudgedAt or now - record.nudgedAt >= Fight.NUDGE_EVERY then
            record.nudgedAt = now
            Fight.realClick()
        end
    end
    local maxHealth = (humanoid.MaxHealth and humanoid.MaxHealth > 0) and humanoid.MaxHealth or 100
    if humanoid.Health <= record.low - maxHealth * Fight.REAL_DROP then
        record.low, record.lowerAt = humanoid.Health, now
        strikes = {}
    elseif now - record.lowerAt > Fight.NO_DAMAGE_AFTER then
        return strike(mob, 120)
    end
    -- A normal mob dies in seconds: one still up after this long is bugged
    -- (bosses take longer).
    if record.near > Fight.MOB_MAX_NEAR and not Fight.isBoss(mob) then strike(mob, 120) end
end

Fight.BOSS_EXTRA = 10

function Fight.isBoss(mob)
    local name = Enemies.stripLevel(mob.Name)
    for _, boss in ipairs(require("Game.Data").BOSSES) do
        if name == boss or name:find(boss, 1, true) then return true end
    end
    return false
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
    -- A little higher over a boss: its area attacks hit hard (the Ice
    -- Admiral at level 700).
    local height = Settings.get("FarmHeight") + (Fight.isBoss(mob) and Fight.BOSS_EXTRA or 0)
    Movement.to(root.CFrame * CFrame.new(7, height, 0))
    if Settings.get("BringMob") then
        Bring.run(mob, Settings.get("BringCount"))
    end
    mode.target = mob
    PlayerTweaks.ensureBuso()
    if Mastery.step(mob) then return true end
    local tool = Player.equip(weapon or Settings.get("Weapon"))
    -- Close enough to hit: the style's buff first (Dark Step's Overheat).
    if tool and Player.distanceTo(root.Position) <= 40 then pcall(Mastery.buff, tool) end
    return tool ~= nil
end

-- "Fighting X" plus a warning when the weapon is missing.
function Fight.status(mob, hasWeapon, suffix, weapon)
    if Fight.resyncing() then return "No damage on " .. Fight.STRIKES .. " mobs: holding still to resync" end
    local ignored = Fight.lastIgnored
    if ignored and os.clock() - ignored.at < 4 then
        return ignored.name .. " cannot be damaged: left alone 2 min"
    end
    local text = "Fighting " .. mob.Name .. (suffix or "") .. (Fight.nudging and " (clicking to unstick)" or "")
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
    -- No mob up where they spawn: have that place loaded (low graphics).
    IslandLoader.focus(point.Position)
    if Player.distanceTo(point.Position) <= Fight.SPAWN_REACHED then
        self.visited[point] = true
    end
    return true
end

return Fight
