--=============================================================================
-- TRAVEL CONTROLLER — getting somewhere, and knowing when you are not
--=============================================================================
--  The movement itself is still the runtime's (speed-capped tween, short
--  teleport below the threshold). What was missing is supervision: a tween
--  launched at a point that has become unreachable never reported it, and the
--  farm sat stuck halfway with no timeout noticing.
--
--  Here every journey has a target, a starting distance and a clock. If it
--  stops making progress, it says so; the state machine handles it.
--=============================================================================

local Log = require("AutomationCore.Log")
local SafeCombatAnchor = require("AutomationCore.Movement.SafeCombatAnchor")

local TravelController = {}

local function toVector(target)
    if not target then return nil end
    if typeof(target) == "Vector3" then return target end
    if typeof(target) == "CFrame" then return target.Position end
    if typeof(target) == "Instance" and target:IsA("BasePart") then return target.Position end
    return nil
end

---------------------------------------------------------------------------
-- Supervision
---------------------------------------------------------------------------

local function tracker(ctx)
    ctx.travel = ctx.travel or {
        target = nil,
        startedAt = 0,
        lastPos = nil,
        lastProgressAt = 0,
        bestDistance = math.huge,
    }
    return ctx.travel
end

function TravelController.reset(ctx)
    ctx.travel = nil
end

-- True when the player has made no progress for StuckWindow seconds. We
-- measure CLOSING ON the target, not raw movement: circling an obstacle moves
-- a lot while getting nowhere.
function TravelController.isStuck(ctx)
    local state = tracker(ctx)
    if not state.target then return false end
    return os.clock() - state.lastProgressAt > ctx.cfg.Travel.StuckWindow
end

function TravelController.elapsed(ctx)
    local state = tracker(ctx)
    if not state.target then return 0 end
    return os.clock() - state.startedAt
end

---------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------

function TravelController.distanceTo(ctx, target)
    local goal = toVector(target)
    local here = ctx:pos()
    if not goal or not here then return math.huge end
    return (goal - here).Magnitude
end

function TravelController.arrived(ctx, target, tolerance)
    return TravelController.distanceTo(ctx, target)
        <= (tolerance or ctx.cfg.Travel.ArriveDistance)
end

-- One step of a journey. Call it on every turn of the state machine, not once
-- and for all: the tween restarts itself when the destination moves.
-- opts.validate : refuses an invalid destination (under the map, in water).
-- opts.lift     : height added to the destination.
function TravelController.step(ctx, target, opts)
    opts = opts or {}
    local goal = toVector(target)
    if not goal then return false, "nil destination" end

    if opts.lift then goal = goal + Vector3.new(0, opts.lift, 0) end

    if opts.validate then
        local ok, reason = SafeCombatAnchor.validatePosition(ctx, goal, opts.region)
        if not ok then
            -- We do not abandon the journey: we aim at the same point, higher.
            -- A ground destination that is invalid is often still reachable in
            -- flight.
            local lifted = goal + Vector3.new(0, ctx.cfg.Anchor.Height, 0)
            if SafeCombatAnchor.validatePosition(ctx, lifted, opts.region) then
                goal = lifted
            else
                return false, reason
            end
        end
    end

    local state = tracker(ctx)
    local here = ctx:pos()
    if not here then return false, "no player" end

    local distance = (goal - here).Magnitude

    -- New destination: start from a fresh clock.
    if not state.target or (state.target - goal).Magnitude > ctx.cfg.Travel.ArriveDistance then
        state.target = goal
        state.startedAt = os.clock()
        state.lastProgressAt = os.clock()
        state.bestDistance = distance
    elseif distance < state.bestDistance - ctx.cfg.Travel.StuckDistance then
        -- Real progress: the stall clock restarts.
        state.bestDistance = distance
        state.lastProgressAt = os.clock()
    end

    state.lastPos = here

    ctx.move.tweenTo(CFrame.new(goal))
    return true
end

function TravelController.stop(ctx)
    ctx.move.stop()
    TravelController.reset(ctx)
end

-- Passage to a distant area (Fishman, Sky, Ship). The game exposes a dedicated
-- entrance: trying to tween there would cross tens of thousands of studs.
function TravelController.requestEntrance(ctx, entrance)
    if not entrance then return false end
    local ok = pcall(function() ctx.remote.invoke("requestEntrance", entrance) end)
    if ok then Log.Travel("entering through requestEntrance") end
    return ok
end

return TravelController
