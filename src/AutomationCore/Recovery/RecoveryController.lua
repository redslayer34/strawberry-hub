--=============================================================================
-- RECOVERY CONTROLLER — get the farm running again, without starting over
--=============================================================================
--  A real recovery controller, not a `return` that lets the loop land on its
--  feet next turn.
--
--  The escalation ladder, always in this order:
--
--      1. local rescan       -- the index may simply be stale
--      2. recompute data     -- region, anchor, slot assignments
--      3. resume the current state if the cause is gone
--      4. fall back to detection (DETECT_*) if it persists
--      5. change server, only as a last resort
--
--  A server hop costs a minute of loading: it happens only once the earlier
--  rungs are exhausted, and never for a cause that resolves locally (a mob
--  dying mid-bring, for instance).
--=============================================================================

local Log = require("AutomationCore.Log")
local SafeCombatAnchor = require("AutomationCore.Movement.SafeCombatAnchor")
local TravelController = require("AutomationCore.Movement.TravelController")

local RecoveryController = {}
RecoveryController.__index = RecoveryController

-- Cause classification. `local` = resolves in place; `detect` = forces a
-- re-detection; `fatal` = the only case where the server is genuinely at fault.
local CAUSES = {
    quest_lost            = { class = "detect", resume = "DETECT_QUEST" },
    quest_not_taken       = { class = "detect", resume = "FIND_QUEST_GIVER" },
    quest_giver_missing   = { class = "detect", resume = "FIND_QUEST_GIVER", invalidateGiver = true },
    target_missing        = { class = "local",  resume = "SCAN_TARGETS" },
    target_died_in_bring  = { class = "local",  resume = "BUILD_TARGET_GROUP" },
    target_returned_spawn = { class = "local",  resume = "BRING_TARGETS" },
    player_dead           = { class = "wait",   resume = "DETECT_QUEST" },
    player_respawned      = { class = "local",  resume = "DETECT_QUEST" },
    server_changed        = { class = "detect", resume = "DETECT_SEA", wipe = true },
    map_not_loaded        = { class = "wait",   resume = "DETECT_ISLAND" },
    invalid_position      = { class = "local",  resume = "BUILD_TARGET_GROUP", invalidateAnchor = true },
    movement_blocked      = { class = "local",  resume = "TRAVEL_TO_QUEST", resetTravel = true },
    combat_interrupted    = { class = "local",  resume = "SCAN_TARGETS" },
    boss_missing          = { class = "fatal",  resume = "DETECT_QUEST" },
    objective_missing     = { class = "detect", resume = "SPECIAL_OBJECTIVE" },
    unknown               = { class = "detect", resume = "DETECT_QUEST" },
}

function RecoveryController.new(ctx, perception)
    return setmetatable({
        ctx = ctx,
        perception = perception,
        cause = nil,
        attempts = 0,
        redetects = 0,
        failures = 0,
        lastAttempt = 0,
        enteredAt = 0,
    }, RecoveryController)
end

-- Declares the cause before entering the RECOVERY state. A cause different
-- from the previous one resets the counters: two distinct faults must not add
-- up towards a server hop.
function RecoveryController:begin(cause)
    cause = CAUSES[cause] and cause or "unknown"
    if cause ~= self.cause then
        self.cause = cause
        self.attempts = 0
        self.redetects = 0
    end
    self.enteredAt = os.clock()
    self.ctx.stats.recoveries = self.ctx.stats.recoveries + 1
    Log.Recovery("cause:", cause)
end

function RecoveryController:reset()
    self.cause = nil
    self.attempts = 0
    self.redetects = 0
    self.failures = 0
end

---------------------------------------------------------------------------
-- Rungs
---------------------------------------------------------------------------

-- 1 and 2: rescan and recompute. Always attempted, whatever the cause.
function RecoveryController:localRepair(profile)
    local ctx = self.ctx

    if profile.wipe then
        ctx.map:clear("recovery after a server change")
    end
    if profile.invalidateAnchor then
        SafeCombatAnchor.invalidate(ctx, "recovery")
    end
    if profile.resetTravel then
        TravelController.stop(ctx)
    end
    if profile.invalidateGiver then
        ctx.map:invalidate("QuestGivers", nil, "recovery")
        ctx.questGiver = nil
    end

    -- The forced rescan ignores the pacing: we need a fresh picture now, not
    -- at the next interval.
    self.perception:rescan("recovery (" .. tostring(self.cause) .. ")")
end

-- 3: has the cause gone away?
function RecoveryController:resolved()
    local ctx = self.ctx
    local cause = self.cause

    if cause == "player_dead" then
        return ctx.player.alive()
    elseif cause == "map_not_loaded" then
        return ctx.world.enemies() ~= nil and ctx.world.locations() ~= nil
    elseif cause == "target_missing" or cause == "target_died_in_bring"
        or cause == "target_returned_spawn" or cause == "combat_interrupted" then
        return #ctx.targets > 0
    elseif cause == "quest_lost" or cause == "quest_not_taken" then
        return ctx.quest ~= nil and ctx.quest.Active
    elseif cause == "quest_giver_missing" then
        return ctx.questGiver ~= nil
    elseif cause == "invalid_position" then
        return SafeCombatAnchor.compute(ctx, true) ~= nil
    elseif cause == "server_changed" then
        return ctx.sea ~= nil and ctx.island ~= nil
    end

    return false
end

---------------------------------------------------------------------------
-- Cycle
---------------------------------------------------------------------------

-- One recovery step. Returns the state to move to, or nil to stay in RECOVERY
-- for another turn.
function RecoveryController:step()
    local ctx = self.ctx
    local cfg = ctx.cfg.Recovery
    local profile = CAUSES[self.cause or "unknown"]

    local now = os.clock()
    if now - self.lastAttempt < cfg.Cooldown then return nil end
    self.lastAttempt = now

    self.attempts = self.attempts + 1

    -- A dead player is not a fault: wait for the respawn without recomputing
    -- anything (it would all have to be redone afterwards).
    if self.cause == "player_dead" then
        if ctx.player.alive() then
            Log.Recovery("player respawned -- resuming")
            self:reset()
            return profile.resume
        end
        return nil
    end

    -- Rungs 1 and 2.
    self:localRepair(profile)

    -- Rung 3: resume in place.
    if self:resolved() then
        Log.Recovery("resolved after", self.attempts, "attempt(s) -- resuming at", profile.resume)
        self:reset()
        return profile.resume
    end

    -- Rung 4: full re-detection.
    if self.attempts >= cfg.MaxLocalAttempts then
        self.redetects = self.redetects + 1
        self.attempts = 0
        self.failures = self.failures + 1

        if self.redetects <= cfg.MaxRedetects then
            Log.Recovery("rescan insufficient -- full re-detection")
            ctx.map:clear("re-detection")
            ctx.region = nil
            ctx.questGiver = nil
            return "DETECT_SEA"
        end
    end

    -- Rung 5: server change. Reserved for causes that cannot resolve here --
    -- typically a boss absent from this server.
    local hopWorthy = profile.class == "fatal" or self.failures >= cfg.HopAfterFailures
    if hopWorthy then
        Log.Recovery("exhausted locally (" .. tostring(self.cause) .. ") -- changing server")
        self:reset()
        return "SERVER_HOP"
    end

    return nil
end

-- Detects causes nobody reported explicitly. Called on every core turn, before
-- the state machine.
function RecoveryController:detectImplicit(ctx)
    if not ctx.player.alive() then return "player_dead" end
    if not ctx.world.enemies() then return "map_not_loaded" end
    return nil
end

return RecoveryController
