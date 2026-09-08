--=============================================================================
-- QUEST FARM — the quest-farming state machine
--=============================================================================
--  Each state declares its entry, timeout, success condition, failure
--  condition and next state. No state loops in place without a limit: a block
--  becomes a transition to RECOVERY, not a freeze.
--
--  The target selection flow is mandated and cannot be short-circuited:
--
--      DETECT_QUEST -> SCAN_TARGETS -> BUILD_TARGET_GROUP -> BRING_TARGETS
--          (QuestDetector) (EnemyScanner)  (TargetValidator)  (BringController)
--
--  BringController therefore never receives anything but a list already
--  validated against the active quest.
--=============================================================================

local AttackController = require("AutomationCore.Combat.AttackController")
local BringController = require("AutomationCore.Combat.BringController")
local Log = require("AutomationCore.Log")
local QuestTravel = require("AutomationCore.Movement.QuestTravel")
local RoutePlanner = require("AutomationCore.Farming.RoutePlanner")
local SafeCombatAnchor = require("AutomationCore.Movement.SafeCombatAnchor")
local StateMachine = require("AutomationCore.StateMachine")
local TargetTravel = require("AutomationCore.Movement.TargetTravel")
local TravelController = require("AutomationCore.Movement.TravelController")

local QuestFarm = {}
QuestFarm.__index = QuestFarm

function QuestFarm.new(ctx, perception, recovery)
    local self = setmetatable({
        ctx = ctx,
        perception = perception,
        recovery = recovery,
        bring = BringController.new(ctx),
        attack = AttackController.new(ctx),
        plan = nil,
        acceptedPlan = nil,
        acceptedAt = 0,
        machine = nil,
    }, QuestFarm)

    self.machine = StateMachine.new("QuestFarm", ctx)
    self:defineStates()
    return self
end

function QuestFarm:bringEnabled()
    return self.ctx.legacyConfig.Farming.BringMob == true
end

-- Shorthand: request a recovery with an explicit cause.
function QuestFarm:recover(cause)
    self.recovery:begin(cause)
    return "RECOVERY"
end

---------------------------------------------------------------------------
-- States
---------------------------------------------------------------------------

