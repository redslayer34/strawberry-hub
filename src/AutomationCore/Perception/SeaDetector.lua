--=============================================================================
-- SEA DETECTOR — dans quelle mer sommes-nous
--=============================================================================
--  La mer se lit sur le PlaceId : ce n'est pas une coordonnee mais l'identite
--  du serveur lui-meme, donc une donnee stable qu'une mise a jour de carte ne
--  deplace pas. Elle ne devient fausse que si le jeu publie un nouveau
--  PlaceId, cas traite par la detection de repli.
--
--  Repli : la composition du dossier des lieux. Chaque mer expose des iles
--  qui n'existent pas dans les autres ; leur presence identifie la mer sans
--  aucune position.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")

local SeaDetector = {}

-- PlaceId connus. Une entree manquante n'est plus bloquante : on tombe sur
-- la signature d'iles.
local PLACES = {
    [2753915549] = 1, [100117331123089] = 1,
    [4442272183] = 2, [79091703265657] = 2,
    [7449423635] = 3, [85211729168715] = 3,
}

-- Iles exclusives a une mer. Il suffit d'une seule pour trancher.
local SIGNATURE = {
    [1] = { "jungle", "pirate village", "desert", "frozen village", "marine", "skylands" },
    [2] = { "kingdom of rose", "green zone", "graveyard island", "snow mountain", "cafe" },
    [3] = { "port town", "hydra island", "great tree", "floating turtle", "castle on the sea" },
}

local function fromPlaceId(ctx)
    return PLACES[ctx.world.placeId()]
end

local function fromLocations(ctx)
    local folder = ctx.world.locations()
    if not folder then return nil end

    local present = {}
    for _, node in ipairs(folder:GetChildren()) do
        local key = Names.normalize(node.Name)
        if key then present[key] = true end
    end

    for sea, markers in pairs(SIGNATURE) do
        for _, marker in ipairs(markers) do
            if present[Names.normalize(marker)] then return sea end
        end
    end
    return nil
end

-- Renvoie le numero de mer, et true si la valeur vient d'un repli.
function SeaDetector.detect(ctx)
    local sea = fromPlaceId(ctx)
    if sea then return sea, false end

    sea = fromLocations(ctx)
    if sea then
        Log.Sea("PlaceId inconnu (" .. tostring(ctx.world.placeId())
            .. ") -- mer deduite des iles presentes :", sea)
        return sea, true
    end

    return nil, true
end

function SeaDetector.update(ctx)
    local sea = SeaDetector.detect(ctx)
    if sea and sea ~= ctx.sea then
        Log.Sea(ctx.sea and ("changement " .. ctx.sea .. " -> " .. sea) or ("mer " .. sea))
        ctx.sea = sea
    end
    return ctx.sea
end

return SeaDetector
