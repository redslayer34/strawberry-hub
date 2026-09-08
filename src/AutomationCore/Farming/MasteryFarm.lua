--=============================================================================
-- MASTERY FARM — raise the mastery of one specific weapon
--=============================================================================
--  Covers the four requested modes (SwordMastery, FruitMastery,
--  FightingStyleMastery, GunMastery): they are the same farm with a different
--  weapon equipped. One module per weapon would have duplicated nothing but a
--  string.
--
--  The target still comes from an active quest or an explicit selection --
--  never "the nearest mob". Without either, the mode does nothing, which is
--  the correct behaviour: we do not guess what the user wants to farm.
--=============================================================================

local Log = require("AutomationCore.Log")
local TargetedFarm = require("AutomationCore.Farming.TargetedFarm")

local MasteryFarm = {}
MasteryFarm.__index = MasteryFarm

-- Mode -> weapon selection understood by the runtime.
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

    -- The weapon is re-equipped on every engagement: the game puts the default
    -- one back in hand after a death or a zone change.
    self.engine.onEngage = function() self:equip() end

    return self
end

-- kind : "Sword" | "Fruit" | "FightingStyle" | "Gun"
function MasteryFarm:setWeapon(kind)
    local selection = MasteryFarm.WEAPONS[kind]
    if not selection then
        Log.Mastery("unknown weapon:", tostring(kind))
        return false
    end
    self.weapon = selection
    Log.Mastery("weapon =", selection)
    return true
end

-- A target imposed by the user. Takes priority over the quest: it is an
-- explicit choice and must not be overridden by whatever the game offers.
function MasteryFarm:setTarget(name)
    self.explicitTarget = name
    self.ctx.region = nil
    if name then Log.Mastery("target set:", name) end
end

function MasteryFarm:equip()
    if not self.weapon then return end
    pcall(function() self.ctx.attack.equip(self.weapon) end)
end

-- Explicit selection first, active quest second. Nothing otherwise.
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
    return self.engine:describe() .. " weapon=" .. tostring(self.weapon)
end

return MasteryFarm
