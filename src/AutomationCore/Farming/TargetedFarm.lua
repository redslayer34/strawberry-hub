--=============================================================================
-- TARGETED FARM — moteur commun aux farms sans quete
--=============================================================================
--  MaterialFarm et MasteryFarm posent la meme question au systeme : "frappe
--  ce mob-la, en boucle". Seule la maniere de CHOISIR le mob differe. Ce
--  module porte donc tout le cycle (scan, voyage, bring, combat, recuperation)
--  et laisse a l'appelant la seule decision qui lui appartient : l'objectif.
--
--  L'objectif a la meme forme qu'un QuestState, ce qui garantit que
--  TargetValidator lui applique exactement les memes controles — y compris
--  l'exclusion des boss, qu'aucun de ces deux modes ne leve.
--=============================================================================

local AttackController = require("AutomationCore.Combat.AttackController")
local BringController = require("AutomationCore.Combat.BringController")
local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")
local SafeCombatAnchor = require("AutomationCore.Movement.SafeCombatAnchor")
local StateMachine = require("AutomationCore.StateMachine")
local TargetTravel = require("AutomationCore.Movement.TargetTravel")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")
local TravelController = require("AutomationCore.Movement.TravelController")

local TargetedFarm = {}
TargetedFarm.__index = TargetedFarm

-- label : etiquette de journal ("Material", "Mastery").
-- selector : function() -> nom de mob souhaite, ou nil. Rappele quand
--            l'objectif courant n'est plus tenable.
function TargetedFarm.new(ctx, perception, recovery, label, selector)
    local self = setmetatable({
        ctx = ctx,
        perception = perception,
        recovery = recovery,
        label = label,
        selector = selector,
        objective = nil,
        bring = BringController.new(ctx),
        attack = AttackController.new(ctx),
        onEngage = nil,     -- crochet appele avant chaque combat
        machine = nil,
    }, TargetedFarm)

    self.machine = StateMachine.new(label .. "Farm", ctx)
    self:defineStates()
    return self
end

-- Objectif synthetique. Volontairement sans AllowBoss : ces modes n'ont
-- aucune raison d'engager un boss, et le validateur les exclura.
function TargetedFarm:setTarget(name)
    local canonical = Names.normalize(name)
    if not canonical then
        self.objective = nil
        return false
    end

    if self.objective and self.objective.TargetName == canonical then return true end

    self.objective = {
        Active = true,
        QuestName = self.label,
        TargetRaw = name,
        TargetName = canonical,
        RequiredCount = math.huge,
        CurrentCount = 0,
        Remaining = math.huge,
        IsBossQuest = false,
    }
    -- La region du cycle precedent portait sur un autre mob.
    self.ctx.region = nil
    Log.write(self.label, "cible =", name)
    return true
end

function TargetedFarm:candidates()
    if not self.objective then return {} end
    local raw = self.perception.scanner:candidatesFor(self.objective.TargetName)
    return TargetValidator.filter(self.ctx, raw, self.objective)
end

function TargetedFarm:bringEnabled()
    return self.ctx.legacyConfig.Farming.BringMob == true
end

