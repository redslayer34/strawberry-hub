--=============================================================================
-- ROUTE PLANNER — quelle quete prendre, et pourquoi celle-la
--=============================================================================
--  L'ancienne selection tenait en une ligne : la premiere entree de la table
--  dont [Min, Max] contient le niveau. Elle ignorait tout le reste — que le
--  mob n'existe pas sur ce serveur, qu'il n'en reste que deux, qu'ils sont a
--  quatre mille studs, ou qu'une autre quete rapporte davantage.
--
--  Ici la table historique n'est plus qu'un CATALOGUE de quetes possibles :
--  elle fournit des identifiants de quete et des noms de cible, jamais une
--  verite de position. Chaque candidate est notee sur ce qui est reellement
--  observable maintenant :
--
--      niveau  x  disponibilite de la cible  x  densite  x  distance  x  gain
--
--  Une quete dont la cible n'existe pas sur ce serveur tombe a zero, quelle
--  que soit sa place dans la table.
--=============================================================================

local IslandDetector = require("AutomationCore.Perception.IslandDetector")
local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")

local RoutePlanner = {}

-- Distance max entre une coordonnee historique et une ile publiee pour
-- qu'on accepte de les associer. Au-dela, la table est trop perimee pour
-- servir meme d'indice.
local ISLAND_SNAP = 2500

---------------------------------------------------------------------------
-- Catalogue
---------------------------------------------------------------------------

-- Convertit une entree de la table historique en candidate exploitable.
-- Les CFrame ne sont conserves que comme replis de dernier recours, jamais
-- comme destination directe.
local function toCandidate(ctx, row)
    local canonical = Names.normalize(row.Name)
    if not canonical then return nil end

    return {
        questId = row.Quest,
        questLevel = row.QLevel or 1,
        targetRaw = row.Name,
        targetName = canonical,
        minLevel = row.Min or 1,
        maxLevel = row.Max or math.huge,
        sea = row.Sea,
        entrance = row.Entrance,
        -- Confiance 6. Utilises uniquement si toute detection a echoue.
        giverFallback = row.QCF and row.QCF.Position or nil,
        mobFallback = row.MonCF and row.MonCF.Position or nil,
    }
end

-- Ile la plus proche de la coordonnee historique. Astuce utile : la vieille
-- coordonnee ne sert pas de destination, elle sert a NOMMER la zone, et le
-- nom est ensuite resolu sur la position publiee par le jeu. Une ile
-- deplacee reste donc trouvable tant qu'elle n'a pas change de nom.
function RoutePlanner.islandFor(ctx, fallbackPosition)
    if not fallbackPosition then return nil end

    local best, bestDist
    for _, island in ipairs(IslandDetector.all(ctx)) do
        local d = (island.position - fallbackPosition).Magnitude
        if not bestDist or d < bestDist then best, bestDist = island.name, d end
    end

    if not best or bestDist > ISLAND_SNAP then return nil end
    return best
end

---------------------------------------------------------------------------
-- Notation
---------------------------------------------------------------------------

-- Chaque facteur est un multiplicateur : un facteur nul elimine la candidate
-- au lieu de se faire compenser par les autres.
local function scoreCandidate(ctx, scanner, candidate, level)
    -- Mer : une quete d'une autre mer n'est pas atteignable d'ici.
    if candidate.sea and ctx.sea and candidate.sea ~= ctx.sea then return 0 end

    -- Niveau. Dans la fourchette : plein tarif. En dessous : elimine (les
    -- mobs tuent). Au-dessus : penalise, le gain d'experience s'effondre.
    local levelFactor
    if level < candidate.minLevel then
        return 0
    elseif level <= candidate.maxLevel then
        levelFactor = 1
    else
        local excess = level - candidate.maxLevel
        levelFactor = math.max(0.05, 1 - excess / 400)
    end

    -- Disponibilite : la cible existe-t-elle vraiment, ici, maintenant ?
    -- C'est le facteur qui manquait completement a l'ancienne selection.
    local live = scanner:candidatesFor(candidate.targetName)
    local count = #live
    local availability = count > 0 and 1 or 0.08

    -- Densite : un paquet de dix mobs vaut mieux qu'un mob isole. Plafonnee
    -- pour qu'une zone tres peuplee ne domine pas le reste du calcul.
    local density = 1 + math.min(count, 12) / 12

    -- Distance : mesuree sur les mobs reels quand il y en a, sinon sur l'ile.
    local distance
    if count > 0 then
        local here = ctx:pos()
        if here then
            local nearest = math.huge
            for _, entry in ipairs(live) do
                local d = (entry.position - here).Magnitude
                if d < nearest then nearest = d end
            end
            distance = nearest
        end
    end
    local distanceFactor = 1
    if distance then
        distanceFactor = 1 / (1 + distance / 2500)
    end

    -- Gain : approxime par le palier de la quete. Les paliers hauts donnent
    -- nettement plus d'experience par kill.
    local reward = 1 + (candidate.minLevel / 2000)

    return levelFactor * availability * density * distanceFactor * reward
end

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------

-- Renvoie le meilleur plan, ou nil. `preferBoss` reserve a BossFarm.
function RoutePlanner.plan(ctx, scanner, opts)
    opts = opts or {}
    local catalogue = ctx.legacyConfig.Quests or {}
    local level = ctx.player.level()

    local best, bestScore
    for _, row in ipairs(catalogue) do
        local candidate = toCandidate(ctx, row)
        if candidate then
            local value = scoreCandidate(ctx, scanner, candidate, level)
            if value > 0 and (not bestScore or value > bestScore) then
                best, bestScore = candidate, value
            end
        end
    end

    if not best then
        Log.Quest("aucune quete exploitable (niveau", level, ", mer", tostring(ctx.sea) .. ")")
        return nil
    end

    best.score = bestScore
    best.island = RoutePlanner.islandFor(ctx, best.mobFallback or best.giverFallback)

    -- Indices d'identification du donneur. L'identifiant de quete est le plus
    -- discriminant : il porte le nom de la zone ("DesertQuest", "SnowQuest").
    best.hints = {
        best.questId or "",
        best.targetRaw or "",
        best.island or "",
    }

    Log.Quest(string.format("plan : %s niveau %d -> %s (score %.2f%s)",
        tostring(best.questId), best.questLevel, best.targetRaw, bestScore,
        best.island and (", ile " .. best.island) or ""))

    return best
end

-- Le plan reste-t-il pertinent ? Un changement de niveau peut ouvrir une
-- meilleure quete, et une cible qui disparait du serveur en invalide une.
function RoutePlanner.isStale(ctx, plan, scanner)
    if not plan then return true end
    local level = ctx.player.level()
    if level < plan.minLevel or level > plan.maxLevel then return true end
    if plan.sea and ctx.sea and plan.sea ~= ctx.sea then return true end
    return false
end

return RoutePlanner