function QuestFarm:defineStates()
    local ctx = self.ctx
    local perception = self.perception

    self.machine:defineAll({

        -----------------------------------------------------------------
        IDLE = {
            update = function()
                if not ctx.flags.farming() then return nil end
                return "CHECK_REQUIREMENTS"
            end,
        },

        -----------------------------------------------------------------
        -- Checks what nothing else makes sense without. Better to wait here
        -- than to start detecting against a half-loaded world.
        CHECK_REQUIREMENTS = {
            timeout = 30,
            onTimeout = function() return self:recover("map_not_loaded") end,
            update = function()
                if not ctx.player.alive() then return self:recover("player_dead") end
                if not ctx.world.enemies() then return nil end
                if not ctx.world.locations() then return nil end
                return "DETECT_SEA"
            end,
        },

        -----------------------------------------------------------------
        DETECT_SEA = {
            timeout = 10,
            onTimeout = "DETECT_ISLAND",
            update = function()
                perception:detectSea()
                if not ctx.sea then return nil end
                return "DETECT_ISLAND"
            end,
        },

        -----------------------------------------------------------------
        DETECT_ISLAND = {
            timeout = 10,
            onTimeout = "DETECT_QUEST",
            update = function()
                perception:detectIsland()
                return "DETECT_QUEST"
            end,
        },

        -----------------------------------------------------------------
        -- The pivot of the whole machine. An active, readable quest skips the
        -- entire "go and pick up a quest" branch.
        DETECT_QUEST = {
            timeout = 20,
            onTimeout = function() return self:recover("quest_lost") end,
            update = function()
                local quest = perception:detectQuest(true)

                if quest.Active and quest.TargetName then
                    if quest.Remaining <= 0 then return "TURN_IN" end
                    return "SCAN_TARGETS"
                end

                -- Quest active but the objective is unreadable, even after
                -- QuestDetector's own catalogue fallback: if we are the ones
                -- who just accepted this quest, we already know its target --
                -- no need to abandon it over a UI we failed to parse. The
                -- short window guards against pinning a stale plan onto some
                -- unrelated quest the player picked up another way.
                if quest.Active and not quest.TargetName then
                    if self.acceptedPlan and os.clock() - (self.acceptedAt or 0) < 20 then
                        quest.TargetRaw = self.acceptedPlan.targetRaw
                        quest.TargetName = self.acceptedPlan.targetName
                        quest.RequiredCount = math.huge
                        quest.Remaining = math.huge
                        Log.Quest("objective unreadable -- using the plan we just accepted:",
                            quest.TargetRaw)
                        return "SCAN_TARGETS"
                    end

                    Log.Quest("objective unreadable -- abandoning the quest")
                    QuestTravel.abandon(ctx)
                    return nil
                end

                -- No quest: plan one.
                if RoutePlanner.isStale(ctx, self.plan, perception.scanner) then
                    self.plan = RoutePlanner.plan(ctx, perception.scanner)
                end
                if not self.plan then return nil end
                return "FIND_QUEST_GIVER"
            end,
        },

        -----------------------------------------------------------------
        FIND_QUEST_GIVER = {
            timeout = 12,
            onTimeout = function() return self:recover("quest_giver_missing") end,
            enter = function()
                if not self.plan then return end
                -- The static fallback is handed to the resolver but stays at
                -- the lowest trust level: it is used only if no NPC matches.
                perception:setQuestGiverHints(self.plan.hints, self.plan.giverFallback)
            end,
            update = function()
                if not self.plan then return "DETECT_QUEST" end
                local position = perception:refreshQuestGiver()
                if not position then return nil end
                return "TRAVEL_TO_QUEST"
            end,
        },

        -----------------------------------------------------------------
        TRAVEL_TO_QUEST = {
            timeout = 45,
            onTimeout = function() return self:recover("movement_blocked") end,
            exit = function() TravelController.reset(ctx) end,
            update = function()
                -- A quest that appeared meanwhile (picked up some other way)
                -- makes the journey pointless.
                if perception:detectQuest().Active then return "DETECT_QUEST" end

                local status = QuestTravel.step(ctx, self.plan)
                if status == "arrived" then return "ACCEPT_QUEST" end
                if status == "unreachable" then return self:recover("quest_giver_missing") end
                if status == "unknown" then return "FIND_QUEST_GIVER" end
                return nil
            end,
        },

        -----------------------------------------------------------------
        -- Accepting a quest is not instant: we request it, then wait for the
        -- UI to confirm. Without that wait the old code immediately moved on
        -- and re-requested in a loop.
        ACCEPT_QUEST = {
            timeout = 8,
            onTimeout = function() return self:recover("quest_not_taken") end,
            enter = function()
                QuestTravel.accept(ctx, self.plan)
            end,
            update = function()
                local quest = perception:detectQuest(true)
                if quest.Active then
                    -- Remember what we just accepted: DETECT_QUEST falls back
                    -- to it if the quest panel's text turns out unreadable.
                    self.acceptedPlan = self.plan
                    self.acceptedAt = os.clock()
                    return "DETECT_QUEST"
                end

                -- Re-request once a second while the NPC is in range: the
                -- remote fails if we have drifted away.
                if self.machine:elapsed() > 2 then
                    QuestTravel.accept(ctx, self.plan)
                    self.machine.enteredAt = os.clock() - 2
                end
                return nil
            end,
        },

        -----------------------------------------------------------------
        SCAN_TARGETS = {
            timeout = 12,
            onTimeout = function() return self:recover("target_missing") end,
            update = function()
                perception:update(true)

                if not ctx.quest.Active then return self:recover("quest_lost") end
                if ctx.quest.Remaining <= 0 then return "CHECK_PROGRESS" end

                if #ctx.targets > 0 then
                    Log.Target("Found", #ctx.targets, "valid targets")
                    return "BUILD_TARGET_GROUP"
                end

                -- Nothing valid: the zone may not be active yet.
                return "ACTIVATE_SPAWN"
            end,
        },

        -----------------------------------------------------------------
        -- Many spawns only trigger when the player gets close. Before
        -- concluding they are absent, go there.
        ACTIVATE_SPAWN = {
            timeout = 35,
            onTimeout = function() return self:recover("target_missing") end,
            exit = function() TravelController.reset(ctx) end,
            update = function()
                local status = TargetTravel.step(ctx, self.plan)

                -- A rescan on every step: as soon as the zone populates we
                -- move on without waiting for the journey to finish.
                perception:update(true)
                if #ctx.targets > 0 then
                    Log.Target("zone activated --", #ctx.targets, "target(s)")
                    return "BUILD_TARGET_GROUP"
                end

                if status == "unknown" then
                    -- No destination at all: no target, no region, no island.
                    -- The plan itself is suspect.
                    self.plan = nil
                    return self:recover("target_missing")
                end
                if status == "unreachable" then
                    return self:recover("movement_blocked")
                end
                return nil
            end,
        },

        -----------------------------------------------------------------
        -- Assembles the group to engage. Here, and nowhere else, is the list
        -- handed to the bring settled.
        BUILD_TARGET_GROUP = {
            timeout = 8,
            onTimeout = "SCAN_TARGETS",
            update = function()
                perception:refreshSpawnRegion()
                perception:refreshTargets()

                if #ctx.targets == 0 then return "SCAN_TARGETS" end
                if ctx.quest.Remaining <= 0 then return "CHECK_PROGRESS" end

                -- The anchor must exist before the bring: without it, mobs
                -- would be placed on an unvalidated position.
                if self:bringEnabled() then
                    local anchor = SafeCombatAnchor.compute(ctx, true)
                    if not anchor then return self:recover("invalid_position") end
                    self.bring:publishAnchor(anchor)
                    Log.Bring("Building group of",
                        math.min(#ctx.targets, ctx.cfg.Bring.MaxTargets))
                    return "BRING_TARGETS"
                end

                return "ATTACK"
            end,
        },

        -----------------------------------------------------------------
        BRING_TARGETS = {
            timeout = 15,
            onTimeout = function() return self:recover("target_returned_spawn") end,
            enter = function()
                ctx.bringActive = true
                self.bring:attach()
                perception:setCombat(true)
            end,
            exit = function()
                ctx.bringActive = false
                self.bring:detach()
            end,
            update = function()
                if not ctx.quest.Active then return self:recover("quest_lost") end
                if ctx.quest.Remaining <= 0 then return "CHECK_PROGRESS" end

                perception:refreshTargets()
                if #ctx.targets == 0 then return "SCAN_TARGETS" end

                local anchor = SafeCombatAnchor.compute(ctx)
                if not anchor then return self:recover("invalid_position") end
                self.bring:publishAnchor(anchor)

                local report = self.bring:update(ctx.targets, ctx.quest)

                if report.status == "too_far" then
                    -- PullLimit: we do not drag the mob across the map, the
                    -- player moves instead, then we recompute.
                    return "ACTIVATE_SPAWN"
                end
                if report.status == "no_anchor" then
                    return self:recover("invalid_position")
                end
                if report.status == "no_targets" then
                    return "SCAN_TARGETS"
                end

                -- As soon as one target is in place, strike. The ATTACK state
                -- keeps the bring running: the two work together.
                if report.placed > 0 then return "ATTACK" end
                return nil
            end,
        },

        -----------------------------------------------------------------
        ATTACK = {
            timeout = 30,
            onTimeout = function() return self:recover("combat_interrupted") end,
            enter = function()
                perception:setCombat(true)
                -- The bring stays active during the attack when it is
                -- requested: otherwise mobs scatter on the first blow.
                if self:bringEnabled() then
                    ctx.bringActive = true
                    self.bring:attach()
                end
            end,
            exit = function()
                perception:setCombat(false)
                self.attack:clear(nil)
            end,
            update = function()
                if not ctx.player.alive() then return self:recover("player_dead") end
                if not ctx.quest.Active then return self:recover("quest_lost") end

                perception:refreshTargets()
                if ctx.quest.Remaining <= 0 then return "CHECK_PROGRESS" end

                if self:bringEnabled() then
                    local anchor = SafeCombatAnchor.compute(ctx)
                    if anchor then self.bring:publishAnchor(anchor) end
                end

                local status = self.attack:engage(ctx.targets, ctx.quest)

                if status == "killed" then return "CHECK_PROGRESS" end
                if status == "idle" then return "SCAN_TARGETS" end
                if status == "lost" then
                    -- Target lost without dying: it may have returned to its
                    -- spawn.
                    return "BUILD_TARGET_GROUP"
                end
                if status == "timeout" then return self:recover("combat_interrupted") end
                if status == "blocked" then return nil end

                -- The ATTACK state is not left after every blow: we stay here
                -- as long as a valid target is engaged.
                return nil
            end,
        },

        -----------------------------------------------------------------
        CHECK_PROGRESS = {
            timeout = 6,
            onTimeout = "DETECT_QUEST",
            update = function()
                local quest = perception:detectQuest(true)

                if not quest.Active then
                    -- The quest is gone: either it was just completed, or it
                    -- was lost. DETECT_QUEST will settle it.
                    return "DETECT_QUEST"
                end

                if quest.Remaining <= 0 then return "TURN_IN" end

                if #ctx.targets > 0 then
                    return self:bringEnabled() and "BRING_TARGETS" or "ATTACK"
                end
                return "SCAN_TARGETS"
            end,
        },

        -----------------------------------------------------------------
        -- Most quests complete on their own at the last kill. We wait for
        -- that; if it does not come, we go back to the giver, since some
        -- quests require it.
        TURN_IN = {
            timeout = 20,
            onTimeout = function() return self:recover("quest_lost") end,
            enter = function()
                Log.Quest("Complete")
                perception:setCombat(false)
            end,
            update = function()
                local quest = perception:detectQuest(true)

                if not quest.Active then
                    Log.Quest("reward confirmed")
                    self.plan = nil
                    return "DETECT_QUEST"
                end

                if self.machine:elapsed() > 4 and ctx.questGiver then
                    local status = QuestTravel.step(ctx, self.plan)
                    if status == "unreachable" then return "DETECT_QUEST" end
                end
                return nil
            end,
        },

        -----------------------------------------------------------------
        RECOVERY = {
            -- No timeout: the controller decides the escalation, including
            -- when to give up.
            enter = function()
                perception:setCombat(false)
                self.attack:clear("recovery")
                self.bring:detach()
                ctx.bringActive = false
            end,
            update = function()
                return self.recovery:step()
            end,
        },

        -----------------------------------------------------------------
        SERVER_HOP = {
            timeout = 30,
            onTimeout = "IDLE",
            enter = function()
                Log.ServerHop("server change requested")
                -- Everything learned here will be wrong over there.
                ctx.map:clear("server change")
                ctx.region = nil
                ctx.questGiver = nil
                self.plan = nil
                pcall(function() ctx.server.hop(true) end)
            end,
            update = function() return nil end,
        },

        -----------------------------------------------------------------
        -- Hook for special objectives (CDK, event quests). The core switches
        -- here on explicit request; QuestFarm never goes there on its own.
        SPECIAL_OBJECTIVE = {
            timeout = 600,
            onTimeout = "DETECT_QUEST",
            update = function()
                local handler = ctx.specialObjective
                if not handler then return "DETECT_QUEST" end
                local status = handler:step()
                if status == "done" or status == "failed" then
                    ctx.specialObjective = nil
                    return "DETECT_QUEST"
                end
                return nil
            end,
        },
    })

    self.machine:goTo("IDLE", "startup")
end

---------------------------------------------------------------------------
-- Cycle
---------------------------------------------------------------------------

function QuestFarm:update()
    local ctx = self.ctx

    -- Stopped from the interface: hand back cleanly, leaving no anchor and no
    -- bring driver behind.
    if not ctx.flags.farming() then
        if not self.machine:is("IDLE") then
            self.machine:goTo("IDLE", "farm stopped")
        end
        return
    end

    -- Implicit causes, detected before the machine: a dead player or an
    -- unloaded map short-circuits the current state.
    local implicit = self.recovery:detectImplicit(ctx)
    if implicit and not self.machine:is("RECOVERY") and not self.machine:is("SERVER_HOP") then
        self.recovery:begin(implicit)
        self.machine:goTo("RECOVERY", implicit)
        return
    end

    self.perception:update(false)
    self.machine:update()
end

function QuestFarm:stop()
    self.bring:detach()
    self.attack:clear("stop")
    TravelController.stop(self.ctx)
    self.machine:goTo("IDLE", "stop")
end

function QuestFarm:describe()
    return string.format("[%s] %s | %s",
        tostring(self.machine.current),
        self.perception:describe(),
        self.bring:describe())
end

return QuestFarm
