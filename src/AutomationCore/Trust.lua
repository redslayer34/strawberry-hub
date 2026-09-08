--=============================================================================
-- TRUST — hierarchie de confiance des sources d'information
--=============================================================================
--  Le point central de toute l'architecture. Une meme question ("ou est le
--  donneur de quete ?", "quel mob dois-je frapper ?") admet plusieurs
--  reponses, de fiabilites tres inegales. On les classe une fois pour toutes :
--
--    1. QUEST_STATE     etat reel de la quete lu dans le jeu
--    2. LIVE_ENTITY     entite reellement presente dans le Workspace
--    3. NPC_IDENTITY    identite / dialogue / objectif d'un PNJ
--    4. SPAWN_CLUSTER   groupe de spawn effectivement detecte
--    5. SERVER_MEMORY   donnee apprise sur CE serveur, pendant CETTE session
--    6. STATIC_FALLBACK coordonnee connue d'avance (table figee)
--
--  Consequence directe : une ancienne coordonnee n'est jamais une verite.
--  C'est le dernier recours, et il est trace comme tel. Quand une mise a jour
--  du jeu deplace une ile, les niveaux 1 a 4 continuent de fonctionner ; seul
--  le niveau 6 devient faux, et il n'est consulte que si tout le reste a
--  echoue.
--=============================================================================

local Log = require("AutomationCore.Log")

local Trust = {}

Trust.LEVEL = {
    QUEST_STATE = 1,
    LIVE_ENTITY = 2,
    NPC_IDENTITY = 3,
    SPAWN_CLUSTER = 4,
    SERVER_MEMORY = 5,
    STATIC_FALLBACK = 6,
}

Trust.LABEL = {
    [1] = "quest-state",
    [2] = "live-entity",
    [3] = "npc-identity",
    [4] = "spawn-cluster",
    [5] = "server-memory",
    [6] = "static-fallback",
}

-- Au-dela de ce niveau la donnee est un pis-aller : on l'utilise, mais on le
-- dit, et l'appelant est cense declencher un rescan en parallele.
Trust.DEGRADED_FROM = Trust.LEVEL.SERVER_MEMORY

-- sources : liste de { level = Trust.LEVEL.*, get = function() -> value, why = "..." }
-- Renvoie value, level, why. Les sources sont essayees par confiance
-- decroissante, quel que soit leur ordre dans la table.
function Trust.resolve(question, sources)
    local ordered = table.clone and table.clone(sources) or (function()
        local copy = {}
        for i, v in ipairs(sources) do copy[i] = v end
        return copy
    end)()

    table.sort(ordered, function(a, b) return a.level < b.level end)

    for _, source in ipairs(ordered) do
        local ok, value = pcall(source.get)
        if ok and value ~= nil then
            if source.level >= Trust.DEGRADED_FROM then
                Log.Perception(question, "resolu en mode degrade via",
                    Trust.LABEL[source.level], "--", source.why or "")
            end
            return value, source.level, source.why
        end
    end

    return nil, nil, nil
end

function Trust.isDegraded(level)
    return level ~= nil and level >= Trust.DEGRADED_FROM
end

function Trust.label(level)
    return Trust.LABEL[level or 0] or "unknown"
end

return Trust
