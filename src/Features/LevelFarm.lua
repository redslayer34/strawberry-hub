--=============================================================================
-- LEVEL FARM — take the best quest, kill its mobs, repeat
--=============================================================================
--  One decision per tick, never a blocking wait, so switching the farm off
--  takes effect on the next frame:
--
--    no quest          -> fly to the best quest giver, StartQuest on arrival
--    quest, mob found  -> hold above it, bring its pack (the attack loop hits)
--    quest, no mob     -> visit its spawn points one after the other
--
--  The game completes the quest by itself once the count is reached; the
--  panel closes and the next tick picks up a new quest.
--=============================================================================

local Bring = require("Game.Bring")
local Enemies = require("Game.Enemies")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Quests = require("Game.Quests")
local Settings = require("Core.Settings")

local LevelFarm = {
    name = "Level Farm",
    status = "Idle",
    target = nil,     -- the mob the attack loop should strike
}

LevelFarm.QUEST_RANGE = 8        -- studs from the quest giver to talk to it
LevelFarm.QUEST_SETTLE = 1       -- seconds standing there before StartQuest
LevelFarm.QUEST_RETRY = 3        -- seconds between two StartQuest attempts
LevelFarm.SPAWN_HEIGHT = 60      -- fly this high above a spawn point
LevelFarm.SPAWN_REACHED = 100    -- studs: close enough, mobs stream in

local arrivedAt, lastStart
local currentMob
local visited = {}

function LevelFarm.enabled()
    return Settings.get("AutoFarmLevel") == true
end

local function takeQuest()
    LevelFarm.target = nil
    local plan = Quests.best(Player.level())
    if not plan or not plan.position then
        LevelFarm.status = "No quest found for level " .. Player.level()
        Movement.stop()
        return
    end

    Movement.to(CFrame.new(plan.position) * CFrame.new(0, 4, 2))

    if Player.distanceTo(plan.position) > LevelFarm.QUEST_RANGE then
        arrivedAt = nil
        LevelFarm.status = "Going to " .. tostring(plan.npc or plan.questName)
            .. " (" .. plan.mob .. ")"
        return
    end

    local now = os.clock()
    arrivedAt = arrivedAt or now
    LevelFarm.status = "Taking quest: " .. plan.mob
    if now - arrivedAt >= LevelFarm.QUEST_SETTLE
        and (not lastStart or now - lastStart >= LevelFarm.QUEST_RETRY) then
        lastStart = now
        Quests.start(plan)
    end
end

local function fight(mob, required, hasWeapon)
    local root = mob.HumanoidRootPart
    Movement.to(root.CFrame * CFrame.new(7, Settings.get("FarmHeight"), 0))
    if Settings.get("BringMob") then
        Bring.run(mob, Settings.get("BringCount"))
    end
    LevelFarm.target = mob
    LevelFarm.status = "Fighting " .. mob.Name .. (required and (" x" .. required) or "")
    if not hasWeapon then
        LevelFarm.status = LevelFarm.status .. " -- no " .. Settings.get("Weapon") .. " in your inventory"
    end
end

local function search(name)
    LevelFarm.target = nil
    local points = Enemies.spawnPoints(name)
    if #points == 0 then
        -- No spawn part streamed in yet. Quest mobs live around their quest
        -- giver, so waiting above it brings them into streaming range.
        local plan = Quests.best(Player.level())
        if plan and plan.mob == name and plan.position then
            Movement.to(CFrame.new(plan.position) * CFrame.new(0, LevelFarm.SPAWN_HEIGHT, 0))
            LevelFarm.status = "Looking for " .. name .. " around its quest giver"
        else
            LevelFarm.status = "Waiting for " .. name .. " (no spawn point loaded)"
        end
        return
    end

    local point
    for _, candidate in ipairs(points) do
        if not visited[candidate] then
            point = candidate
            break
        end
    end
    if not point then
        -- Every spawn visited without a live mob: start the round again.
        visited = {}
        point = points[1]
    end

    Movement.to(point.CFrame * CFrame.new(0, LevelFarm.SPAWN_HEIGHT, 0))
    LevelFarm.status = "Looking for " .. name
    if Player.distanceTo(point.Position) <= LevelFarm.SPAWN_REACHED then
        visited[point] = true
    end
end

function LevelFarm.tick()
    if not Player.alive() then
        LevelFarm.target = nil
        LevelFarm.status = "Waiting for respawn"
        return
    end

    local hasWeapon = Player.equip(Settings.get("Weapon")) ~= nil

    if not Quests.active() then
        return takeQuest()
    end
    arrivedAt = nil

    local quest = Quests.target()
    if not quest then
        LevelFarm.target = nil
        LevelFarm.status = "Reading quest..."
        return
    end

    if quest.mob ~= currentMob then
        currentMob = quest.mob
        visited = {}
    end

    local mob = Enemies.nearest(quest.mob)
    if mob then
        return fight(mob, quest.count, hasWeapon)
    end
    return search(quest.mob)
end

-- Called when the mode stops being the active one.
function LevelFarm.stop()
    LevelFarm.target = nil
    LevelFarm.status = "Idle"
    arrivedAt, lastStart, currentMob = nil, nil, nil
    visited = {}
end

return LevelFarm
