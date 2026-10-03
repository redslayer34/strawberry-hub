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

local Data = require("Game.Data")
local Enemies = require("Game.Enemies")
local Fight = require("Features.Fight")
local IslandLoader = require("Game.IslandLoader")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Quests = require("Game.Quests")
local Settings = require("Core.Settings")

local LevelFarm = {
    name = "Level Farm",
    status = "Idle",
    target = nil,     -- the mob the attack loop should strike
}

-- Teddy's SafeGetQuest: StartQuest from 30 studs, again every 0.5 s.
LevelFarm.QUEST_RANGE = 30       -- studs from the quest giver to talk to it
LevelFarm.QUEST_SETTLE = 0       -- seconds standing there before StartQuest
LevelFarm.QUEST_RETRY = 0.5      -- seconds between two StartQuest attempts
LevelFarm.BOSS_RETRY = 3         -- the same for a boss quest (its tries are counted)
LevelFarm.ABANDON_EVERY = 3      -- seconds between two AbandonQuest (boss quests)
LevelFarm.BOSS_TRIES = 3         -- boss quest asks that give nothing...
LevelFarm.BOSS_PAUSE = 120       -- ...then boss quests are left alone this long
-- A boss quest held for a boss that is not really there (killed by
-- someone else, fought by another player, a stale copy): dropped, and that
-- boss is left alone this long.
LevelFarm.BOSS_ABSENT = 180
LevelFarm.BOSS_REACH = 60        -- seconds to reach the boss after taking its quest
LevelFarm.BOSS_NEAR = 200        -- studs: at the boss
LevelFarm.BOSS_STALE = 20        -- seconds at a parked copy without the boss loading

-- Whatever the cause (a bugged mob, a desync...): the quest's kill count
-- frozen this long while fighting means the farm is stuck. First the quest
-- is dropped (its mobs left alone a while), then the character is reset.
LevelFarm.STUCK_AFTER = 120
LevelFarm.STUCK_AGAIN = 600     -- a second freeze within this time: reset
local stuck = { value = nil, since = nil, lastFix = nil }

local arrivedAt, lastStart, lastAbandon
local bossTries, bossPausedUntil = 0, nil
local bossHeldSince, staleSince

-- Boss quests are wanted: the setting is on and the server did not keep
-- refusing one.
local function bossQuestsOn()
    if not Settings.get("FarmBossQuests") then return false end
    return not bossPausedUntil or os.clock() >= bossPausedUntil
end
local search = Fight.newSearch()

-- Double quest: of the giver's quests (best first), the one to take now.
-- The best one, unless its mobs are not up (just killed for the last
-- quest) while the other's are: then the other, and the farm does not
-- wait for respawns. Returns the plan and a note for the status.
function LevelFarm.choose(pair)
    local best, other = pair[1], pair[2]
    if not best or not other or not Settings.get("DoubleQuest") then return best, nil end
    local up, otherUp = #Enemies.all(best.mob), #Enemies.all(other.mob)
    local note = string.format("double quest: %d alive, %s %d", up, other.mob, otherUp)
    if up >= best.count or up >= otherUp then return best, note end
    return other, string.format("double quest: %d alive, %s %d", otherUp, best.mob, up)
end

function LevelFarm.enabled()
    return Settings.get("AutoFarmLevel") == true
end

