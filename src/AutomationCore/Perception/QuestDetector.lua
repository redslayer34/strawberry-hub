--=============================================================================
-- QUEST DETECTOR — lit l'objectif REEL de la quete en cours
--=============================================================================
--  Regle absolue de l'architecture : la quete active est la source de verite
--  pour choisir les mobs. Ce module est donc le sommet de la hierarchie de
--  confiance ; tout le reste en decoule.
--
--  L'ancienne boucle se contentait de lire le titre pour verifier qu'il
--  contenait le nom attendu, le nom venant d'une table figee indexee par
--  niveau. Ici c'est l'inverse : on extrait l'objectif du jeu, et la table
--  figee ne sert plus qu'a proposer une quete a prendre quand aucune n'est
--  active.
--
--      "Defeat 8 Desert Bandits"  ->  TargetName = "desert bandit"
--                                     RequiredCount = 8
--
--  Le nom extrait est une forme CANONIQUE, pas un nom d'instance. La
--  correspondance avec l'entite reelle est faite par EnemyScanner, qui seul
--  sait ce qui existe vraiment dans le Workspace.
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")

local QuestDetector = {}

-- Etat de quete neutre. Toujours la meme forme : aucun appelant n'a besoin
-- de tester l'existence des champs.
function QuestDetector.blank()
    return {
        Active = false,
        QuestName = nil,       -- titre affiche ("Bandit Hunter")
        TargetRaw = nil,       -- objectif tel qu'ecrit ("Desert Bandits")
        TargetName = nil,      -- forme canonique ("desert bandit")
        ResolvedName = nil,    -- nom d'instance reel, rempli par EnemyScanner
        RequiredCount = 0,
        CurrentCount = 0,
        Remaining = 0,
        QuestGiver = nil,
        Island = nil,
        IsBossQuest = false,
        ReadAt = 0,
    }
end

---------------------------------------------------------------------------
-- Lecture du texte
---------------------------------------------------------------------------

-- Le chemin connu d'abord (rapide, une seule indirection), le balayage
-- ensuite (robuste a une refonte de l'UI). Une mise a jour qui deplace le
-- label ralentit la lecture, elle ne la casse pas.
local function knownPathText(frame)
    local ok, text = pcall(function()
        return frame.Container.QuestTitle.Title.Text
    end)
    if ok and type(text) == "string" and text ~= "" then return text end
    return nil
end

local function collectTexts(frame, limit)
    local texts = {}
    local seen = 0
    for _, node in ipairs(frame:GetDescendants()) do
        seen = seen + 1
        if seen > limit then break end
        if node:IsA("TextLabel") or node:IsA("TextButton") then
            local text = node.Text
            if type(text) == "string" and text ~= "" then
                texts[#texts + 1] = text
            end
        end
    end
    return texts
end

---------------------------------------------------------------------------
-- Extraction
---------------------------------------------------------------------------

local function matchObjective(text, patterns)
    for _, pattern in ipairs(patterns) do
        local count, target = text:match(pattern)
        if count and target then
            return tonumber(count), target
        end
    end
    return nil
end

local function matchProgress(text, patterns)
    for _, pattern in ipairs(patterns) do
        local current, required = text:match(pattern)
        if current and required then
            return tonumber(current), tonumber(required)
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

function QuestDetector.isActive(ctx)
    local frame = ctx.world.questFrame()
    return frame ~= nil and frame.Visible == true
end

-- Lit l'etat de quete courant. Ne devine rien : si l'objectif n'est pas
-- lisible, RequiredCount reste 0 et TargetName reste nil, ce qui bloque le
-- bring en amont plutot que de laisser passer un filtre vide.
function QuestDetector.read(ctx)
    local state = QuestDetector.blank()
    local frame = ctx.world.questFrame()

    if not frame or frame.Visible ~= true then
        return state
    end

    state.Active = true
    state.ReadAt = os.clock()

    local cfg = ctx.cfg.Quest
    local title = knownPathText(frame)
    local texts = collectTexts(frame, ctx.cfg.Perception.MaxScanPerTick)
    if title then table.insert(texts, 1, title) end

    state.QuestName = title or texts[1]

    -- Objectif : premier texte qui exprime "N cibles a battre".
    for _, text in ipairs(texts) do
        local count, target = matchObjective(text, cfg.Patterns)
        if count then
            -- L'objectif porte parfois sa propre progression :
            -- "Defeat 8 Desert Bandits [3/8]". On la retire du nom.
            target = target:gsub("%[.-%]", ""):gsub("%(.-%)", "")
            target = target:gsub("%d+%s*/%s*%d+", "")
            state.RequiredCount = count
            state.TargetRaw = (target:gsub("^%s*(.-)%s*$", "%1"))
            state.TargetName = Names.normalize(target)
            break
        end
    end

    -- Progression : on privilegie la paire dont le total correspond a
    -- l'objectif deja lu, sinon la premiere rencontree.
    local fallbackCurrent, fallbackRequired
    for _, text in ipairs(texts) do
        local current, required = matchProgress(text, cfg.ProgressPatterns)
        if current then
            if state.RequiredCount > 0 and required == state.RequiredCount then
                state.CurrentCount = current
                break
            end
            fallbackCurrent = fallbackCurrent or current
            fallbackRequired = fallbackRequired or required
        end
    end

    if state.CurrentCount == 0 and fallbackCurrent then
        state.CurrentCount = fallbackCurrent
        if state.RequiredCount == 0 and fallbackRequired then
            state.RequiredCount = fallbackRequired
        end
    end

    state.Remaining = math.max(0, state.RequiredCount - state.CurrentCount)

    -- Indice de quete de boss. Confirme seulement quand l'entite reelle
    -- porte une vie de boss : ici on ne fait que le signaler, la decision
    -- d'autoriser un boss appartient a TargetValidator.
    state.IsBossQuest = state.RequiredCount == 1

    return state
end

-- Vrai si deux etats designent le meme objectif. Sert a detecter un
-- changement de quete sans reconstruire toute la chaine de decision.
function QuestDetector.sameObjective(a, b)
    if not a or not b then return false end
    if not a.Active or not b.Active then return a.Active == b.Active end
    return a.TargetName == b.TargetName and a.RequiredCount == b.RequiredCount
end

function QuestDetector.describe(state)
    if not state or not state.Active then return "aucune quete active" end
    if not state.TargetName then
        return "quete active, objectif illisible (" .. tostring(state.QuestName) .. ")"
    end
    return string.format("%s -- %s %d/%d",
        tostring(state.QuestName), state.TargetRaw or state.TargetName,
        state.CurrentCount, state.RequiredCount)
end

-- Trace uniquement les changements : la lecture tourne plusieurs fois par
-- seconde, le journal doit rester lisible.
function QuestDetector.logChange(previous, current)
    if QuestDetector.sameObjective(previous, current) then
        if previous and current and previous.CurrentCount ~= current.CurrentCount then
            Log.Quest("Progress =", current.CurrentCount .. "/" .. current.RequiredCount)
            if current.Remaining == 0 then Log.Quest("Complete") end
        end
        return
    end

    if not current.Active then
        Log.Quest("quete perdue")
        return
    end
    if current.TargetName then
        Log.Quest("Target =", current.TargetRaw or current.TargetName)
        Log.Quest("Progress =", current.CurrentCount .. "/" .. current.RequiredCount)
    else
        Log.Quest("objectif illisible --", tostring(current.QuestName))
    end
end

return QuestDetector
