--=============================================================================
-- PERCEPTION — one detection pass, paced and cached
--=============================================================================
--  None of this runs on RenderStepped. A full pass is expensive (walking the
--  Enemies folder, reading the UI, clustering): it runs every few seconds when
--  idle, and tightens up during combat when the situation changes fast.
--
--  A fixed order, each step building on the previous one:
--
--      DetectSea -> DetectIsland -> DetectQuest
--                -> RefreshQuestGiver -> RefreshTargets -> RefreshSpawnRegion
--
--  A sea or island change clears the map memory BEFORE the later steps read
--  anything, so no step can work on data inherited from the previous context.
--=============================================================================

local EnemyScanner = require("AutomationCore.Perception.EnemyScanner")
local IslandDetector = require("AutomationCore.Perception.IslandDetector")
local Log = require("AutomationCore.Log")
local QuestDetector = require("AutomationCore.Perception.QuestDetector")
local QuestGiverResolver = require("AutomationCore.Perception.QuestGiverResolver")
local SeaDetector = require("AutomationCore.Perception.SeaDetector")
local SpawnClusterResolver = require("AutomationCore.Perception.SpawnClusterResolver")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")

local Perception = {}
Perception.__index = Perception

function Perception.new(ctx)
    local self = setmetatable({
        ctx = ctx,
        scanner = EnemyScanner.new(ctx),
        lastFull = 0,
        lastQuest = 0,
        combatMode = false,
        questGiverHints = nil,
        questGiverFallback = nil,
    }, Perception)

    ctx.quest = QuestDetector.blank()
    return self
end

-- Combat mode tightens the pace: during a bring, the situation changes within
-- tenths of a second.
function Perception:setCombat(value)
    self.combatMode = value and true or false
end

function Perception:interval()
    local cfg = self.ctx.cfg.Perception
    return self.combatMode and cfg.CombatInterval or cfg.IdleInterval
end

-- Identification hints for the giver, set by the active farming mode.
-- Perception does not know which quest we want to take; it knows how to look
-- for it once told.
function Perception:setQuestGiverHints(hints, fallback)
    self.questGiverHints = hints
    self.questGiverFallback = fallback
end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------

function Perception:detectSea()
    return SeaDetector.update(self.ctx)
end

function Perception:detectIsland()
    return IslandDetector.update(self.ctx)
end

-- The quest is re-read more often than the rest: it is the source of truth,
-- and its progress changes on every kill.
function Perception:detectQuest(force)
    local ctx = self.ctx
    local now = os.clock()
    if not force and now - self.lastQuest < ctx.cfg.Perception.QuestPollInterval then
        return ctx.quest
    end
    self.lastQuest = now

    local previous = ctx.quest
    local current = QuestDetector.read(ctx)

    -- The real instance name cannot be invented: it comes from the Workspace.
    -- It is carried onto the quest state so everything downstream works with
    -- an entity that exists.
    if current.TargetName then
        current.ResolvedName = self.scanner:resolveName(current.TargetName)
    end

    -- Objective changed: everything derived from it is now wrong.
    if not QuestDetector.sameObjective(previous, current) then
        ctx.region = nil
        ctx.targets = {}
        ctx.map:invalidate("SpawnClusters", nil, "objective changed")
    end

    QuestDetector.logChange(previous, current)
    ctx.quest = current
    return current
end

function Perception:refreshQuestGiver()
    local hints = self.questGiverHints
    if not hints then return nil end

    local near = self.ctx.region and self.ctx.region.center or nil
    local position, level = QuestGiverResolver.resolve(
        self.ctx, hints, near, self.questGiverFallback)

    self.ctx.questGiver = position
    self.ctx.questGiverTrust = level
    return position, level
end

-- Rebuilds the list of VALID targets. This is the only place ctx.targets is
-- written: everything else reads it.
function Perception:refreshTargets()
    local ctx = self.ctx
    local quest = ctx.quest

    if not quest or not quest.TargetName then
        ctx.targets = {}
        return ctx.targets
    end

    local candidates = self.scanner:candidatesFor(quest.TargetName)
    ctx.targets = TargetValidator.filter(ctx, candidates, quest)
    return ctx.targets
end

function Perception:refreshSpawnRegion()
    local ctx = self.ctx
    -- The region is computed from valid targets but WITHOUT the region filter
    -- (otherwise it could never move: it would validate itself). So we start
    -- from the raw candidates revalidated without the zone check.
    local quest = ctx.quest
    if not quest or not quest.TargetName then
        ctx.region = nil
        return nil
    end

    local previousRegion = ctx.region
    ctx.region = nil
    local unfiltered = TargetValidator.filter(
        ctx, self.scanner:candidatesFor(quest.TargetName), quest)
    ctx.region = previousRegion

    local reference = ctx.questGiver or ctx:pos()
    return SpawnClusterResolver.update(ctx, unfiltered, reference)
end

---------------------------------------------------------------------------
-- Loop
---------------------------------------------------------------------------

-- One full pass. `force` ignores the pacing (used by recovery, which needs a
-- fresh picture immediately).
function Perception:update(force)
    local ctx = self.ctx
    local now = os.clock()

    -- The quest is re-read on every call, pacing or not: it is cheap (a few
    -- labels) and it is the data that must be freshest.
    self:detectQuest(force)

    if not force and now - self.lastFull < self:interval() then
        return false
    end
    self.lastFull = now
    ctx.stats.ticks = ctx.stats.ticks + 1

    local sea = self:detectSea()
    local island = self:detectIsland()

    -- Flush the memory BEFORE the steps that read it.
    ctx.map:syncContext(ctx.world.jobId(), sea, island)

    self.scanner:scan()

    -- Re-resolve the real name after the scan: on the first pass on a server,
    -- detectQuest ran against a still-empty index.
    if ctx.quest and ctx.quest.TargetName and not ctx.quest.ResolvedName then
        ctx.quest.ResolvedName = self.scanner:resolveName(ctx.quest.TargetName)
    end

    -- Region before giver, contrary to the nominal order: the two reference
    -- each other (the region is scored against the giver, the giver is broken
    -- by proximity to the region), so something has to give. Computing the
    -- region first means refreshTargets filters against a FRESH region -- and
    -- the target list is the critical output. The giver only loses a small
    -- ranking bonus by working from the previous pass's region.
    self:refreshSpawnRegion()
    self:refreshQuestGiver()
    self:refreshTargets()

    return true
end

-- Immediate, full rescan. First rung of the recovery ladder: often a "no
-- targets left" is just a stale index.
function Perception:rescan(reason)
    Log.Perception("rescan --", reason or "requested")
    self.lastFull = 0
    self.lastQuest = 0
    return self:update(true)
end

function Perception:targetCount() return #self.ctx.targets end

function Perception:describe()
    local ctx = self.ctx
    return string.format(
        "sea=%s island=%s targets=%d region=%s",
        tostring(ctx.sea), tostring(ctx.island), #ctx.targets,
        ctx.region and string.format("%d mobs", ctx.region.count) or "none")
end

return Perception
