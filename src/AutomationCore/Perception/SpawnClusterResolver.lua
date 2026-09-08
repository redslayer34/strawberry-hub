--=============================================================================
-- SPAWN CLUSTER RESOLVER — ou se trouve reellement le paquet de mobs
--=============================================================================
--  Les mobs d'une meme quete ne sont pas repartis uniformement : ils forment
--  des paquets, parfois tres eloignes les uns des autres, et une mise a jour
--  redistribue ces paquets. Choisir "le plus proche" un par un fait traverser
--  la zone en permanence ; choisir un centre fixe rate le paquet des que le
--  jeu le deplace.
--
--  On regroupe donc les cibles reellement presentes, on note chaque groupe,
--  et on retient le meilleur comme SpawnRegion. La region est une donnee
--  vivante : elle expire, se recalcule, et ne survit ni a un changement d'ile
--  ni a un changement d'objectif.
--
--  La region sert ensuite de filtre geographique dans TargetValidator : c'est
--  ce qui empeche d'aspirer les mobs de la zone voisine.
--=============================================================================

local Log = require("AutomationCore.Log")

local SpawnClusterResolver = {}

-- Regroupement glouton par proximite. Choisi pour son cout : O(n * groupes),
-- avec n borne par le budget de scan et un nombre de groupes tres faible en
-- pratique. Un k-means serait plus juste et bien plus cher, pour un gain nul
-- sur des paquets aussi nets.
local function cluster(entries, radius)
    local groups = {}
    local radiusSq = radius * radius

    for _, entry in ipairs(entries) do
        local placed = false
        for _, group in ipairs(groups) do
            if (entry.position - group.center).Magnitude <= radius then
                group.members[#group.members + 1] = entry
                -- Moyenne incrementale : le centre suit le paquet au fur et a
                -- mesure, sans second passage.
                local n = #group.members
                group.center = group.center + (entry.position - group.center) / n
                placed = true
                break
            end
        end
        if not placed then
            groups[#groups + 1] = {
                center = entry.position,
                members = { entry },
            }
        end
    end

    -- Rayon reel de chaque groupe : distance du membre le plus excentre.
    for _, group in ipairs(groups) do
        local spread = 0
        for _, member in ipairs(group.members) do
            local d = (member.position - group.center).Magnitude
            if d > spread then spread = d end
        end
        group.radius = math.max(spread, radius * 0.5)
        group.count = #group.members
    end

    local _ = radiusSq
    return groups
end

-- Note d'un groupe. Densite en positif, eloignement en negatif : un gros
-- paquet un peu plus loin bat un mob isole a cote.
local function score(ctx, group, reference)
    local cfg = ctx.cfg.Cluster
    local distance = reference and (group.center - reference).Magnitude or 0
    -- Echelle de 1000 studs : au-dela, l'eloignement domine la densite.
    local penalty = 1 + cfg.DistanceWeight * (distance / 1000)
    return (cfg.DensityWeight * group.count) / penalty, distance
end

-- entries : cibles DEJA validees (voir TargetValidator). Ce module ne filtre
-- pas, il regroupe : lui donner des mobs non valides produirait une region
-- centree sur les mauvais ennemis.
-- reference : point d'interet (donneur de quete si connu, sinon joueur).
function SpawnClusterResolver.resolve(ctx, entries, reference)
    if #entries == 0 then return nil end

    local cfg = ctx.cfg.Cluster
    local groups = cluster(entries, cfg.Radius)

    local best, bestScore, bestDistance
    for _, group in ipairs(groups) do
        if group.count >= cfg.MinSize then
            local value, distance = score(ctx, group, reference)
            if not bestScore or value > bestScore then
                best, bestScore, bestDistance = group, value, distance
            end
        end
    end

    if not best then return nil end

    return {
        center = best.center,
        radius = best.radius,
        count = best.count,
        distance = bestDistance,
        groups = #groups,
        stamp = os.clock(),
    }
end

-- Une region reste valable tant qu'elle est fraiche, qu'elle contient encore
-- des cibles, et que l'objectif n'a pas change.
function SpawnClusterResolver.isStale(ctx, region)
    if not region then return true end
    if os.clock() - region.stamp > ctx.cfg.Cluster.RefreshInterval then return true end
    return false
end

function SpawnClusterResolver.update(ctx, entries, reference)
    local current = ctx.region

    if not SpawnClusterResolver.isStale(ctx, current) then
        return current
    end

    local region = SpawnClusterResolver.resolve(ctx, entries, reference)
    if not region then
        if current then
            Log.Target("region de spawn perdue (aucune cible valide)")
        end
        ctx.region = nil
        return nil
    end

    local moved = current and (region.center - current.center).Magnitude or math.huge
    ctx.region = region

    -- On ne journalise qu'un vrai deplacement de paquet, pas la derive de
    -- quelques studs due aux mobs qui bougent.
    if moved > ctx.cfg.Cluster.Radius then
        Log.Target(string.format(
            "region de spawn : %d cibles sur %d groupe(s), a %.0f studs",
            region.count, region.groups, region.distance or 0))
    end

    return region
end

-- Vrai si une position appartient a la region retenue. RegionSlack laisse une
-- marge : un mob qui poursuit le joueur sort du rayon strict sans pour autant
-- appartenir a une autre zone.
function SpawnClusterResolver.contains(ctx, region, position)
    if not region or not position then return true end
    local limit = region.radius * ctx.cfg.Targets.RegionSlack
    return (position - region.center).Magnitude <= limit
end

return SpawnClusterResolver
