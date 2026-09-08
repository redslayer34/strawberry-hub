--=============================================================================
-- BOSS FARM — un boss se demande, il ne se ramasse pas au passage
--=============================================================================
--  Regle non negociable : un boss n'entre JAMAIS dans un bring ordinaire.
--  C'est ce qui desynchronisait les combats — un boss aspire au milieu d'un
--  paquet de mobs normaux, avec sa vie et ses degats, bloquait le farm sans
--  que rien ne le signale.
--
--  L'autorisation passe par un objectif synthetique portant AllowBoss, seul
--  drapeau que TargetValidator accepte pour lever l'exclusion. Aucun autre
--  module ne le pose.
--=============================================================================

local AttackController = require("AutomationCore.Combat.AttackController")
local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")
local StateMachine = require("AutomationCore.StateMachine")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")
local TravelController = require("AutomationCore.Movement.TravelController")

local BossFarm = {}
BossFarm.__index = BossFarm

function BossFarm.new(ctx, perception, recovery)
    local self = setmetatable({
        ctx = ctx,
        perception = perception,
        recovery = recovery,
        attack = AttackController.new(ctx),
        bossName = nil,
        objective = nil,
        lastSeenHealth = nil,
        killedAt = nil,
        machine = nil,
    }, BossFarm)

    self.machine = StateMachine.new("BossFarm", ctx)
    self:defineStates()
    return self
end

-- Le boss doit etre nomme explicitement. Sans appel a setBoss, ce module ne
-- fait rien du tout.
function BossFarm:setBoss(name)
    local canonical = Names.normalize(name)
    if not canonical then
        Log.Boss("nom de boss invalide :", tostring(name))
        return false
    end

    self.bossName = name
    self.objective = {
        Active = true,
        QuestName = "BossFarm",
        TargetRaw = name,
        TargetName = canonical,
        RequiredCount = 1,
        CurrentCount = 0,
        Remaining = 1,
        IsBossQuest = true,
        -- Le seul endroit du systeme qui pose ce drapeau.
        AllowBoss = true,
    }
    Log.Boss("cible :", name)
    return true
end

function BossFarm:candidates()
    if not self.objective then return {} end
    local raw = self.perception.scanner:candidatesFor(self.objective.TargetName)
    return TargetValidator.filter(self.ctx, raw, self.objective)
end

function BossFarm:defineStates()
    local ctx = self.ctx
    local perception = self.perception

    self.machine:defineAll({

        IDLE = {
            update = function()
                if not self.objective then return nil end
                return "SEARCH"
            end,
        },

        -- Recherche sur le serveur courant. Un boss absent n'est pas une
        -- panne locale : il est mort et pas encore reapparu, ou il n'existe
        -- pas ici. C'est le seul cas ou le changement de serveur est le bon
        -- reflexe plutot qu'un pis-aller.
        SEARCH = {
            timeout = 20,
            onTimeout = "AWAIT_RESPAWN",
            update = function()
                perception:update(true)
                local found = self:candidates()
                if #found > 0 then
                    Log.Boss("trouve --", #found, "instance(s)")
                    return "TRAVEL"
                end
                return nil
            end,
        },

        TRAVEL = {
            timeout = 60,
            onTimeout = "SEARCH",
            exit = function() TravelController.reset(ctx) end,
            update = function()
                local found = self:candidates()
                local boss = found[1]
                if not boss then return "SEARCH" end

                if TravelController.distanceTo(ctx, boss.position) <= ctx.cfg.Bring.Radius then
                    return "COMBAT"
                end

                local ok = TravelController.step(ctx, boss.position, {
                    lift = ctx.cfg.Anchor.Height,
                    validate = true,
                })
                if not ok or TravelController.isStuck(ctx) then
                    TravelController.reset(ctx)
                    return "SEARCH"
                end
                return nil
            end,
        },

        COMBAT = {
            -- Genereux : un boss encaisse longtemps. Le vrai garde-fou est
            -- l'absence de degats, gere par AttackController.
            timeout = 300,
            onTimeout = "SEARCH",
            enter = function() perception:setCombat(true) end,
            exit = function()
                perception:setCombat(false)
                self.attack:clear(nil)
            end,
            update = function()
                if not ctx.player.alive() then
                    self.recovery:begin("player_dead")
                    return "AWAIT_RESPAWN"
                end

                perception:update(false)
                local found = self:candidates()

                local status = self.attack:engage(found, self.objective)

                if status == "killed" then return "CONFIRM_KILL" end
                if status == "idle" then
                    -- Plus aucun boss valide alors qu'on en engageait un :
                    -- soit il est mort, soit il a disparu. CONFIRM_KILL
                    -- tranche sur une observation, pas sur une supposition.
                    return "CONFIRM_KILL"
                end
                if status == "timeout" then return "SEARCH" end
                return nil
            end,
        },

        -- On ne declare pas un boss mort parce qu'il a disparu de l'index :
        -- on verifie qu'aucune instance vivante ne subsiste, apres un delai.
        CONFIRM_KILL = {
            timeout = 10,
            onTimeout = "SEARCH",
            enter = function() self.killedAt = os.clock() end,
            update = function()
                if os.clock() - (self.killedAt or 0) < ctx.cfg.Boss.KillConfirmDelay then
                    return nil
                end

                perception:update(true)
                if #self:candidates() > 0 then
                    Log.Boss("encore vivant -- reprise du combat")
                    return "COMBAT"
                end

                Log.Boss("mort confirmee")
                return "AWAIT_RESPAWN"
            end,
        },

        AWAIT_RESPAWN = {
            timeout = 180,
            onTimeout = "SERVER_HOP",
            update = function()
                if self.machine:elapsed() % ctx.cfg.Boss.RespawnPoll > 0.5 then return nil end
                perception:update(true)
                if #self:candidates() > 0 then
                    Log.Boss("reapparu")
                    return "TRAVEL"
                end
                return nil
            end,
        },

        SERVER_HOP = {
            timeout = 30,
            onTimeout = "IDLE",
            enter = function()
                Log.Boss("absent de ce serveur -- changement")
                ctx.map:clear("boss absent")
                pcall(function() ctx.server.hop(true) end)
            end,
            update = function() return nil end,
        },

        -- Atteint par la machine a etats quand un update leve une erreur.
        -- Le controleur de recuperation raisonne en etats de QuestFarm : il
        -- FAUT les ramener sur ceux d'ici, sinon goTo retombe sur RECOVERY
        -- (etat inconnu) et la machine tourne en rond sans jamais avancer.
        RECOVERY = {
            update = function()
                local resume = self.recovery:step()
                if not resume then return nil end
                if resume == "SERVER_HOP" then return "SERVER_HOP" end
                if resume == "AWAIT_RESPAWN" then return "AWAIT_RESPAWN" end
                return "SEARCH"
            end,
        },
    })

    self.machine:goTo("IDLE", "demarrage")
end

function BossFarm:update()
    if not self.objective then return end
    self.perception:update(false)
    self.machine:update()
end

function BossFarm:stop()
    self.attack:clear("arret")
    TravelController.stop(self.ctx)
    self.objective = nil
    self.bossName = nil
    self.machine:goTo("IDLE", "arret")
end

function BossFarm:describe()
    return string.format("[%s] boss=%s", tostring(self.machine.current),
        tostring(self.bossName))
end

return BossFarm
