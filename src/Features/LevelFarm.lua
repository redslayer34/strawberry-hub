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
LevelFarm.ABANDON_EVERY = 3      -- seconds between two AbandonQuest (boss quests)
LevelFarm.BOSS_TRIES = 3         -- boss quest asks that give nothing...
LevelFarm.BOSS_PAUSE = 120       -- ...then boss quests are left alone this long

local arrivedAt, lastStart, lastAbandon
local bossTries, bossPausedUntil = 0, nil

-- Boss quests are wanted: the setting is on and the server did not keep
-- refusing one.
local function bossQuestsOn()
    if not Settings.get("FarmBossQuests") then return false end
    return not bossPausedUntil or os.clock() >= bossPausedUntil
end
local search = Fight.newSearch()

function LevelFarm.enabled()
    return Settings.get("AutoFarmLevel") == true
end

local function takeQuest(weapon)
    LevelFarm.target = nil
    Player.equip(weapon or Settings.get("Weapon"))
    local plan = (bossQuestsOn() and Quests.bossQuest(Player.level())) or Quests.best(Player.level())
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
        if plan.boss then
            bossTries = bossTries + 1
            if bossTries > LevelFarm.BOSS_TRIES then
                bossTries, bossPausedUntil = 0, now + LevelFarm.BOSS_PAUSE
            end
        end
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

local function abandon(reason)
    LevelFarm.target = nil
    local now = os.clock()
    if not lastAbandon or now - lastAbandon >= LevelFarm.ABANDON_EVERY then
        lastAbandon = now
        Quests.abandon()
    end
    LevelFarm.status = reason
end

-- With FarmBossQuests: a mob quest gives way to a boss quest whose boss is
-- up, and a boss quest whose boss is gone (someone else killed it) is
-- dropped. Returns true when it acted.
local function bossSwitch(quest)
    if not Settings.get("FarmBossQuests") then return false end
    bossTries = 0
    if quest.count == 1 then
        if not Enemies.findBoss(quest.mob) then
            abandon("Boss " .. quest.mob .. " is gone: dropping its quest")
            return true
        end
        return false
    end
    local boss = bossQuestsOn() and Quests.bossQuest(Player.level())
    if boss then
        abandon("Boss " .. boss.mob .. " is up: switching to its quest")
        return true
    end
    return false
end

-- `weapon` (optional) replaces the Weapon setting (mastery farms).
function LevelFarm.tick(weapon)
    if not Player.alive() then
        LevelFarm.target = nil
        LevelFarm.status = "Waiting for respawn"
        return
    end

    if not Quests.active() then
        return takeQuest(weapon)
    end
    arrivedAt = nil

    local quest = Quests.target()
    if not quest then
        LevelFarm.target = nil
        LevelFarm.status = "Reading quest..."
        return
    end

    if bossSwitch(quest) then return end

    local mob = Enemies.nearest(quest.mob)
    if not mob and quest.count == 1 then
        -- A boss kept in ReplicatedStorage is out of streaming range: going
        -- there loads it.
        local boss, inWorld = Enemies.findBoss(quest.mob)
        if boss and inWorld then
            mob = boss
        elseif boss then
            LevelFarm.target = nil
            Movement.to(boss.HumanoidRootPart.CFrame * CFrame.new(0, Fight.SPAWN_HEIGHT, 0))
            LevelFarm.status = "Boss quest: going to " .. quest.mob
            return
        end
    end
    if mob then
        local hasWeapon = Fight.engage(LevelFarm, mob, weapon)
        LevelFarm.status = Fight.status(mob, hasWeapon, quest.count and (" x" .. quest.count) or "", weapon)
        return
    end
    return hunt(quest.mob)
end

-- Called when the mode stops being the active one.
function LevelFarm.stop()
    LevelFarm.target = nil
    LevelFarm.status = "Idle"
    arrivedAt, lastStart, lastAbandon = nil, nil, nil
    bossTries, bossPausedUntil = 0, nil
    search:reset()
end

return LevelFarm
