--=============================================================================
-- ATTACK CONTROLLER — engager une cible, un pas a la fois
--=============================================================================
--  L'ancien `engage()` etait une boucle `while` bloquante : tant qu'elle
--  tournait, rien d'autre ne pouvait s'executer — ni la relecture de la
--  quete, ni la detection d'un changement d'ile, ni la recuperation. Un mob
--  inatteignable gelait tout le farm jusqu'a son timeout.
--
--  Ici chaque appel fait un pas et rend la main. La machine a etats garde le
--  controle, et le verrouillage sur une cible (qui rend le farm efficace)
--  est conserve : on ne rebalaie pas le Workspace entre deux coups.
--
--  Avant chaque coup : ValidateTarget puis ValidateCombatState. Aucune
--  operation n'est faite sur une reference qui a vieilli.
--=============================================================================

local CombatPositionController = require("AutomationCore.Combat.CombatPositionController")
local Log = require("AutomationCore.Log")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")

local AttackController = {}
AttackController.__index = AttackController

function AttackController.new(ctx)
    return setmetatable({
        ctx = ctx,
        entry = nil,
        lastHealth = nil,
        lastProgress = 0,
        lastStrike = 0,
        engagedAt = 0,
        kills = 0,
    }, AttackController)
end

function AttackController:target() return self.entry end

function AttackController:clear(reason)
    if self.entry and reason then
        Log.Combat("cible relachee --", reason)
    end
    self.entry = nil
    self.lastHealth = nil
    self.ctx.attack.release()
end

function AttackController:setTarget(entry)
    if self.entry and self.entry.model == entry.model then return end
    self.entry = entry
    self.lastHealth = entry.humanoid and entry.humanoid.Health or nil
    self.lastProgress = os.clock()
    self.engagedAt = os.clock()
    Log.Combat("Started --", entry.name)
end

-- Choisit la cible la plus proche parmi une liste DEJA validee. Aucun
-- filtrage supplementaire ici : ce module ne juge pas de la validite.
function AttackController:pick(targets)
    local here = self.ctx:pos()
    if not here or not targets or #targets == 0 then return nil end

    local best, bestDist
    for _, entry in ipairs(targets) do
        local d = (entry.position - here).Magnitude
        if not bestDist or d < bestDist then best, bestDist = entry, d end
    end
    return best
end

-- Un pas de combat.
-- Renvoie "attacking" | "killed" | "lost" | "timeout" | "blocked" | "idle".
function AttackController:step(quest)
    local ctx = self.ctx
    local entry = self.entry

    if not entry then return "idle" end

    -- 1. La cible est-elle encore une cible ? Une quete qui change en cours
    -- de combat doit interrompre le coup en cours, pas le finir.
    local valid, reason = TargetValidator.stillValid(ctx, entry, quest)
    if not valid then
        local dead = entry.humanoid and entry.humanoid.Health <= 0
        self:clear(nil)
        if dead then
            self.kills = self.kills + 1
            ctx.stats.kills = ctx.stats.kills + 1
            return "killed"
        end
        Log.Combat("cible perdue --", reason)
        return "lost"
    end

    -- 2. Sommes-nous en etat de frapper ?
    local ready, why = CombatPositionController.validateCombatState(ctx)
    if not ready then
        return "blocked", why
    end

    -- 3. Progression : c'est la perte de vie qui prouve que le combat avance.
    -- Sans ce controle, un mob invulnerable ou hors sync bloquait la boucle.
    local health = entry.humanoid.Health
    if self.lastHealth and health < self.lastHealth then
        self.lastProgress = os.clock()
    end
    self.lastHealth = health

    if os.clock() - self.lastProgress > ctx.cfg.Combat.EngageTimeout then
        Log.Combat("aucun degat depuis", ctx.cfg.Combat.EngageTimeout, "s -- abandon")
        self:clear(nil)
        return "timeout"
    end

    -- 4. Placement puis frappe, a la cadence configuree.
    local now = os.clock()
    if now - self.lastStrike < ctx.cfg.Combat.AttackDelay then
        return "attacking"
    end
    self.lastStrike = now

    -- En mode bring les mobs viennent a nous : on reste sur l'ancre plutot
    -- que de courir apres chacun.
    if not ctx.bringActive then
        CombatPositionController.hold(ctx, entry)
    end

    ctx.attack.strike(entry.model)
    return "attacking"
end

-- Engage la meilleure cible disponible et fait un pas. Point d'entree unique
-- de l'etat ATTACK.
function AttackController:engage(targets, quest)
    if not self.entry then
        local pick = self:pick(targets)
        if not pick then return "idle" end
        self:setTarget(pick)
    end
    return self:step(quest)
end

return AttackController