local function takeQuest(weapon)
    LevelFarm.target = nil
    Player.equip(weapon or Settings.get("Weapon"))
    local plan = bossQuestsOn() and Quests.bossQuest(Player.level())
    local note
    if not plan then plan, note = LevelFarm.choose(Quests.pair(Player.level())) end
    if not plan or not plan.position then
        LevelFarm.status = "No quest found for level " .. Player.level()
        Movement.stop()
        return
    end

    Movement.to(CFrame.new(plan.position) * CFrame.new(0, 4, 2))
    -- The giver's island loaded ahead of the arrival (its mobs with it).
    IslandLoader.focus(plan.position)

    if Player.distanceTo(plan.position) > LevelFarm.QUEST_RANGE then
        arrivedAt = nil
        LevelFarm.status = "Going to " .. tostring(plan.npc or plan.questName)
            .. " (" .. plan.mob .. ")"
        return
    end

    local now = os.clock()
    arrivedAt = arrivedAt or now
    LevelFarm.status = "Taking quest: " .. plan.mob .. (note and (" (" .. note .. ")") or "")
    if now - arrivedAt >= LevelFarm.QUEST_SETTLE
        and (not lastStart or now - lastStart >= (plan.boss and LevelFarm.BOSS_RETRY or LevelFarm.QUEST_RETRY)) then
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
    -- No spawn part streamed in yet: where the mob is known to live
    -- (Teddy's table) brings it into streaming range. The Shandas live on
    -- the Upper Skylands, far from their giver on the lower ones.
    local spot = Data.MOB_SPOTS[name]
    if spot then
        Movement.to(CFrame.new(spot) * CFrame.new(0, Fight.SPAWN_HEIGHT, 0))
        IslandLoader.focus(spot)
        LevelFarm.status = "Looking for " .. name .. " where it lives"
        return
    end
    -- Else around its quest giver.
    local plan
    for _, quest in ipairs(Quests.pair(Player.level())) do
        if quest.mob == name then plan = quest end
    end
    if plan and plan.position then
        Movement.to(CFrame.new(plan.position) * CFrame.new(0, Fight.SPAWN_HEIGHT, 0))
        IslandLoader.focus(plan.position)
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
    if quest.count == 1 then return false end
    bossHeldSince, staleSince = nil, nil
    local boss = bossQuestsOn() and Quests.bossQuest(Player.level())
    if boss then
        abandon("Boss " .. boss.mob .. " is up: switching to its quest")
        return true
    end
    return false
end

local function giveUpBoss(name, why)
    Enemies.markAbsent(name, LevelFarm.BOSS_ABSENT)
    bossHeldSince, staleSince = nil, nil
    abandon(string.format("Boss %s: not really there (%s), back to mob quests for %d min",
        name, why, math.floor(LevelFarm.BOSS_ABSENT / 60)))
end

-- A boss quest is held (FarmBossQuests): fight the boss when it is really
-- there, otherwise find out quickly and drop the quest.
local function bossTick(quest, weapon)
    local now = os.clock()
    bossHeldSince = bossHeldSince or now
    local boss = Enemies.bossUp(quest.mob)
    if boss then
        staleSince = nil
        if Player.distanceTo(boss.HumanoidRootPart.Position) > LevelFarm.BOSS_NEAR
            and now - bossHeldSince > LevelFarm.BOSS_REACH then
            return giveUpBoss(quest.mob, "not reached in " .. LevelFarm.BOSS_REACH .. " s")
        end
        local hasWeapon = Fight.engage(LevelFarm, boss, weapon)
        LevelFarm.status = Fight.status(boss, hasWeapon, " (boss quest)", weapon)
        return
    end
    -- Out of streaming range the game parks the boss in ReplicatedStorage:
    -- going there loads it, unless that copy is stale.
    local copy, inWorld = Enemies.findBoss(quest.mob)
    if copy and not inWorld then
        local where = copy.HumanoidRootPart.Position
        LevelFarm.target = nil
        Movement.to(CFrame.new(where) * CFrame.new(0, Fight.SPAWN_HEIGHT, 0))
        if Player.distanceTo(where) <= LevelFarm.BOSS_NEAR then
            staleSince = staleSince or now
            if now - staleSince > LevelFarm.BOSS_STALE then return giveUpBoss(quest.mob, "nothing loaded there") end
        elseif now - bossHeldSince > LevelFarm.BOSS_REACH then
            return giveUpBoss(quest.mob, "not reached in " .. LevelFarm.BOSS_REACH .. " s")
        end
        LevelFarm.status = "Boss quest: going to " .. quest.mob
        return
    end
    return giveUpBoss(quest.mob, copy and "fought by someone else" or "gone")
end

-- The farm-level watchdog (see STUCK_AFTER). Returns true when it acted.
function LevelFarm.unstick(quest)
    local current = Quests.progress()
    local now = os.clock()
    if current == nil then return false end
    if current ~= stuck.value or not stuck.since then
        stuck.value, stuck.since = current, now
        return false
    end
    if now - stuck.since < LevelFarm.STUCK_AFTER then return false end
    stuck.since = now
    if stuck.lastFix and now - stuck.lastFix < LevelFarm.STUCK_AGAIN then
        stuck.lastFix = nil
        local blocked
        pcall(function() blocked = require("Game.Router").resetBlocked() end)
        if not blocked then
            LevelFarm.target = nil
            pcall(function()
                local humanoid = Player.humanoid()
                if humanoid then humanoid.Health = 0 end
            end)
            LevelFarm.status = "Still stuck: resetting the character"
            return true
        end
    end
    stuck.lastFix = now
    for _, model in ipairs(Enemies.all(quest.mob)) do Enemies.ignore(model, 120) end
    abandon("No kill for " .. math.floor(LevelFarm.STUCK_AFTER / 60) .. " min: dropping the quest")
    return true
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
    if quest.count == 1 and Settings.get("FarmBossQuests") then return bossTick(quest, weapon) end

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
    if mob and LevelFarm.unstick(quest) then return end
    if mob then
        local hasWeapon = Fight.engage(LevelFarm, mob, weapon)
        LevelFarm.status = Fight.status(mob, hasWeapon, quest.count and (" x" .. quest.count) or "", weapon)
        return
    end
    stuck.since = nil   -- only the time spent fighting counts
    return hunt(quest.mob)
end

-- Called when the mode stops being the active one.
function LevelFarm.stop()
    LevelFarm.target = nil
    LevelFarm.status = "Idle"
    arrivedAt, lastStart, lastAbandon = nil, nil, nil
    bossTries, bossPausedUntil = 0, nil
    bossHeldSince, staleSince = nil, nil
    stuck = { value = nil, since = nil, lastFix = nil }
    search:reset()
end

return LevelFarm
