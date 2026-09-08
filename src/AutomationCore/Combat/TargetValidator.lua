--=============================================================================
-- TARGET VALIDATOR — la seule autorite qui decide qu'un mob est frappable
--=============================================================================
--  Aucun autre module n'a le droit de conclure qu'une entite est une cible.
--  BringController, AttackController et les modes de farm recoivent des
--  listes DEJA validees ; ils ne refont pas le tri, ils ne l'assouplissent
--  pas.
--
--  Dix controles, dans cet ordre (du moins cher au plus cher) :
--
--    1. l'entite existe et est encore dans le Workspace
--    2. elle possede un Humanoid exploitable
--    3. elle possede une partie racine manipulable
--    4. elle est vivante
--    5. ce n'est pas un joueur
--    6. ce n'est pas un PNJ de quete
--    7. son nom correspond EXACTEMENT a la cible normalisee
--    8. ce n'est pas un boss, sauf si la quete le designe explicitement
--    9. elle appartient a la region de spawn retenue
--   10. sa reference est encore fraiche (ni detruite, ni deplacee hors jeu)
--
--  Le point 7 est le coeur du systeme : egalite de formes canoniques, jamais
--  `string.find`, jamais "le nom contient un mot proche". C'est ce qui
--  empeche "Bandit" d'aspirer "Desert Bandit", et inversement.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")
local SpawnClusterResolver = require("AutomationCore.Perception.SpawnClusterResolver")

local Players = game:GetService("Players")

local TargetValidator = {}

-- Comptage des refus par motif. Sans cela, "0 cible valide" n'apprend rien :
-- avec, on sait si les mobs sont absents, hors zone, ou tous morts.
local rejections = {}

local function reject(reason)
    rejections[reason] = (rejections[reason] or 0) + 1
    return false, reason
end

function TargetValidator.stats()
    local out = {}
    for reason, count in pairs(rejections) do out[#out + 1] = { reason = reason, count = count } end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

function TargetValidator.resetStats() table.clear(rejections) end

---------------------------------------------------------------------------
-- Boss
---------------------------------------------------------------------------

-- Un boss se reconnait a sa reserve de vie, pas a son nom : aucune liste a
-- maintenir, et une mise a jour qui ajoute un boss est couverte d'office.
-- L'attribut explicite, quand le jeu en pose un, prime sur l'heuristique.
function TargetValidator.isBoss(ctx, entry)
    local model = entry.model
    local flagged = model:GetAttribute("IsBoss")
    if flagged ~= nil then return flagged == true end

    if model:FindFirstChild("BossHealthBar") then return true end

    local maxHealth = entry.maxHealth or (entry.humanoid and entry.humanoid.MaxHealth) or 0
    return maxHealth >= ctx.cfg.Targets.BossHealthThreshold
end

---------------------------------------------------------------------------
-- PNJ de quete
---------------------------------------------------------------------------

local function isQuestNPC(ctx, model)
    local npcs = ctx.world.npcs()
    if npcs and model:IsDescendantOf(npcs) then return true end

    -- Un mob ne porte jamais d'invite d'interaction ; un donneur de quete si.
    for _, node in ipairs(model:GetChildren()) do
        if node:IsA("ProximityPrompt") or node:IsA("ClickDetector") then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------

-- entry : entree d'EnemyScanner, ou modele brut (normalise ici).
-- quest : QuestState. quest.AllowBoss n'est pose que par BossFarm, qui
--         demande explicitement un boss.
-- Renvoie true, ou false + motif.
function TargetValidator.isValidQuestTarget(ctx, entry, quest)
    -- Tolere un modele brut : le validateur doit pouvoir etre appele depuis
    -- n'importe ou, y compris sur une reference gardee par un appelant.
    if typeof(entry) == "Instance" then
        entry = {
            model = entry,
            humanoid = entry:FindFirstChildOfClass("Humanoid"),
            root = entry:FindFirstChild("HumanoidRootPart") or entry.PrimaryPart,
            name = entry.Name,
        }
    end

    -- 1. existence
    local model = entry and entry.model
    if not model or not model.Parent then return reject("disparu") end

    -- 2. Humanoid
    local humanoid = entry.humanoid or model:FindFirstChildOfClass("Humanoid")
    if not humanoid or not humanoid.Parent then return reject("sans humanoid") end

    -- 3. partie racine
    local root = entry.root
    if not root or not root.Parent or not root:IsA("BasePart") then
        return reject("sans racine")
    end

    -- 4. vivant
    if humanoid.Health <= 0 then return reject("mort") end

    -- 5. pas un joueur
    if Players:GetPlayerFromCharacter(model) then return reject("joueur") end

    -- 6. pas un PNJ de quete
    if isQuestNPC(ctx, model) then return reject("pnj de quete") end

    -- 7. correspondance stricte avec l'objectif de la quete
    if not quest or not quest.TargetName then
        -- Pas d'objectif lisible = aucune cible autorisee. On prefere ne rien
        -- faire plutot que de frapper au hasard : c'est ce trou qui faisait
        -- aspirer toute la zone entre deux cibles.
        return reject("objectif inconnu")
    end
    local canonical = entry.canonical or Names.normalize(entry.name or model.Name)
    if canonical ~= quest.TargetName then return reject("nom different") end

    -- 8. boss
    if TargetValidator.isBoss(ctx, entry) then
        -- Le nom correspond deja (point 7). Il faut EN PLUS que la quete
        -- active designe bien un boss, sinon c'est un homonyme costaud qu'on
        -- n'a aucune raison d'engager.
        if not (quest.AllowBoss or quest.IsBossQuest) then
            return reject("boss non demande")
        end
    end

    -- 9. region de spawn
    local position = root.Position
    if ctx.region and not SpawnClusterResolver.contains(ctx, ctx.region, position) then
        return reject("hors region")
    end

    -- 10. reference encore exploitable
    if position.Y ~= position.Y then return reject("position invalide") end
    if humanoid.Health ~= humanoid.Health then return reject("vie invalide") end

    return true
end

-- Filtre une liste de candidats. C'est la SEULE fabrique de listes de cibles
-- de tout le systeme : le flux impose est
--     QuestDetector -> TargetSelector -> TargetValidator -> BringController
function TargetValidator.filter(ctx, candidates, quest)
    local valid = {}
    for _, entry in ipairs(candidates) do
        if TargetValidator.isValidQuestTarget(ctx, entry, quest) then
            valid[#valid + 1] = entry
        end
    end
    return valid
end

-- Revalidation d'une cible gardee d'un tour a l'autre. Appelee avant CHAQUE
-- operation sur un mob : jamais d'action sur une reference qui a vieilli.
function TargetValidator.stillValid(ctx, entry, quest)
    return TargetValidator.isValidQuestTarget(ctx, entry, quest)
end

function TargetValidator.logRejections(tag)
    local stats = TargetValidator.stats()
    if #stats == 0 then return end
    local parts = {}
    for i = 1, math.min(4, #stats) do
        parts[#parts + 1] = stats[i].reason .. "=" .. stats[i].count
    end
    Log.write(tag or "Target", "refus :", table.concat(parts, ", "))
    TargetValidator.resetStats()
end

return TargetValidator
