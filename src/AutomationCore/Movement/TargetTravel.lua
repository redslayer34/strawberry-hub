--=============================================================================
-- TARGET TRAVEL — rejoindre la zone ou les cibles se trouvent reellement
--=============================================================================
--  On ne voyage pas vers un mob : on voyage vers la REGION calculee par
--  SpawnClusterResolver. Suivre une cible individuelle fait traverser la zone
--  en permanence, et la cible meurt en route.
--
--  Sert aussi de reponse au PullLimit : quand les mobs sont trop loin pour
--  etre ramenes, c'est le joueur qui se rapproche, pas le mob qu'on teleporte
--  a travers la carte.
--=============================================================================

local IslandDetector = require("AutomationCore.Perception.IslandDetector")
local Log = require("AutomationCore.Log")
local TravelController = require("AutomationCore.Movement.TravelController")
local Trust = require("AutomationCore.Trust")

local TargetTravel = {}

-- Destination de farm, par confiance decroissante :
--   2. une cible reellement presente
--   4. le centre du paquet de spawn detecte
--   5. l'ile memorisee pour cette quete sur ce serveur
--   6. la coordonnee figee de la table historique
function TargetTravel.destination(ctx, plan)
    return Trust.resolve("zone de farm", {
        {
            level = Trust.LEVEL.LIVE_ENTITY,
            why = "cible valide presente",
            get = function()
                local first = ctx.targets and ctx.targets[1]
                return first and first.position or nil
            end,
        },
        {
            level = Trust.LEVEL.SPAWN_CLUSTER,
            why = "centre du paquet detecte",
            get = function()
                return ctx.region and ctx.region.center or nil
            end,
        },
        {
            level = Trust.LEVEL.SERVER_MEMORY,
            why = "ile publiee par le jeu",
            get = function()
                if not plan or not plan.island then return nil end
                return IslandDetector.positionOf(ctx, plan.island)
            end,
        },
        {
            level = Trust.LEVEL.STATIC_FALLBACK,
            why = "coordonnee de la table historique",
            get = function()
                return plan and plan.mobFallback or nil
            end,
        },
    })
end

-- Renvoie "arrived" | "travelling" | "unreachable" | "unknown".
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

    -- Arrive des qu'on est dans le rayon de collecte : inutile de se poser
    -- exactement au centre, le bring couvre la difference.
    if TravelController.distanceTo(ctx, destination) <= ctx.cfg.Bring.Radius then
        return "arrived"
    end

    local ok, reason = TravelController.step(ctx, destination, {
        lift = ctx.cfg.Anchor.Height,
        validate = true,
    })
    if not ok then
        Log.Travel("zone de farm inatteignable :", reason,
            "(source :", Trust.label(level) .. ")")
        return "unreachable"
    end

    if TravelController.isStuck(ctx) then
        Log.Travel("blocage en route vers la zone de farm")
        TravelController.reset(ctx)
        return "unreachable"
    end

    return "travelling"
end

return TargetTravel
