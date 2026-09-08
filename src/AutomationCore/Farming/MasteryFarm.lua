--=============================================================================
-- MASTERY FARM — monter la maitrise d'une arme precise
--=============================================================================
--  Couvre les quatre modes demandes (SwordMastery, FruitMastery,
--  FightingStyleMastery, GunMastery) : ce sont le meme farm, avec une arme
--  differente equipee. Un module par arme n'aurait duplique que la chaine de
--  caracteres.
--
--  La cible reste choisie par une quete active ou une selection explicite —
--  jamais "le mob le plus proche". Sans l'un ou l'autre, le mode ne fait
--  rien, ce qui est le comportement correct : on ne devine pas ce que
--  l'utilisateur veut farmer.
--=============================================================================

local Log = require("AutomationCore.Log")
local TargetedFarm = require("AutomationCore.Farming.TargetedFarm")

local MasteryFarm = {}
MasteryFarm.__index = MasteryFarm

-- Correspondance mode -> selection d'arme comprise par le runtime.
MasteryFarm.WEAPONS = {
    Sword = "Sword",
    Fruit = "Blox Fruit",
    FightingStyle = "Melee",
    Gun = "Gun",
}

function MasteryFarm.new(ctx, perception, recovery)
    local self = setmetatable({
        ctx = ctx,
        perception = perception,
        weapon = nil,
        explicitTarget = nil,
    }, MasteryFarm)

    self.engine = TargetedFarm.new(ctx, perception, recovery, "Mastery", function()
        return self:pickTarget()
    end)

    -- L'arme est reequipee a chaque engagement : le jeu la remet en main par
    -- defaut apres une mort ou un changement de zone.
    self.engine.onEngage = function() self:equip() end

    return self
end

-- kind : "Sword" | "Fruit" | "FightingStyle" | "Gun"
function MasteryFarm:setWeapon(kind)
    local selection = MasteryFarm.WEAPONS[kind]
    if not selection then
        Log.Mastery("arme inconnue :", tostring(kind))
        return false
    end
    self.weapon = selection
    Log.Mastery("arme =", selection)
    return true
end

-- Cible imposee par l'utilisateur. Prioritaire sur la quete : c'est un choix
-- explicite, il ne doit pas etre ecrase par ce que le jeu propose.
function MasteryFarm:setTarget(name)
    self.explicitTarget = name
    self.ctx.region = nil
    if name then Log.Mastery("cible imposee :", name) end
end

function MasteryFarm:equip()
    if not self.weapon then return end
    pcall(function() self.ctx.attack.equip(self.weapon) end)
end

-- Selection explicite d'abord, quete active ensuite. Rien sinon.
function MasteryFarm:pickTarget()
    if self.explicitTarget then return self.explicitTarget end

    local quest = self.ctx.quest
    if quest and quest.Active and quest.TargetName then
        return quest.ResolvedName or quest.TargetRaw
    end

    return nil
end

function MasteryFarm:update() return self.engine:update() end
function MasteryFarm:stop()
    self.explicitTarget = nil
    return self.engine:stop()
end
function MasteryFarm:describe()
    return self.engine:describe() .. " arme=" .. tostring(self.weapon)
end

return MasteryFarm
