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

local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
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

local arrivedAt, lastStart
local search = Fight.newSearch()

function LevelFarm.enabled()
    return Settings.get("AutoFarmLevel") == true
end

local function takeQuest()
    LevelFarm.target = nil
    Player.equip(Settings.get("Weapon"))
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
        local result = Quests.start(plan)
        if result == nil or result == false then
            LevelFarm.status = LevelFarm.status .. " (server answered " .. tostring(result) .. ")"
        end
    end
end

local function hunt(name)
    if search:run(LevelFarm, { name }) then
        LevelFarm.status = "Looking for " .. name
        return
    end
    -- No spawn part streamed in yet. Quest mobs live around their quest
    -- giver, so waiting above it brings them into streaming range.
    local plan = Quests.best(Player.level())
    if plan and plan.mob == name and plan.position then
        Movement.to(CFrame.new(plan.position) * CFrame.new(0, Fight.SPAWN_HEIGHT, 0))
        LevelFarm.status = "Looking for " .. name .. " around its quest giver"
    else
        LevelFarm.status = "Waiting for " .. name .. " (no spawn point loaded)"
    end
end

function LevelFarm.tick()
    if not Player.alive() then
        LevelFarm.target = nil
        LevelFarm.status = "Waiting for respawn"
        return
    end

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

    local mob = Enemies.nearest(quest.mob)
    if mob then
        local hasWeapon = Fight.engage(LevelFarm, mob)
        LevelFarm.status = Fight.status(mob, hasWeapon, quest.count and (" x" .. quest.count) or "")
        return
    end
    return hunt(quest.mob)
end

-- Called when the mode stops being the active one.
function LevelFarm.stop()
    LevelFarm.target = nil
    LevelFarm.status = "Idle"
    arrivedAt, lastStart = nil, nil
    search:reset()
end

return LevelFarm
