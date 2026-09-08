--=============================================================================
-- RECOVERY CONTROLLER — remettre le farm en marche, sans repartir de zero
--=============================================================================
--  Un vrai controleur de recuperation, pas un `return` qui laisse la boucle
--  retomber sur ses pieds au tour suivant.
--
--  Echelle d'escalade, toujours dans cet ordre :
--
--      1. rescan local          -- l'index est peut-etre juste perime
--      2. recalcul des donnees  -- region, ancre, affectations
--      3. reprise de l'etat courant si la cause a disparu
--      4. retour a la detection (DETECT_*) si elle persiste
--      5. changement de serveur, uniquement en dernier recours
--
--  Le changement de serveur coute une minute de chargement : il n'intervient
--  qu'apres avoir epuise les barreaux precedents, et jamais pour une cause
--  qui se resout localement (un mob mort pendant le bring, par exemple).
--=============================================================================

local Log = require("AutomationCore.Log")
local SafeCombatAnchor = require("AutomationCore.Movement.SafeCombatAnchor")
local TravelController = require("AutomationCore.Movement.TravelController")

local RecoveryController = {}
RecoveryController.__index = RecoveryController

-- Classification des causes. `local` = se resout sur place ; `detect` =
-- impose une redetection ; `fatal` = seul cas ou le serveur est en cause.
local CAUSES = {
    quest_lost            = { class = "detect", resume = "DETECT_QUEST" },
    quest_not_taken       = { class = "detect", resume = "FIND_QUEST_GIVER" },
    quest_giver_missing   = { class = "detect", resume = "FIND_QUEST_GIVER", invalidateGiver = true },
    target_missing        = { class = "local",  resume = "SCAN_TARGETS" },
    target_died_in_bring  = { class = "local",  resume = "BUILD_TARGET_GROUP" },
    target_returned_spawn = { class = "local",  resume = "BRING_TARGETS" },
    player_dead           = { class = "wait",   resume = "DETECT_QUEST" },
    player_respawned      = { class = "local",  resume = "DETECT_QUEST" },
    server_changed        = { class = "detect", resume = "DETECT_SEA", wipe = true },
    map_not_loaded        = { class = "wait",   resume = "DETECT_ISLAND" },
    invalid_position      = { class = "local",  resume = "BUILD_TARGET_GROUP", invalidateAnchor = true },
    movement_blocked      = { class = "local",  resume = "TRAVEL_TO_QUEST", resetTravel = true },
    combat_interrupted    = { class = "local",  resume = "SCAN_TARGETS" },
    boss_missing          = { class = "fatal",  resume = "DETECT_QUEST" },
    objective_missing     = { class = "detect", resume = "SPECIAL_OBJECTIVE" },
    unknown               = { class = "detect", resume = "DETECT_QUEST" },
}

function RecoveryController.new(ctx, perception)
    return setmetatable({
        ctx = ctx,
        perception = perception,
        cause = nil,
        attempts = 0,
        redetects = 0,
        failures = 0,
        lastAttempt = 0,
        enteredAt = 0,
    }, RecoveryController)
end

-- Declare la cause avant d'entrer dans l'etat RECOVERY. Une cause differente
-- de la precedente remet les compteurs a zero : deux pannes distinctes ne
-- doivent pas s'additionner jusqu'au server hop.
function RecoveryController:begin(cause)
    cause = CAUSES[cause] and cause or "unknown"
    if cause ~= self.cause then
        self.cause = cause
        self.attempts = 0
        self.redetects = 0
    end
    self.enteredAt = os.clock()
    self.ctx.stats.recoveries = self.ctx.stats.recoveries + 1
    Log.Recovery("cause :", cause)
end

function RecoveryController:reset()
    self.cause = nil
    self.attempts = 0
    self.redetects = 0
    self.failures = 0
end

---------------------------------------------------------------------------
-- Barreaux
---------------------------------------------------------------------------

