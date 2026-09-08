--=============================================================================
-- ISLAND DETECTOR — sur quelle ile sommes-nous, et ou sont les autres
--=============================================================================
--  Le jeu publie lui-meme la position de chaque ile dans
--  workspace._WorldOrigin.Locations. C'est la donnee qui remplace les tables
--  de CFrame : quand une mise a jour deplace une ile, ce dossier bouge avec
--  elle et la detection suit, sans aucune modification du script.
--
--  On ne memorise donc PAS une position d'ile. On lit le dossier a la
--  demande, et le cache n'existe que pour eviter de le relire soixante fois
--  par seconde.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")

local IslandDetector = {}

local function positionOf(node)
    if node:IsA("BasePart") then return node.Position end
    if node:IsA("Model") then
        local ok, cf = pcall(function() return node:GetPivot() end)
        if ok and cf then return cf.Position end
        local primary = node.PrimaryPart or node:FindFirstChildWhichIsA("BasePart")
        if primary then return primary.Position end
    end
    local attachment = node:FindFirstChildWhichIsA("BasePart")
    return attachment and attachment.Position or nil
end

-- Liste { name, position } de toutes les iles publiees. Rendue telle quelle,
-- sans filtrage : c'est la seule verite disponible sur la geographie.
function IslandDetector.all(ctx)
    local folder = ctx.world.locations()
    if not folder then return {} end

    local out = {}
    for _, node in ipairs(folder:GetChildren()) do
        local pos = positionOf(node)
        if pos then
            out[#out + 1] = { name = node.Name, position = pos, instance = node }
        end
    end
    return out
end

-- Position publiee d'une ile, par nom. Comparaison sur forme canonique :
-- "Frozen Village" et "frozen village" designent la meme ile.
function IslandDetector.positionOf(ctx, islandName)
    local wanted = Names.normalize(islandName)
    if not wanted then return nil end

    local cached = ctx.map:get("Islands", wanted)
    if cached then return cached end

    for _, island in ipairs(IslandDetector.all(ctx)) do
        if Names.normalize(island.name) == wanted then
            -- Validateur : l'entree reste bonne tant que l'instance vit et
            -- n'a pas bouge. Une ile deplacee par une mise a jour invalide
            -- le cache d'elle-meme au tour suivant.
            local instance, origin = island.instance, island.position
            ctx.map:put("Islands", wanted, origin, { name = island.name }, function()
                if not instance or not instance.Parent then return false end
                local now = positionOf(instance)
                return now ~= nil and (now - origin).Magnitude < 25
            end)
            return origin
        end
    end
    return nil
end

-- Ile la plus proche du joueur. C'est la definition operationnelle de "ou je
-- suis" : aucune zone codee en dur, aucune bounding box a maintenir.
function IslandDetector.current(ctx)
    local here = ctx:pos()
    if not here then return nil end

    local best, bestDist
    for _, island in ipairs(IslandDetector.all(ctx)) do
        local d = (island.position - here).Magnitude
        if not bestDist or d < bestDist then
            best, bestDist = island.name, d
        end
    end
    return best, bestDist
end

function IslandDetector.update(ctx)
    local island = IslandDetector.current(ctx)
    if island ~= ctx.island then
        Log.Island(ctx.island and (tostring(ctx.island) .. " -> " .. tostring(island))
            or tostring(island))
        ctx.island = island
    end
    return ctx.island
end

return IslandDetector
