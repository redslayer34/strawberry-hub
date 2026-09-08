--=============================================================================
-- QUEST GIVER RESOLVER — identifier le donneur, pas retenir sa position
--=============================================================================
--  L'ancienne approche stockait QuestGiver = CFrame.new(...). Une mise a jour
--  qui deplace le PNJ de trois metres suffisait alors a casser le farm, sans
--  aucun moyen de s'en apercevoir.
--
--  Ici on identifie le PNJ par ce qu'il EST : son nom, le texte de son
--  invite d'interaction, les etiquettes qu'il porte. Sa position n'est qu'une
--  consequence, mise en cache pour ne pas rebalayer le dossier NPCs a chaque
--  frame, et invalidee des que quoi que ce soit bouge.
--
--  Le cache tombe sur : changement de serveur, de mer, d'ile, PNJ introuvable,
--  interaction ratee, deplacement detecte, expiration.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")
local Trust = require("AutomationCore.Trust")

local QuestGiverResolver = {}

-- En dessous, on considere qu'aucun PNJ ne correspond : mieux vaut declarer
-- l'echec et laisser la recuperation agir que d'aller parler au mauvais.
local MIN_SCORE = 0.34
local MOVE_TOLERANCE = 15      -- studs avant de considerer que le PNJ a bouge

---------------------------------------------------------------------------
-- Identite d'un PNJ
---------------------------------------------------------------------------

local function rootOf(model)
    local root = model:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then return root end
    if model.PrimaryPart then return model.PrimaryPart end
    return model:FindFirstChildWhichIsA("BasePart")
end

-- Tout ce que le PNJ dit de lui-meme : son nom, ses invites, ses etiquettes.
-- C'est le niveau NPC_IDENTITY de la hierarchie de confiance.
local function identityTokens(model)
    local tokens = { model.Name }
    local interactive = false

    for _, node in ipairs(model:GetDescendants()) do
        if node:IsA("ProximityPrompt") then
            interactive = true
            if node.ObjectText ~= "" then tokens[#tokens + 1] = node.ObjectText end
            if node.ActionText ~= "" then tokens[#tokens + 1] = node.ActionText end
        elseif node:IsA("ClickDetector") then
            interactive = true
        elseif node:IsA("TextLabel") and node.Text ~= "" then
            -- Panneau flottant au-dessus du PNJ : porte souvent le nom de la
            -- quete plutot que celui du personnage.
            tokens[#tokens + 1] = node.Text
        end
    end

    return tokens, interactive
end

-- hints : { questId = "DesertQuest", target = "desert bandit", island = "Desert" }
-- Chaque indice est compare a chaque jeton ; on garde le meilleur accord.
local function scoreAgainst(tokens, hints)
    local best = 0
    for _, token in ipairs(tokens) do
        for _, hint in ipairs(hints) do
            if hint and hint ~= "" then
                local value = Names.similarity(token, hint)
                if value > best then best = value end
            end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Recherche
---------------------------------------------------------------------------

-- Renvoie { model, root, position, name, score } ou nil.
function QuestGiverResolver.find(ctx, hints, near)
    local folder = ctx.world.npcs()
    if not folder then return nil end

    local budget = ctx.cfg.Perception.MaxScanPerTick
    local seen = 0
    local best, bestScore

    for _, model in ipairs(folder:GetChildren()) do
        seen = seen + 1
        if seen > budget then break end

        local root = rootOf(model)
        if root then
            local tokens, interactive = identityTokens(model)
            local value = scoreAgainst(tokens, hints)

            -- Un PNJ interactif est un meilleur candidat qu'un figurant qui
            -- porterait le meme mot dans son nom.
            if interactive then value = value * 1.15 end

            -- Bonus de proximite avec la zone de la quete : un donneur se
            -- trouve sur la meme ile que ses mobs. Jamais determinant seul.
            if near then
                local d = (root.Position - near).Magnitude
                if d < 600 then value = value * 1.2
                elseif d > 4000 then value = value * 0.5 end
            end

            if value > (bestScore or 0) then
                best, bestScore = {
                    model = model,
                    root = root,
                    position = root.Position,
                    name = model.Name,
                    score = value,
                    interactive = interactive,
                }, value
            end
        end
    end

    if not best or bestScore < MIN_SCORE then return nil end
    return best
end

---------------------------------------------------------------------------
-- Cache
---------------------------------------------------------------------------

local function cacheKey(hints)
    return table.concat(hints, "|")
end

-- Resolution complete, hierarchie de confiance appliquee :
--   3. identite d'un PNJ present
--   5. donneur retenu plus tot sur CE serveur
--   6. coordonnee figee de la table historique (dernier recours)
function QuestGiverResolver.resolve(ctx, hints, near, staticFallback)
    local key = cacheKey(hints)

    local position, level = Trust.resolve("donneur de quete", {
        {
            level = Trust.LEVEL.NPC_IDENTITY,
            why = "PNJ identifie dans le Workspace",
            get = function()
                local found = QuestGiverResolver.find(ctx, hints, near)
                if not found then return nil end

                local model, origin = found.model, found.position
                -- Le cache ne survit pas au PNJ : s'il disparait ou se
                -- deplace, l'entree se declare invalide d'elle-meme.
                ctx.map:put("QuestGivers", key, origin, {
                    name = found.name, score = found.score,
                }, function()
                    if not model.Parent then return false end
                    local root = rootOf(model)
                    if not root then return false end
                    return (root.Position - origin).Magnitude <= MOVE_TOLERANCE
                end)

                Log.QuestGiver(string.format("%s (score %.2f)", found.name, found.score))
                return origin
            end,
        },
        {
            level = Trust.LEVEL.SERVER_MEMORY,
            why = "donneur memorise sur ce serveur",
            get = function() return ctx.map:get("QuestGivers", key) end,
        },
        {
            level = Trust.LEVEL.STATIC_FALLBACK,
            why = "coordonnee de la table historique",
            get = function() return staticFallback end,
        },
    })

    return position, level
end

-- Interaction ratee : on jette immediatement ce qu'on croyait savoir. Sans
-- cela le script retourne indefiniment au meme endroit vide.
function QuestGiverResolver.markFailed(ctx, hints, reason)
    ctx.map:invalidate("QuestGivers", cacheKey(hints), reason or "interaction echouee")
    Log.QuestGiver("cache invalide --", reason or "interaction echouee")
end

return QuestGiverResolver
