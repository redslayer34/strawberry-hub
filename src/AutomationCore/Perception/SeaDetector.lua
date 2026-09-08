--=============================================================================
-- SEA DETECTOR — which sea are we in
--=============================================================================
--  The sea is read from the PlaceId: that is not a coordinate but the identity
--  of the server itself, so a map update cannot move it. It only becomes wrong
--  if the game publishes a new PlaceId, which the fallback below covers.
--
--  Fallback: the make-up of the locations folder. Each sea exposes islands the
--  others do not; their presence identifies the sea without any position.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")

local SeaDetector = {}

-- Known PlaceIds. A missing entry is no longer fatal: we fall through to the
-- island signature.
local PLACES = {
    [2753915549] = 1, [100117331123089] = 1,
    [4442272183] = 2, [79091703265657] = 2,
    [7449423635] = 3, [85211729168715] = 3,
}

-- Islands exclusive to one sea. A single match settles it.
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

-- Returns the sea number, and true when the value came from a fallback.
function SeaDetector.detect(ctx)
    local sea = fromPlaceId(ctx)
    if sea then return sea, false end

    sea = fromLocations(ctx)
    if sea then
        Log.Sea("unknown PlaceId (" .. tostring(ctx.world.placeId())
            .. ") -- sea inferred from present islands:", sea)
        return sea, true
    end

    return nil, true
end

function SeaDetector.update(ctx)
    local sea = SeaDetector.detect(ctx)
    if sea and sea ~= ctx.sea then
        Log.Sea(ctx.sea and ("changed " .. ctx.sea .. " -> " .. sea) or ("sea " .. sea))
        ctx.sea = sea
    end
    return ctx.sea
end

return SeaDetector
