--=============================================================================
-- AUTOMATION CORE — assemblage
--=============================================================================
--  Un seul contexte, une seule perception, une seule recuperation, partages
--  par tous les modes de farm. C'est ce qui repond a "permettre a chaque
--  systeme de farm d'utiliser le meme AutomationCore" : passer de QuestFarm
--  a MaterialFarm ne reconstruit ni l'index des ennemis, ni la memoire de
--  carte, ni l'echelle de recuperation.
--
--  Un seul mode est actif a la fois. Le changement de mode arrete proprement
--  le precedent — sans quoi deux machines a etats se disputeraient la
--  position du joueur.
--=============================================================================

local BossFarm = require("AutomationCore.Farming.BossFarm")
local CDKController = require("AutomationCore.SpecialObjectives.CDKController")
local Context = require("AutomationCore.Context")
local Log = require("AutomationCore.Log")
local MasteryFarm = require("AutomationCore.Farming.MasteryFarm")
local MaterialFarm = require("AutomationCore.Farming.MaterialFarm")
local Perception = require("AutomationCore.Perception")
local QuestFarm = require("AutomationCore.Farming.QuestFarm")
local RecoveryController = require("AutomationCore.Recovery.RecoveryController")
local ServerHop = require("AutomationCore.Farming.ServerHop")
local SpecialFarm = require("AutomationCore.Farming.SpecialFarm")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")

local AutomationCore = {}
AutomationCore.__index = AutomationCore

AutomationCore.MODES = { "Quest", "Boss", "Mastery", "Material", "Special" }

function AutomationCore.new(internal)
    local ctx = Context.new(internal)
    local perception = Perception.new(ctx)
    local recovery = RecoveryController.new(ctx, perception)

    local self = setmetatable({
        ctx = ctx,
        perception = perception,
        recovery = recovery,
        serverHop = ServerHop.new(ctx),
        mode = "Quest",
        lastReport = 0,
    }, AutomationCore)

    self.modes = {
        Quest = QuestFarm.new(ctx, perception, recovery),
        Boss = BossFarm.new(ctx, perception, recovery),
        Mastery = MasteryFarm.new(ctx, perception, recovery),
        Material = MaterialFarm.new(ctx, perception, recovery),
        Special = SpecialFarm.new(ctx),
    }

    -- CDK delegue son boss final a BossFarm : on lui donne la meme instance
    -- plutot qu'une seconde, qui se battrait pour le meme personnage.
    ctx.bossFarm = self.modes.Boss

    Log.write("Core", "AutomationCore pret --", #AutomationCore.MODES, "modes")
    return self
end

---------------------------------------------------------------------------
-- Modes
---------------------------------------------------------------------------

function AutomationCore:active()
    return self.modes[self.mode]
end

function AutomationCore:setMode(mode)
    if not self.modes[mode] then
        Log.write("Core", "mode inconnu :", tostring(mode))
        return false
    end
    if mode == self.mode then return true end

    -- Arret explicite : l'ancien mode doit relacher l'ancre, le pilote de
    -- bring et sa cible avant que le suivant ne touche au personnage.
    local previous = self:active()
    if previous and previous.stop then previous:stop() end

    self.mode = mode
    Log.write("Core", "mode =", mode)
    return true
end

---------------------------------------------------------------------------
-- Raccourcis de configuration
---------------------------------------------------------------------------

function AutomationCore:farmBoss(name)
    if not self.modes.Boss:setBoss(name) then return false end
    return self:setMode("Boss")
end

function AutomationCore:farmMaterial(name)
    self.modes.Material:setMaterial(name)
    return self:setMode("Material")
end

-- kind : "Sword" | "Fruit" | "FightingStyle" | "Gun"
function AutomationCore:farmMastery(kind, target)
    if not self.modes.Mastery:setWeapon(kind) then return false end
    if target then self.modes.Mastery:setTarget(target) end
    return self:setMode("Mastery")
end

function AutomationCore:farmQuest()
    return self:setMode("Quest")
end

-- CDK est un objectif special : il se branche et se debranche sans que
-- QuestFarm en sache quoi que ce soit.
function AutomationCore:startCDK()
    local controller = CDKController.new(self.ctx, self.perception, self.recovery)

    local ok, reason = controller:requirements()
    if not ok then
        Log.CDK("refuse :", reason)
        return false, reason
    end

    self.modes.Special:setObjective("CDK", controller)
    return self:setMode("Special")
end

function AutomationCore:stopSpecial()
    self.modes.Special:stop()
    return self:setMode("Quest")
end

---------------------------------------------------------------------------
-- Cycle
---------------------------------------------------------------------------

-- Point d'entree unique, appele par la boucle de farm du runtime.
function AutomationCore:update()
    local mode = self:active()
    if not mode then return end

    local ok, err = pcall(function() mode:update() end)
    if not ok then
        -- Une erreur ne doit jamais tuer la boucle : on la trace et on
        -- laisse la recuperation reprendre au tour suivant.
        Log.write("Core", "erreur dans le mode", self.mode, ":", err)
        self.recovery:begin("unknown")
    end

    -- Bilan periodique : etat courant et motifs de refus de cibles. C'est ce
    -- qui permet de diagnostiquer un "0 cible valide" sans rallumer de logs.
    local now = os.clock()
    if now - self.lastReport > 20 then
        self.lastReport = now
        TargetValidator.logRejections("Target")
    end
end

function AutomationCore:stop()
    for _, mode in pairs(self.modes) do
        if mode.stop then pcall(function() mode:stop() end) end
    end
    self.ctx.legacy.State.bringDriver = nil
    self.ctx.legacy.State.bringAnchor = nil
end

function AutomationCore:describe()
    local mode = self:active()
    local detail = mode and mode.describe and mode:describe() or "-"
    return string.format("%s | %s | %s", self.mode, detail, self.serverHop:describe())
end

function AutomationCore:stats()
    return self.ctx.stats
end

return AutomationCore
