--=============================================================================
-- PERCEPTION — un seul tour de detection, cadence et mis en cache
--=============================================================================
--  Rien de tout ceci ne tourne sur RenderStepped. Un tour complet coute cher
--  (parcours du dossier Enemies, lecture de l'UI, regroupement) : il tourne
--  toutes les quelques secondes au repos, et se resserre pendant le combat ou
--  la situation change vite.
--
--  Ordre impose, chaque etape s'appuyant sur la precedente :
--
--      DetectSea -> DetectIsland -> DetectQuest
--                -> RefreshQuestGiver -> RefreshTargets -> RefreshSpawnRegion
--
--  Le changement de mer ou d'ile vide la memoire de carte AVANT que les
--  etapes suivantes ne lisent quoi que ce soit : aucune etape ne peut donc
--  travailler sur des donnees heritees du contexte precedent.
--=============================================================================

local EnemyScanner = require("AutomationCore.Perception.EnemyScanner")
local IslandDetector = require("AutomationCore.Perception.IslandDetector")
local Log = require("AutomationCore.Log")
local QuestDetector = require("AutomationCore.Perception.QuestDetector")
local QuestGiverResolver = require("AutomationCore.Perception.QuestGiverResolver")
local SeaDetector = require("AutomationCore.Perception.SeaDetector")
local SpawnClusterResolver = require("AutomationCore.Perception.SpawnClusterResolver")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")

local Perception = {}
Perception.__index = Perception

function Perception.new(ctx)
    local self = setmetatable({
        ctx = ctx,
        scanner = EnemyScanner.new(ctx),
        lastFull = 0,
        lastQuest = 0,
        combatMode = false,
        questGiverHints = nil,
        questGiverFallback = nil,
    }, Perception)

    ctx.quest = QuestDetector.blank()
    return self
end

-- Le mode combat resserre la cadence : pendant un bring, la situation change
-- en quelques dixiemes de seconde.
function Perception:setCombat(value)
    self.combatMode = value and true or false
end

function Perception:interval()
    local cfg = self.ctx.cfg.Perception
    return self.combatMode and cfg.CombatInterval or cfg.IdleInterval
end

-- Indices d'identification du donneur, poses par le mode de farm actif.
-- La perception ne sait pas quelle quete on veut prendre ; elle sait la
-- chercher une fois qu'on le lui dit.
function Perception:setQuestGiverHints(hints, fallback)
    self.questGiverHints = hints
    self.questGiverFallback = fallback
end

---------------------------------------------------------------------------
-- Etapes
---------------------------------------------------------------------------

function Perception:detectSea()
    return SeaDetector.update(self.ctx)
end

function Perception:detectIsland()
    return IslandDetector.update(self.ctx)
end

-- La quete se relit plus souvent que le reste : c'est la source de verite,
-- et sa progression change a chaque kill.
function Perception:detectQuest(force)
    local ctx = self.ctx
    local now = os.clock()
    if not force and now - self.lastQuest < ctx.cfg.Perception.QuestPollInterval then
        return ctx.quest
    end
    self.lastQuest = now

    local previous = ctx.quest
    local current = QuestDetector.read(ctx)

    -- Le nom d'instance reel ne s'invente pas : il vient du Workspace. On le
    -- reporte sur l'etat de quete pour que tout le reste travaille sur une
    -- entite qui existe.
    if current.TargetName then
        current.ResolvedName = self.scanner:resolveName(current.TargetName)
    end

    -- Changement d'objectif : tout ce qui en decoulait devient faux.
    if not QuestDetector.sameObjective(previous, current) then
        ctx.region = nil
        ctx.targets = {}
        ctx.map:invalidate("SpawnClusters", nil, "changement d'objectif")
    end

    QuestDetector.logChange(previous, current)
    ctx.quest = current
    return current
end

function Perception:refreshQuestGiver()
    local hints = self.questGiverHints
    if not hints then return nil end

    local near = self.ctx.region and self.ctx.region.center or nil
    local position, level = QuestGiverResolver.resolve(
        self.ctx, hints, near, self.questGiverFallback)

    self.ctx.questGiver = position
    self.ctx.questGiverTrust = level
    return position, level
end

-- Reconstruit la liste des cibles VALIDES. C'est le seul endroit ou
-- ctx.targets est ecrit : tout le reste le lit.
function Perception:refreshTargets()
    local ctx = self.ctx
    local quest = ctx.quest

    if not quest or not quest.TargetName then
        ctx.targets = {}
        return ctx.targets
    end

    local candidates = self.scanner:candidatesFor(quest.TargetName)
    ctx.targets = TargetValidator.filter(ctx, candidates, quest)
    return ctx.targets
end

function Perception:refreshSpawnRegion()
    local ctx = self.ctx
    -- La region se calcule sur les cibles valides, mais SANS filtre de region
    -- (sinon la region ne pourrait jamais se deplacer : elle se validerait
    -- elle-meme). On repart donc des candidats bruts revalides hors zone.
    local quest = ctx.quest
    if not quest or not quest.TargetName then
        ctx.region = nil
        return nil
    end

    local previousRegion = ctx.region
    ctx.region = nil
    local unfiltered = TargetValidator.filter(
        ctx, self.scanner:candidatesFor(quest.TargetName), quest)
    ctx.region = previousRegion

    local reference = ctx.questGiver or ctx:pos()
    return SpawnClusterResolver.update(ctx, unfiltered, reference)
end

---------------------------------------------------------------------------
-- Boucle
---------------------------------------------------------------------------

-- Un tour complet. `force` ignore la cadence (utilise par la recuperation,
-- qui a besoin d'une image fraiche immediatement).
function Perception:update(force)
    local ctx = self.ctx
    local now = os.clock()

    -- La quete se relit a chaque appel, meme hors cadence : c'est bon marche
    -- (quelques labels) et c'est la donnee qui doit etre la plus fraiche.
    self:detectQuest(force)

    if not force and now - self.lastFull < self:interval() then
        return false
    end
    self.lastFull = now
    ctx.stats.ticks = ctx.stats.ticks + 1

    local sea = self:detectSea()
    local island = self:detectIsland()

    -- Vidange de la memoire AVANT les etapes qui la lisent.
    ctx.map:syncContext(ctx.world.jobId(), sea, island)

    self.scanner:scan()

    -- Re-resolution du nom reel apres le scan : au premier tour sur un
    -- serveur, detectQuest a tourne sur un index encore vide.
    if ctx.quest and ctx.quest.TargetName and not ctx.quest.ResolvedName then
        ctx.quest.ResolvedName = self.scanner:resolveName(ctx.quest.TargetName)
    end

    -- Region avant donneur, contrairement a l'ordre nominal : les deux se
    -- referencent mutuellement (la region se note par rapport au donneur, le
    -- donneur se departage par proximite a la region), il faut donc trancher.
    -- Calculer la region d'abord fait que refreshTargets filtre sur une
    -- region FRAICHE — et la liste de cibles est la sortie critique. Le
    -- donneur, lui, ne perd qu'un leger bonus de classement a travailler sur
    -- la region du tour precedent.
    self:refreshSpawnRegion()
    self:refreshQuestGiver()
    self:refreshTargets()

    return true
end

-- Rescan immediat et complet. Premier barreau de l'echelle de recuperation :
-- souvent, un "plus aucune cible" n'est qu'un index perime.
function Perception:rescan(reason)
    Log.Perception("rescan --", reason or "demande")
    self.lastFull = 0
    self.lastQuest = 0
    return self:update(true)
end

function Perception:targetCount() return #self.ctx.targets end

function Perception:describe()
    local ctx = self.ctx
    return string.format(
        "mer=%s ile=%s cibles=%d region=%s",
        tostring(ctx.sea), tostring(ctx.island), #ctx.targets,
        ctx.region and string.format("%d mobs", ctx.region.count) or "aucune")
end

return Perception
