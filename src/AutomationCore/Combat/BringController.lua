--=============================================================================
-- BRING CONTROLLER — bring the targets in, without deciding which
--=============================================================================
--  This module chooses NOTHING. It receives an already-filtered list and only
--  places it. The mandated flow is:
--
--      QuestDetector -> TargetSelector -> TargetValidator -> BringController
--
--  Two substantive differences from the old Move.bringMobs:
--
--  1. DISTINCT SLOTS. The old code wrote the same CFrame for every mob: they
--     overlapped, pushed each other away, and the server sent them flying.
--     Here each target gets its own slot around the anchor, and a dead mob's
--     slot is handed to the next one.
--
--  2. PULL LIMIT. A very distant mob is not teleported across the map (the
--     server rejects the jump, and the anti-cheat notices). We ask the
--     TravelController to move the PLAYER closer instead, then rescan.
--=============================================================================

local Log = require("AutomationCore.Log")
local SafeCombatAnchor = require("AutomationCore.Movement.SafeCombatAnchor")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")

local BringController = {}
BringController.__index = BringController

function BringController.new(ctx)
    return setmetatable({
        ctx = ctx,
        slots = {},        -- index -> { model = ..., since = ... }
        assigned = {},     -- model -> index
        lastRun = 0,
        lastAnchor = nil,
        moved = 0,
        tooFar = 0,
    }, BringController)
end

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------

-- Even distribution around a circle below the anchor. With MaxTargets = 6 that
-- gives exactly front / back / left / right plus two in between, but the
-- formula holds for any slot count.
function BringController:slotOffset(index)
    local cfg = self.ctx.cfg.Bring
    local count = math.max(1, cfg.MaxTargets)
    local angle = (index - 1) * (2 * math.pi / count)
    return Vector3.new(
        math.cos(angle) * cfg.SlotSpacing,
        -cfg.Height,
        math.sin(angle) * cfg.SlotSpacing)
end

function BringController:slotPosition(anchor, index)
    return anchor.Position + self:slotOffset(index)
end

-- Frees slots whose occupant is dead, gone, or no longer a valid target. This
-- is what makes the required reassignment possible.
function BringController:reclaim(quest)
    local ctx = self.ctx
    for index, slot in pairs(self.slots) do
        local model = slot.model
        local drop = false

        if not model or not model.Parent then
            drop = true
        else
            local entry = slot.entry
            if not entry or not TargetValidator.stillValid(ctx, entry, quest) then
                drop = true
            end
        end

        if drop then
            if model then self.assigned[model] = nil end
            self.slots[index] = nil
        end
    end
end

function BringController:freeSlot()
    local count = math.max(1, self.ctx.cfg.Bring.MaxTargets)
    for index = 1, count do
        if not self.slots[index] then return index end
    end
    return nil
end

---------------------------------------------------------------------------
-- Cycle
---------------------------------------------------------------------------

-- targets : an ALREADY validated list. quest : QuestState, used only to
-- revalidate occupants from one turn to the next.
-- Returns a report: { moved, tooFar, placed, anchor, status }.
function BringController:update(targets, quest)
    local ctx = self.ctx
    local cfg = ctx.cfg.Bring
    local report = { moved = 0, tooFar = 0, placed = 0, status = "idle" }

    local now = os.clock()
    if now - self.lastRun < cfg.Interval then
        report.status = "throttled"
        return report
    end
    self.lastRun = now

    if not targets or #targets == 0 then
        self:reclaim(quest)
        report.status = "no_targets"
        return report
    end

    -- The anchor is recomputed here, not kept: it is what guarantees the slots
    -- stay above ground when the pack moves.
    local anchor = SafeCombatAnchor.compute(ctx)
    if not anchor then
        report.status = "no_anchor"
        return report
    end
    report.anchor = anchor

    -- A sharp anchor move makes the assignments obsolete: the slots are no
    -- longer in the same place.
    if self.lastAnchor and (anchor.Position - self.lastAnchor.Position).Magnitude > cfg.SlotSpacing * 2 then
        table.clear(self.slots)
        table.clear(self.assigned)
    end
    self.lastAnchor = anchor

    self:reclaim(quest)

    local origin = anchor.Position
    local reachable = 0

    for _, entry in ipairs(targets) do
        local model = entry.model
        local root = entry.root
        if model and model.Parent and root and root.Parent then
            local distance = (root.Position - origin).Magnitude

            if distance > cfg.PullLimit then
                -- Too far: do not pull it. The player will go to it.
                report.tooFar = report.tooFar + 1
            elseif distance > cfg.Radius then
                -- Outside the collection radius, but not far enough to trigger
                -- a journey: simply skip it this turn.
                reachable = reachable + 1
            else
                reachable = reachable + 1

                local index = self.assigned[model]
                if not index then
                    index = self:freeSlot()
                    if index then
                        self.assigned[model] = index
                        self.slots[index] = { model = model, entry = entry, since = now }
                    end
                end

                if index then
                    report.placed = report.placed + 1
                    local goal = self:slotPosition(anchor, index)

                    -- Already in place: rewriting its position at 10 Hz means
                    -- fighting the server for nothing.
                    if (root.Position - goal).Magnitude > cfg.DeadZone then
                        local ok = SafeCombatAnchor.validatePosition(ctx, goal)
                        if ok then
                            root.CanCollide = false
                            root.CFrame = CFrame.new(goal)
                            root.AssemblyLinearVelocity = Vector3.zero
                            report.moved = report.moved + 1
                        else
                            -- The slot has gone bad: force the anchor to be
                            -- recomputed next turn.
                            SafeCombatAnchor.invalidate(ctx, "invalid slot")
                        end
                    end
                end
            end
        end
    end

    self.moved = report.moved
    self.tooFar = report.tooFar

    -- No reachable target while some exist: that is the PullLimit signal.
    -- QuestFarm must move the player closer and recompute the pack.
    if reachable == 0 and report.tooFar > 0 then
        report.status = "too_far"
        Log.Bring(report.tooFar, "target(s) out of reach -- moving the player closer")
    elseif report.placed > 0 then
        report.status = "bringing"
    else
        report.status = "no_targets"
    end

    return report
end

-- The player is held on the anchor by the runtime (60 Hz). We hand it the
-- anchor and the bring driver; we do not duplicate its loop.
function BringController:attach()
    local ctx = self.ctx
    local state = ctx.legacy.State
    state.bringDriver = function()
        local quest = ctx.quest
        self:update(ctx.targets, quest)
    end
end

function BringController:detach()
    local ctx = self.ctx
    ctx.legacy.State.bringDriver = nil
    ctx.legacy.State.bringAnchor = nil
    table.clear(self.slots)
    table.clear(self.assigned)
end

-- The player's flight position, read by the runtime every frame.
function BringController:publishAnchor(anchor)
    self.ctx.legacy.State.bringAnchor = anchor
end

function BringController:describe()
    local count = 0
    for _ in pairs(self.slots) do count = count + 1 end
    return string.format("%d slot(s) filled, %d moved, %d out of reach",
        count, self.moved, self.tooFar)
end

return BringController
