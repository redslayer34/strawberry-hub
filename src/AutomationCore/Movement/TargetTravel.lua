--=============================================================================
-- TARGET TRAVEL — reaching the area where the targets actually are
--=============================================================================
--  We do not travel to a mob: we travel to the REGION computed by
--  SpawnClusterResolver. Chasing an individual target means crossing the zone
--  constantly, and the target dies on the way.
--
--  This is also the answer to the PullLimit: when mobs are too far to be
--  brought, the player moves, rather than a mob being teleported across the
--  map.
--=============================================================================

local IslandDetector = require("AutomationCore.Perception.IslandDetector")
local Log = require("AutomationCore.Log")
local TravelController = require("AutomationCore.Movement.TravelController")
local Trust = require("AutomationCore.Trust")

local TargetTravel = {}

-- Farming destination, by decreasing trust:
--   2. a target actually present
--   4. the centre of the detected spawn pack
--   5. the island remembered for this quest on this server
--   6. the frozen coordinate from the historical table
function TargetTravel.destination(ctx, plan)
    return Trust.resolve("farming area", {
        {
            level = Trust.LEVEL.LIVE_ENTITY,
            why = "valid target present",
            get = function()
                local first = ctx.targets and ctx.targets[1]
                return first and first.position or nil
            end,
        },
        {
            level = Trust.LEVEL.SPAWN_CLUSTER,
            why = "centre of the detected pack",
            get = function()
                return ctx.region and ctx.region.center or nil
            end,
        },
        {
            level = Trust.LEVEL.SERVER_MEMORY,
            why = "island published by the game",
            get = function()
                if not plan or not plan.island then return nil end
                return IslandDetector.positionOf(ctx, plan.island)
            end,
        },
        {
            level = Trust.LEVEL.STATIC_FALLBACK,
            why = "coordinate from the historical table",
            get = function()
                return plan and plan.mobFallback or nil
            end,
        },
    })
end

-- Returns "arrived" | "travelling" | "unreachable" | "unknown".
function TargetTravel.step(ctx, plan)
    local destination, level = TargetTravel.destination(ctx, plan)
    if not destination then
        return "unknown"
    end

    if plan and plan.entrance
        and TravelController.distanceTo(ctx, destination) > ctx.cfg.Travel.FarEntranceDistance then
        TravelController.requestEntrance(ctx, plan.entrance)
        return "travelling"
    end

    -- Arrived as soon as we are inside the collection radius: there is no need
    -- to land exactly on the centre, the bring covers the difference.
    if TravelController.distanceTo(ctx, destination) <= ctx.cfg.Bring.Radius then
        return "arrived"
    end

    local ok, reason = TravelController.step(ctx, destination, {
        lift = ctx.cfg.Anchor.Height,
        validate = true,
    })
    if not ok then
        Log.Travel("farming area unreachable:", reason,
            "(source:", Trust.label(level) .. ")")
        return "unreachable"
    end

    if TravelController.isStuck(ctx) then
        Log.Travel("stuck on the way to the farming area")
        TravelController.reset(ctx)
        return "unreachable"
    end

    return "travelling"
end

return TargetTravel