function TargetedFarm:defineStates()
    local ctx = self.ctx
    local perception = self.perception

    self.machine:defineAll({

        IDLE = {
            update = function()
                if not ctx.flags.farming() then return nil end
                return "SELECT"
            end,
        },

        -- Le choix du mob est rejoue regulierement : sur un nouveau serveur,
        -- le meilleur candidat n'est pas le meme.
        SELECT = {
            timeout = 15,
            onTimeout = function()
                self.recovery:begin("target_missing")
                return "RECOVERY"
            end,
            update = function()
                perception:update(true)
                local wanted = self.selector()
                if not wanted then return nil end
                if not self:setTarget(wanted) then return nil end
                return "SCAN"
            end,
        },

        SCAN = {
            timeout = 12,
            onTimeout = "TRAVEL",
            update = function()
                perception:update(true)
                local found = self:candidates()
                if #found > 0 then
                    ctx.targets = found
                    Log.write(self.label, "Found", #found, "valid targets")
                    return "ENGAGE"
                end
                return "TRAVEL"
            end,
        },

        TRAVEL = {
            timeout = 40,
            onTimeout = "SELECT",
            exit = function() TravelController.reset(ctx) end,
            update = function()
                perception:update(true)
                local found = self:candidates()
                if #found > 0 then
                    ctx.targets = found
                    return "ENGAGE"
                end

                local status = TargetTravel.step(ctx, nil)
                if status == "unknown" then
                    -- Ni cible ni region : ce mob n'existe pas ici. On
                    -- redemande un candidat plutot que d'insister.
                    self.objective = nil
                    return "SELECT"
                end
                if status == "unreachable" then
                    self.recovery:begin("movement_blocked")
                    return "RECOVERY"
                end
                return nil
            end,
        },

        ENGAGE = {
            timeout = 45,
            onTimeout = "SCAN",
            enter = function()
                perception:setCombat(true)
                if self.onEngage then self.onEngage() end
                if self:bringEnabled() then
                    ctx.bringActive = true
                    self.bring:attach()
                end
            end,
            exit = function()
                perception:setCombat(false)
                ctx.bringActive = false
                self.bring:detach()
                self.attack:clear(nil)
            end,
            update = function()
                if not ctx.player.alive() then
                    self.recovery:begin("player_dead")
                    return "RECOVERY"
                end

                perception:update(false)
                local found = self:candidates()
                ctx.targets = found
                if #found == 0 then return "SCAN" end

                if self:bringEnabled() then
                    local anchor = SafeCombatAnchor.compute(ctx)
                    if anchor then
                        self.bring:publishAnchor(anchor)
                        self.bring:update(found, self.objective)
                    end
                end

                local status = self.attack:engage(found, self.objective)
                if status == "killed" then
                    -- Un kill ne fait pas sortir de l'etat : on enchaine sur
                    -- la cible suivante sans repasser par le scan complet.
                    self.machine.enteredAt = os.clock()
                    return nil
                end
                if status == "idle" or status == "lost" then return "SCAN" end
                if status == "timeout" then return "SCAN" end
                return nil
            end,
        },

        RECOVERY = {
            enter = function()
                perception:setCombat(false)
                self.attack:clear("recuperation")
                self.bring:detach()
                ctx.bringActive = false
            end,
            update = function()
                local resume = self.recovery:step()
                if not resume then return nil end
                -- La recuperation raisonne en etats de QuestFarm : on les
                -- ramene sur ceux d'ici.
                if resume == "SERVER_HOP" then return "SERVER_HOP" end
                if resume == "SCAN_TARGETS" or resume == "BUILD_TARGET_GROUP"
                    or resume == "BRING_TARGETS" then
                    return "SCAN"
                end
                return "SELECT"
            end,
        },

        SERVER_HOP = {
            timeout = 30,
            onTimeout = "IDLE",
            enter = function()
                ctx.map:clear("changement de serveur")
                self.objective = nil
                pcall(function() ctx.server.hop(true) end)
            end,
            update = function() return nil end,
        },
    })

    self.machine:goTo("IDLE", "demarrage")
end

function TargetedFarm:update()
    if not self.ctx.flags.farming() then
        if not self.machine:is("IDLE") then self.machine:goTo("IDLE", "farm arrete") end
        return
    end
    self.perception:update(false)
    self.machine:update()
end

function TargetedFarm:stop()
    self.bring:detach()
    self.attack:clear("arret")
    TravelController.stop(self.ctx)
    self.objective = nil
    self.machine:goTo("IDLE", "arret")
end

function TargetedFarm:describe()
    return string.format("[%s] %s cible=%s", tostring(self.machine.current),
        self.label, self.objective and self.objective.TargetRaw or "-")
end

return TargetedFarm
