--=============================================================================
-- QUEST TRAVEL — reaching the quest giver
--=============================================================================
--  The destination is never a constant: it comes from QuestGiverResolver, so
--  from an NPC actually present. This module only drives to the position it is
--  given, and reports the cases where that position turns out to be wrong.
--
--  A giver you reach with nothing happening is a giver that was misidentified:
--  invalidate, re-resolve. That is the difference between going to the right
--  place and going to yesterday's place.
--=============================================================================

local Log = require("AutomationCore.Log")
local QuestGiverResolver = require("AutomationCore.Perception.QuestGiverResolver")
local TravelController = require("AutomationCore.Movement.TravelController")

local QuestTravel = {}

-- Returns "travelling" | "arrived" | "unreachable" | "unknown".
function QuestTravel.step(ctx, plan)
    local giver = ctx.questGiver

    if not giver then
        Log.Travel("Searching Quest Giver")
        return "unknown"
    end

    -- Distant area: the tween cannot cover the distance, the game provides an
    -- entrance.
    if plan and plan.entrance then
        local distance = TravelController.distanceTo(ctx, giver)
        if distance > ctx.cfg.Travel.FarEntranceDistance then
            TravelController.requestEntrance(ctx, plan.entrance)
            return "travelling"
        end
    end

    if TravelController.arrived(ctx, giver, ctx.cfg.Travel.QuestGiverDistance) then
        return "arrived"
    end

    local ok, reason = TravelController.step(ctx, giver, { lift = 4 })
    if not ok then
        Log.Travel("giver destination refused:", reason)
        return "unreachable"
    end

    if TravelController.isStuck(ctx) then
        -- Stuck on the way: the position most likely came from a stale cache
        -- or a static fallback.
        QuestGiverResolver.markFailed(ctx, plan and plan.hints or {}, "route blocked")
        TravelController.reset(ctx)
        return "unreachable"
    end

    return "travelling"
end

-- Accepting the quest. The remote is the only reliable route: standing next to
-- the NPC is not enough, and clicking is not reproducible.
function QuestTravel.accept(ctx, plan)
    if not plan or not plan.questId then return false, "unknown quest" end

    local ok = pcall(function()
        ctx.remote.invoke("StartQuest", plan.questId, plan.questLevel or 1)
    end)
    if not ok then return false, "remote refused" end

    Log.Quest("accepting quest:", plan.questId, "level", plan.questLevel or 1)
    return true
end

function QuestTravel.abandon(ctx)
    pcall(function() ctx.remote.invoke("AbandonQuest") end)
    Log.Quest("quest abandoned")
end

return QuestTravel