-- 1 et 2 : rescan et recalcul. Toujours tentes, quelle que soit la cause.
function RecoveryController:localRepair(profile)
    local ctx = self.ctx

    if profile.wipe then
        ctx.map:clear("recuperation apres changement de serveur")
    end
    if profile.invalidateAnchor then
        SafeCombatAnchor.invalidate(ctx, "recuperation")
    end
    if profile.resetTravel then
        TravelController.stop(ctx)
    end
    if profile.invalidateGiver then
        ctx.map:invalidate("QuestGivers", nil, "recuperation")
        ctx.questGiver = nil
    end

    -- Le rescan force ignore la cadence : on a besoin d'une image fraiche
    -- maintenant, pas au prochain intervalle.
    self.perception:rescan("recuperation (" .. tostring(self.cause) .. ")")
end

-- 3 : la cause a-t-elle disparu ?
function RecoveryController:resolved()
    local ctx = self.ctx
    local cause = self.cause

    if cause == "player_dead" then
        return ctx.player.alive()
    elseif cause == "map_not_loaded" then
        return ctx.world.enemies() ~= nil and ctx.world.locations() ~= nil
    elseif cause == "target_missing" or cause == "target_died_in_bring"
        or cause == "target_returned_spawn" or cause == "combat_interrupted" then
        return #ctx.targets > 0
    elseif cause == "quest_lost" or cause == "quest_not_taken" then
        return ctx.quest ~= nil and ctx.quest.Active
    elseif cause == "quest_giver_missing" then
        return ctx.questGiver ~= nil
    elseif cause == "invalid_position" then
        return SafeCombatAnchor.compute(ctx, true) ~= nil
    elseif cause == "server_changed" then
        return ctx.sea ~= nil and ctx.island ~= nil
    end

    return false
end

---------------------------------------------------------------------------
-- Cycle
---------------------------------------------------------------------------

-- Un pas de recuperation. Renvoie l'etat a rejoindre, ou nil pour rester
-- dans RECOVERY encore un tour.
function RecoveryController:step()
    local ctx = self.ctx
    local cfg = ctx.cfg.Recovery
    local profile = CAUSES[self.cause or "unknown"]

    local now = os.clock()
    if now - self.lastAttempt < cfg.Cooldown then return nil end
    self.lastAttempt = now

    self.attempts = self.attempts + 1

    -- Le joueur mort n'est pas une panne : on attend le respawn, sans rien
    -- recalculer (tout serait a refaire apres).
    if self.cause == "player_dead" then
        if ctx.player.alive() then
            Log.Recovery("joueur reapparu -- reprise")
            self:reset()
            return profile.resume
        end
        return nil
    end

    -- Barreaux 1 et 2.
    self:localRepair(profile)

    -- Barreau 3 : reprise sur place.
    if self:resolved() then
        Log.Recovery("resolu apres", self.attempts, "tentative(s) -- reprise en", profile.resume)
        self:reset()
        return profile.resume
    end

    -- Barreau 4 : redetection complete.
    if self.attempts >= cfg.MaxLocalAttempts then
        self.redetects = self.redetects + 1
        self.attempts = 0
        self.failures = self.failures + 1

        if self.redetects <= cfg.MaxRedetects then
            Log.Recovery("rescan insuffisant -- redetection complete")
            ctx.map:clear("redetection")
            ctx.region = nil
            ctx.questGiver = nil
            return "DETECT_SEA"
        end
    end

    -- Barreau 5 : changement de serveur. Reserve aux causes qui ne peuvent
    -- pas se resoudre ici — typiquement un boss absent de ce serveur.
    local hopWorthy = profile.class == "fatal" or self.failures >= cfg.HopAfterFailures
    if hopWorthy then
        Log.Recovery("epuise localement (" .. tostring(self.cause) .. ") -- changement de serveur")
        self:reset()
        return "SERVER_HOP"
    end

    return nil
end

-- Detecte les causes que personne n'a signalees explicitement. Appelee a
-- chaque tour du core, avant la machine a etats.
function RecoveryController:detectImplicit(ctx)
    if not ctx.player.alive() then return "player_dead" end
    if not ctx.world.enemies() then return "map_not_loaded" end
    return nil
end

return RecoveryController
