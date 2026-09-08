--=============================================================================
-- AUTOMATION CORE — assembly
--=============================================================================
--  One context, one perception, one recovery, shared by every farming mode.
--  That is the answer to "let each farming system use the same
--  AutomationCore": switching from QuestFarm to MaterialFarm rebuilds neither
--  the enemy index, nor the map memory, nor the recovery ladder.
--
--  Only one mode is active at a time. Changing mode stops the previous one
--  cleanly -- without that, two state machines would fight over the player's
--  position.
--=============================================================================

local BossFarm = require("AutomationCore.Farming.BossFarm")
local CDKController = require("AutomationCore.SpecialObjectives.CDKController")
local Context = require("AutomationCore.Context")
local Log = require("AutomationCore.Log")
local MasteryFarm = require("AutomationCore.Farming.MasteryFarm")
local MaterialFarm = require("AutomationCore.Farming.MaterialFarm")
local Perception = require("AutomationCore.Perception")
local QuestFarm = require("AutomationCore.Farming.QuestFarm")
local RecoveryController = require("AutomationCore.Recovery.RecoveryController")
local ServerHop = require("AutomationCore.Farming.ServerHop")
local SpecialFarm = require("AutomationCore.Farming.SpecialFarm")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")

local AutomationCore = {}
AutomationCore.__index = AutomationCore

AutomationCore.MODES = { "Quest", "Boss", "Mastery", "Material", "Special" }

function AutomationCore.new(internal)
    local ctx = Context.new(internal)
    local perception = Perception.new(ctx)
    local recovery = RecoveryController.new(ctx, perception)

    local self = setmetatable({
        ctx = ctx,
        perception = perception,
        recovery = recovery,
        serverHop = ServerHop.new(ctx),
        mode = "Quest",
        lastReport = 0,
    }, AutomationCore)

    self.modes = {
        Quest = QuestFarm.new(ctx, perception, recovery),
        Boss = BossFarm.new(ctx, perception, recovery),
        Mastery = MasteryFarm.new(ctx, perception, recovery),
        Material = MaterialFarm.new(ctx, perception, recovery),
        Special = SpecialFarm.new(ctx),
    }

    -- CDK delegates its final boss to BossFarm: hand it the same instance
    -- rather than a second one, which would fight over the same character.
    ctx.bossFarm = self.modes.Boss

    Log.write("Core", "AutomationCore ready --", #AutomationCore.MODES, "modes")
    return self
end

---------------------------------------------------------------------------
-- Modes
---------------------------------------------------------------------------

function AutomationCore:active()
    return self.modes[self.mode]
end

function AutomationCore:setMode(mode)
    if not self.modes[mode] then
        Log.write("Core", "unknown mode:", tostring(mode))
        return false
    end
    if mode == self.mode then return true end

    -- Explicit stop: the old mode must release the anchor, the bring driver
    -- and its target before the next one touches the character.
    local previous = self:active()
    if previous and previous.stop then previous:stop() end

    self.mode = mode
    Log.write("Core", "mode =", mode)
    return true
end

---------------------------------------------------------------------------
-- Configuration shorthands
---------------------------------------------------------------------------

function AutomationCore:farmBoss(name)
    if not self.modes.Boss:setBoss(name) then return false end
    return self:setMode("Boss")
end

function AutomationCore:farmMaterial(name)
    self.modes.Material:setMaterial(name)
    return self:setMode("Material")
end

-- kind : "Sword" | "Fruit" | "FightingStyle" | "Gun"
function AutomationCore:farmMastery(kind, target)
    if not self.modes.Mastery:setWeapon(kind) then return false end
    if target then self.modes.Mastery:setTarget(target) end
    return self:setMode("Mastery")
end

function AutomationCore:farmQuest()
    return self:setMode("Quest")
end

-- CDK is a special objective: it plugs in and out without QuestFarm knowing
-- anything about it.
function AutomationCore:startCDK()
    local controller = CDKController.new(self.ctx, self.perception, self.recovery)

    local ok, reason = controller:requirements()
    if not ok then
        Log.CDK("refused:", reason)
        return false, reason
    end

    self.modes.Special:setObjective("CDK", controller)
    return self:setMode("Special")
end

function AutomationCore:stopSpecial()
    self.modes.Special:stop()
    return self:setMode("Quest")
end

---------------------------------------------------------------------------
-- Cycle
---------------------------------------------------------------------------

-- Single entry point, called by the runtime's farming loop.
function AutomationCore:update()
    local mode = self:active()
    if not mode then return end

    local ok, err = pcall(function() mode:update() end)
    if not ok then
        -- An error must never kill the loop: log it and let recovery pick up
        -- next turn.
        Log.write("Core", "error in mode", self.mode, ":", err)
        self.recovery:begin("unknown")
    end

    -- Periodic summary: current state and target rejection reasons. This is
    -- what lets a "0 valid targets" be diagnosed without turning logs back on.
    local now = os.clock()
    if now - self.lastReport > 20 then
        self.lastReport = now
        TargetValidator.logRejections("Target")
    end
end

function AutomationCore:stop()
    for _, mode in pairs(self.modes) do
        if mode.stop then pcall(function() mode:stop() end) end
    end
    self.ctx.legacy.State.bringDriver = nil
    self.ctx.legacy.State.bringAnchor = nil
end

function AutomationCore:describe()
    local mode = self:active()
    local detail = mode and mode.describe and mode:describe() or "-"
    return string.format("%s | %s | %s", self.mode, detail, self.serverHop:describe())
end

function AutomationCore:stats()
    return self.ctx.stats
end

return AutomationCore
