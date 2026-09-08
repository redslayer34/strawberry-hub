--=============================================================================
-- QUEST TRAVEL — rejoindre le donneur de quete
--=============================================================================
--  La destination n'est jamais une constante : elle vient de
--  QuestGiverResolver, donc d'un PNJ reellement present. Ce module ne fait
--  que conduire jusqu'a la position qu'on lui donne, et signaler les cas ou
--  cette position se revele fausse.
--
--  Un donneur qu'on atteint sans que rien ne se passe est un donneur mal
--  identifie : on invalide, on relance la resolution. C'est la difference
--  entre "aller au bon endroit" et "aller a l'endroit d'hier".
--=============================================================================

local Log = require("AutomationCore.Log")
local QuestGiverResolver = require("AutomationCore.Perception.QuestGiverResolver")
local TravelController = require("AutomationCore.Movement.TravelController")

local QuestTravel = {}

-- Renvoie "travelling" | "arrived" | "unreachable" | "unknown".
function QuestTravel.step(ctx, plan)
    local giver = ctx.questGiver

    if not giver then
        Log.Travel("Searching Quest Giver")
        return "unknown"
    end

    -- Zone lointaine : le tween ne peut pas franchir la distance, le jeu
    -- fournit une entree.
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
        Log.Travel("destination du donneur refusee :", reason)
        return "unreachable"
    end

    if TravelController.isStuck(ctx) then
        -- Bloque en chemin : la position vient probablement d'un cache
        -- perime ou d'un repli statique.
        QuestGiverResolver.markFailed(ctx, plan and plan.hints or {}, "trajet bloque")
        TravelController.reset(ctx)
        return "unreachable"
    end

    return "travelling"
end

-- Prise de quete. Le remote est le seul moyen fiable : etre a cote du PNJ ne
-- suffit pas, et cliquer n'est pas reproductible.
function QuestTravel.accept(ctx, plan)
    if not plan or not plan.questId then return false, "quete inconnue" end

    local ok = pcall(function()
        ctx.remote.invoke("StartQuest", plan.questId, plan.questLevel or 1)
    end)
    if not ok then return false, "remote refuse" end

    Log.Quest("prise de quete :", plan.questId, "niveau", plan.questLevel or 1)
    return true
end

function QuestTravel.abandon(ctx)
    pcall(function() ctx.remote.invoke("AbandonQuest") end)
    Log.Quest("quete abandonnee")
end

return QuestTravel
