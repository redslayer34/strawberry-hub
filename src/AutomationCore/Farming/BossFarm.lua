--=============================================================================
-- BOSS FARM — a boss is asked for, never picked up in passing
--=============================================================================
--  Non-negotiable rule: a boss NEVER enters an ordinary bring. That is what
--  used to desync fights -- a boss vacuumed into the middle of a pack of
--  normal mobs, with its health and its damage, blocking the farm with
--  nothing reporting it.
--
--  Authorisation goes through a synthetic objective carrying AllowBoss, the
--  only flag TargetValidator accepts to lift the exclusion. No other module
--  sets it.
--=============================================================================

local AttackController = require("AutomationCore.Combat.AttackController")
local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")
local StateMachine = require("AutomationCore.StateMachine")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")
local TravelController = require("AutomationCore.Movement.TravelController")

local BossFarm = {}
BossFarm.__index = BossFarm

function BossFarm.new(ctx, perception, recovery)
    local self = setmetatable({
        ctx = ctx,
        perception = perception,
        recovery = recovery,
        attack = AttackController.new(ctx),
        bossName = nil,
        objective = nil,
        lastSeenHealth = nil,
        killedAt = nil,
        machine = nil,
    }, BossFarm)

    self.machine = StateMachine.new("BossFarm", ctx)
    self:defineStates()
    return self
end

-- The boss must be named explicitly. Without a call to setBoss, this module
-- does nothing at all.
function BossFarm:setBoss(name)
    local canonical = Names.normalize(name)
    if not canonical then
        Log.Boss("invalid boss name:", tostring(name))
        return false
    end

    self.bossName = name
    self.objective = {
        Active = true,
        QuestName = "BossFarm",
        TargetRaw = name,
        TargetName = canonical,
        RequiredCount = 1,
        CurrentCount = 0,
        Remaining = 1,
        IsBossQuest = true,
        -- The only place in the system that sets this flag.
        AllowBoss = true,
    }
    Log.Boss("target:", name)
    return true
end

function BossFarm:candidates()
    if not self.objective then return {} end
    local raw = self.perception.scanner:candidatesFor(self.objective.TargetName)
    return TargetValidator.filter(self.ctx, raw, self.objective)
end

function BossFarm:defineStates()
    local ctx = self.ctx
    local perception = self.perception

    self.machine:defineAll({

        IDLE = {
            update = function()
                if not self.objective then return nil end
                return "SEARCH"
            end,
        },

        -- Search on the current server. An absent boss is not a local fault:
        -- it is dead and not yet respawned, or it does not exist here. This is
        -- the one case where changing server is the right reflex rather than a
        -- stopgap.
        SEARCH = {
            timeout = 20,
            onTimeout = "AWAIT_RESPAWN",
            update = function()
                perception:update(true)
                local found = self:candidates()
                if #found > 0 then
                    Log.Boss("found --", #found, "instance(s)")
                    return "TRAVEL"
                end
                return nil
            end,
        },

        TRAVEL = {
            timeout = 60,
            onTimeout = "SEARCH",
            exit = function() TravelController.reset(ctx) end,
            update = function()
                local found = self:candidates()
                local boss = found[1]
                if not boss then return "SEARCH" end

                if TravelController.distanceTo(ctx, boss.position) <= ctx.cfg.Bring.Radius then
                    return "COMBAT"
                end

                local ok = TravelController.step(ctx, boss.position, {
                    lift = ctx.cfg.Anchor.Height,
                    validate = true,
                })
                if not ok or TravelController.isStuck(ctx) then
                    TravelController.reset(ctx)
                    return "SEARCH"
                end
                return nil
            end,
        },

        COMBAT = {
            -- Generous: a boss soaks damage for a long time. The real
            -- safeguard is the absence of damage, handled by AttackController.
            timeout = 300,
            onTimeout = "SEARCH",
            enter = function() perception:setCombat(true) end,
            exit = function()
                perception:setCombat(false)
                self.attack:clear(nil)
            end,
            update = function()
                if not ctx.player.alive() then
                    self.recovery:begin("player_dead")
                    return "AWAIT_RESPAWN"
                end

                perception:update(false)
                local found = self:candidates()

                local status = self.attack:engage(found, self.objective)

                if status == "killed" then return "CONFIRM_KILL" end
                if status == "idle" then
                    -- No valid boss left while we were engaging one: either it
                    -- died or it vanished. CONFIRM_KILL settles it on an
                    -- observation, not an assumption.
                    return "CONFIRM_KILL"
                end
                if status == "timeout" then return "SEARCH" end
                return nil
            end,
        },

        -- We do not declare a boss dead because it left the index: we check no
        -- living instance remains, after a delay.
        CONFIRM_KILL = {
            timeout = 10,
            onTimeout = "SEARCH",
            enter = function() self.killedAt = os.clock() end,
            update = function()
                if os.clock() - (self.killedAt or 0) < ctx.cfg.Boss.KillConfirmDelay then
                    return nil
                end

                perception:update(true)
                if #self:candidates() > 0 then
                    Log.Boss("still alive -- resuming combat")
                    return "COMBAT"
                end

                Log.Boss("kill confirmed")
                return "AWAIT_RESPAWN"
            end,
        },

        AWAIT_RESPAWN = {
            timeout = 180,
            onTimeout = "SERVER_HOP",
            update = function()
                if self.machine:elapsed() % ctx.cfg.Boss.RespawnPoll > 0.5 then return nil end
                perception:update(true)
                if #self:candidates() > 0 then
                    Log.Boss("respawned")
                    return "TRAVEL"
                end
                return nil
            end,
        },

        SERVER_HOP = {
            timeout = 30,
            onTimeout = "IDLE",
            enter = function()
                Log.Boss("absent from this server -- changing")
                ctx.map:clear("boss absent")
                pcall(function() ctx.server.hop(true) end)
            end,
            update = function() return nil end,
        },

        -- Reached by the state machine when an update raises. The recovery
        -- controller thinks in QuestFarm states: they MUST be mapped back onto
        -- this machine's, otherwise goTo falls back to RECOVERY (unknown
        -- state) and the machine spins without ever advancing.
        RECOVERY = {
            update = function()
                local resume = self.recovery:step()
                if not resume then return nil end
                if resume == "SERVER_HOP" then return "SERVER_HOP" end
                if resume == "AWAIT_RESPAWN" then return "AWAIT_RESPAWN" end
                return "SEARCH"
            end,
        },
    })

    self.machine:goTo("IDLE", "startup")
end

function BossFarm:update()
    if not self.objective then return end
    self.perception:update(false)
    self.machine:update()
end

function BossFarm:stop()
    self.attack:clear("stop")
    TravelController.stop(self.ctx)
    self.objective = nil
    self.bossName = nil
    self.machine:goTo("IDLE", "stop")
end

function BossFarm:describe()
    return string.format("[%s] boss=%s", tostring(self.machine.current),
        tostring(self.bossName))
end

return BossFarm
