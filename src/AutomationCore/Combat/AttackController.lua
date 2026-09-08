--=============================================================================
-- ATTACK CONTROLLER — engage a target, one step at a time
--=============================================================================
--  The old `engage()` was a blocking `while` loop: while it ran, nothing else
--  could -- not re-reading the quest, not detecting an island change, not
--  recovery. One unreachable mob froze the whole farm until its timeout.
--
--  Here every call takes one step and hands control back. The state machine
--  stays in charge, and the target lock that makes farming efficient is kept:
--  we do not re-sweep the Workspace between blows.
--
--  Before every blow: ValidateTarget then ValidateCombatState. No operation is
--  performed on a reference that has aged.
--=============================================================================

local CombatPositionController = require("AutomationCore.Combat.CombatPositionController")
local Log = require("AutomationCore.Log")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")

local AttackController = {}
AttackController.__index = AttackController

function AttackController.new(ctx)
    return setmetatable({
        ctx = ctx,
        entry = nil,
        lastHealth = nil,
        lastProgress = 0,
        lastStrike = 0,
        engagedAt = 0,
        kills = 0,
    }, AttackController)
end

function AttackController:target() return self.entry end

function AttackController:clear(reason)
    if self.entry and reason then
        Log.Combat("target released --", reason)
    end
    self.entry = nil
    self.lastHealth = nil
    self.ctx.attack.release()
end

function AttackController:setTarget(entry)
    if self.entry and self.entry.model == entry.model then return end
    self.entry = entry
    self.lastHealth = entry.humanoid and entry.humanoid.Health or nil
    self.lastProgress = os.clock()
    self.engagedAt = os.clock()
    Log.Combat("Started --", entry.name)
end

-- Picks the nearest target from an ALREADY validated list. No extra filtering
-- here: this module does not judge validity.
function AttackController:pick(targets)
    local here = self.ctx:pos()
    if not here or not targets or #targets == 0 then return nil end

    local best, bestDist
    for _, entry in ipairs(targets) do
        local d = (entry.position - here).Magnitude
        if not bestDist or d < bestDist then best, bestDist = entry, d end
    end
    return best
end

-- One combat step.
-- Returns "attacking" | "killed" | "lost" | "timeout" | "blocked" | "idle".
function AttackController:step(quest)
    local ctx = self.ctx
    local entry = self.entry

    if not entry then return "idle" end

    -- 1. Is the target still a target? A quest that changes mid-fight must
    -- interrupt the blow in progress, not finish it.
    local valid, reason = TargetValidator.stillValid(ctx, entry, quest)
    if not valid then
        local dead = entry.humanoid and entry.humanoid.Health <= 0
        self:clear(nil)
        if dead then
            self.kills = self.kills + 1
            ctx.stats.kills = ctx.stats.kills + 1
            return "killed"
        end
        Log.Combat("target lost --", reason)
        return "lost"
    end

    -- 2. Are we in a state to strike?
    local ready, why = CombatPositionController.validateCombatState(ctx)
    if not ready then
        return "blocked", why
    end

    -- 3. Progress: losing health is the proof the fight is going anywhere.
    -- Without this check, an invulnerable or desynced mob blocked the loop.
    local health = entry.humanoid.Health
    if self.lastHealth and health < self.lastHealth then
        self.lastProgress = os.clock()
    end
    self.lastHealth = health

    if os.clock() - self.lastProgress > ctx.cfg.Combat.EngageTimeout then
        Log.Combat("no damage for", ctx.cfg.Combat.EngageTimeout, "s -- giving up")
        self:clear(nil)
        return "timeout"
    end

    -- 4. Position then strike, at the configured rate.
    local now = os.clock()
    if now - self.lastStrike < ctx.cfg.Combat.AttackDelay then
        return "attacking"
    end
    self.lastStrike = now

    -- In bring mode the mobs come to us: stay on the anchor rather than chase
    -- each one.
    if not ctx.bringActive then
        CombatPositionController.hold(ctx, entry)
    end

    ctx.attack.strike(entry.model)
    return "attacking"
end

-- Engages the best available target and takes a step. Single entry point for
-- the ATTACK state.
function AttackController:engage(targets, quest)
    if not self.entry then
        local pick = self:pick(targets)
        if not pick then return "idle" end
        self:setTarget(pick)
    end
    return self:step(quest)
end

return AttackController
