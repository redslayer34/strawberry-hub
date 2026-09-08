--=============================================================================
-- QUEST FARM — la machine a etats du farm par quete
--=============================================================================
--  Chaque etat declare son entree, son timeout, sa condition de succes, sa
--  condition d'echec et son etat suivant. Aucun etat ne boucle sur place sans
--  limite : un blocage devient une transition vers RECOVERY, pas un gel.
--
--  Le flux de selection des cibles est impose et ne peut pas etre court-
--  circuite :
--
--      DETECT_QUEST -> SCAN_TARGETS -> BUILD_TARGET_GROUP -> BRING_TARGETS
--          (QuestDetector) (EnemyScanner)  (TargetValidator)  (BringController)
--
--  BringController ne recoit donc jamais autre chose qu'une liste deja
--  validee contre la quete active.
--=============================================================================

local AttackController = require("AutomationCore.Combat.AttackController")
local BringController = require("AutomationCore.Combat.BringController")
local Log = require("AutomationCore.Log")
local QuestTravel = require("AutomationCore.Movement.QuestTravel")
local RoutePlanner = require("AutomationCore.Farming.RoutePlanner")
local SafeCombatAnchor = require("AutomationCore.Movement.SafeCombatAnchor")
local StateMachine = require("AutomationCore.StateMachine")
local TargetTravel = require("AutomationCore.Movement.TargetTravel")
local TravelController = require("AutomationCore.Movement.TravelController")

local QuestFarm = {}
QuestFarm.__index = QuestFarm

function QuestFarm.new(ctx, perception, recovery)
    local self = setmetatable({
        ctx = ctx,
        perception = perception,
        recovery = recovery,
        bring = BringController.new(ctx),
        attack = AttackController.new(ctx),
        plan = nil,
        machine = nil,
    }, QuestFarm)

    self.machine = StateMachine.new("QuestFarm", ctx)
    self:defineStates()
    return self
end

function QuestFarm:bringEnabled()
    return self.ctx.legacyConfig.Farming.BringMob == true
end

-- Raccourci : demande une recuperation avec une cause explicite.
function QuestFarm:recover(cause)
    self.recovery:begin(cause)
    return "RECOVERY"
end

---------------------------------------------------------------------------
-- Etats
---------------------------------------------------------------------------

function QuestFarm:defineStates()
    local ctx = self.ctx
    local perception = self.perception

    self.machine:defineAll({

        -----------------------------------------------------------------
        IDLE = {
            update = function()
                if not ctx.flags.farming() then return nil end
                return "CHECK_REQUIREMENTS"
            end,
        },

        -----------------------------------------------------------------
        -- Verifie ce sans quoi rien d'autre n'a de sens. Mieux vaut
        -- attendre ici que partir en detection sur un monde a moitie charge.
        CHECK_REQUIREMENTS = {
            timeout = 30,
            onTimeout = function() return self:recover("map_not_loaded") end,
            update = function()
                if not ctx.player.alive() then return self:recover("player_dead") end
                if not ctx.world.enemies() then return nil end
                if not ctx.world.locations() then return nil end
                return "DETECT_SEA"
            end,
        },

        -----------------------------------------------------------------
        DETECT_SEA = {
            timeout = 10,
            onTimeout = "DETECT_ISLAND",
            update = function()
                perception:detectSea()
                if not ctx.sea then return nil end
                return "DETECT_ISLAND"
            end,
        },

        -----------------------------------------------------------------
        DETECT_ISLAND = {
            timeout = 10,
            onTimeout = "DETECT_QUEST",
            update = function()
                perception:detectIsland()
                return "DETECT_QUEST"
            end,
        },

        -----------------------------------------------------------------
        -- Pivot de toute la machine. Une quete active et lisible court-
        -- circuite toute la partie "aller prendre une quete".
        DETECT_QUEST = {
            timeout = 20,
            onTimeout = function() return self:recover("quest_lost") end,
            update = function()
                local quest = perception:detectQuest(true)

                if quest.Active and quest.TargetName then
                    if quest.Remaining <= 0 then return "TURN_IN" end
                    return "SCAN_TARGETS"
                end

                -- Quete active mais objectif illisible : on ne devine pas.
                -- On l'abandonne et on en reprend une proprement, plutot que
                -- de farmer a l'aveugle.
                if quest.Active and not quest.TargetName then
                    Log.Quest("objectif illisible -- abandon de la quete")
                    QuestTravel.abandon(ctx)
                    return nil
                end

                -- Aucune quete : on en planifie une.
                if RoutePlanner.isStale(ctx, self.plan, perception.scanner) then
                    self.plan = RoutePlanner.plan(ctx, perception.scanner)
                end
                if not self.plan then return nil end
                return "FIND_QUEST_GIVER"
            end,
        },

        -----------------------------------------------------------------
        FIND_QUEST_GIVER = {
            timeout = 12,
            onTimeout = function() return self:recover("quest_giver_missing") end,
            enter = function()
                if not self.plan then return end
                -- Le repli statique est passe au resolveur mais reste au
                -- niveau de confiance le plus bas : il ne sert que si aucun
                -- PNJ ne correspond.
                perception:setQuestGiverHints(self.plan.hints, self.plan.giverFallback)
            end,
            update = function()
                if not self.plan then return "DETECT_QUEST" end
                local position = perception:refreshQuestGiver()
                if not position then return nil end
                return "TRAVEL_TO_QUEST"
            end,
        },

        -----------------------------------------------------------------
        TRAVEL_TO_QUEST = {
            timeout = 45,
            onTimeout = function() return self:recover("movement_blocked") end,
            exit = function() TravelController.reset(ctx) end,
            update = function()
                -- Une quete apparue entre-temps (ramassee par un autre
                -- moyen) rend le voyage inutile.
                if perception:detectQuest().Active then return "DETECT_QUEST" end

                local status = QuestTravel.step(ctx, self.plan)
                if status == "arrived" then return "ACCEPT_QUEST" end
                if status == "unreachable" then return self:recover("quest_giver_missing") end
                if status == "unknown" then return "FIND_QUEST_GIVER" end
                return nil
            end,
        },

        -----------------------------------------------------------------
        -- La prise de quete n'est pas instantanee : on la demande, puis on
        -- attend la confirmation par l'UI. Sans cette attente, l'ancien code
        -- repartait immediatement et redemandait en boucle.
        ACCEPT_QUEST = {
            timeout = 8,
            onTimeout = function() return self:recover("quest_not_taken") end,
            enter = function()
                QuestTravel.accept(ctx, self.plan)
            end,
            update = function()
                local quest = perception:detectQuest(true)
                if quest.Active then return "DETECT_QUEST" end

                -- On re-demande une seule fois par seconde tant que le PNJ
                -- est a portee : le remote echoue si l'on s'est eloigne.
                if self.machine:elapsed() > 2 then
                    QuestTravel.accept(ctx, self.plan)
                    self.machine.enteredAt = os.clock() - 2
                end
                return nil
            end,
        },

        -----------------------------------------------------------------
        SCAN_TARGETS = {
            timeout = 12,
            onTimeout = function() return self:recover("target_missing") end,
            update = function()
                perception:update(true)

                if not ctx.quest.Active then return self:recover("quest_lost") end
                if ctx.quest.Remaining <= 0 then return "CHECK_PROGRESS" end

                if #ctx.targets > 0 then
                    Log.Target("Found", #ctx.targets, "valid targets")
                    return "BUILD_TARGET_GROUP"
                end

                -- Rien de valide : la zone n'est peut-etre pas active.
                return "ACTIVATE_SPAWN"
            end,
        },

        -----------------------------------------------------------------
        -- Beaucoup de spawns ne se declenchent qu'a l'approche du joueur.
        -- Avant de conclure a l'absence, on va sur place.
        ACTIVATE_SPAWN = {
            timeout = 35,
            onTimeout = function() return self:recover("target_missing") end,
            exit = function() TravelController.reset(ctx) end,
            update = function()
                local status = TargetTravel.step(ctx, self.plan)

                -- Un rescan a chaque pas : des que la zone se peuple, on
                -- repart sans attendre la fin du voyage.
                perception:update(true)
                if #ctx.targets > 0 then
                    Log.Target("zone activee --", #ctx.targets, "cible(s)")
                    return "BUILD_TARGET_GROUP"
                end

                if status == "unknown" then
                    -- Aucune destination : ni cible, ni region, ni ile. Le
                    -- plan lui-meme est douteux.
                    self.plan = nil
                    return self:recover("target_missing")
                end
                if status == "unreachable" then
                    return self:recover("movement_blocked")
                end
                return nil
            end,
        },

        -----------------------------------------------------------------
        -- Constitue le groupe a engager. C'est ici, et nulle part ailleurs,
        -- que la liste transmise au bring est arretee.
        BUILD_TARGET_GROUP = {
            timeout = 8,
            onTimeout = "SCAN_TARGETS",
            update = function()
                perception:refreshSpawnRegion()
                perception:refreshTargets()

                if #ctx.targets == 0 then return "SCAN_TARGETS" end
                if ctx.quest.Remaining <= 0 then return "CHECK_PROGRESS" end

                -- L'ancre doit exister avant le bring : sans elle, les mobs
                -- seraient places sur une position non validee.
                if self:bringEnabled() then
                    local anchor = SafeCombatAnchor.compute(ctx, true)
                    if not anchor then return self:recover("invalid_position") end
                    self.bring:publishAnchor(anchor)
                    Log.Bring("Building group of",
                        math.min(#ctx.targets, ctx.cfg.Bring.MaxTargets))
                    return "BRING_TARGETS"
                end

                return "ATTACK"
            end,
        },

        -----------------------------------------------------------------
        BRING_TARGETS = {
            timeout = 15,
            onTimeout = function() return self:recover("target_returned_spawn") end,
            enter = function()
                ctx.bringActive = true
                self.bring:attach()
                perception:setCombat(true)
            end,
            exit = function()
                ctx.bringActive = false
                self.bring:detach()
            end,
            update = function()
                if not ctx.quest.Active then return self:recover("quest_lost") end
                if ctx.quest.Remaining <= 0 then return "CHECK_PROGRESS" end

                perception:refreshTargets()
                if #ctx.targets == 0 then return "SCAN_TARGETS" end

                local anchor = SafeCombatAnchor.compute(ctx)
                if not anchor then return self:recover("invalid_position") end
                self.bring:publishAnchor(anchor)

                local report = self.bring:update(ctx.targets, ctx.quest)

                if report.status == "too_far" then
                    -- PullLimit : on ne tire pas le mob a travers la carte,
                    -- c'est le joueur qui se deplace, puis on recalcule.
                    return "ACTIVATE_SPAWN"
                end
                if report.status == "no_anchor" then
                    return self:recover("invalid_position")
                end
                if report.status == "no_targets" then
                    return "SCAN_TARGETS"
                end

                -- Des qu'une cible est en place, on frappe. L'etat ATTACK
                -- garde le bring actif : les deux tournent ensemble.
                if report.placed > 0 then return "ATTACK" end
                return nil
            end,
        },

        -----------------------------------------------------------------
        ATTACK = {
            timeout = 30,
            onTimeout = function() return self:recover("combat_interrupted") end,
            enter = function()
                perception:setCombat(true)
                -- Le bring reste actif pendant l'attaque quand il est
                -- demande : sinon les mobs repartent des le premier coup.
                if self:bringEnabled() then
                    ctx.bringActive = true
                    self.bring:attach()
                end
            end,
            exit = function()
                perception:setCombat(false)
                self.attack:clear(nil)
            end,
            update = function()
                if not ctx.player.alive() then return self:recover("player_dead") end
                if not ctx.quest.Active then return self:recover("quest_lost") end

                perception:refreshTargets()
                if ctx.quest.Remaining <= 0 then return "CHECK_PROGRESS" end

                if self:bringEnabled() then
                    local anchor = SafeCombatAnchor.compute(ctx)
                    if anchor then self.bring:publishAnchor(anchor) end
                end

                local status = self.attack:engage(ctx.targets, ctx.quest)

                if status == "killed" then return "CHECK_PROGRESS" end
                if status == "idle" then return "SCAN_TARGETS" end
                if status == "lost" then
                    -- Cible perdue sans etre morte : elle est peut-etre
                    -- repartie au spawn.
                    return "BUILD_TARGET_GROUP"
                end
                if status == "timeout" then return self:recover("combat_interrupted") end
                if status == "blocked" then return nil end

                -- L'etat ATTACK ne se quitte pas apres chaque coup : on
                -- reste ici tant qu'une cible valide est engagee.
                return nil
            end,
        },

        -----------------------------------------------------------------
        CHECK_PROGRESS = {
            timeout = 6,
            onTimeout = "DETECT_QUEST",
            update = function()
                local quest = perception:detectQuest(true)

                if not quest.Active then
                    -- La quete a disparu : soit elle vient d'etre validee,
                    -- soit elle a ete perdue. DETECT_QUEST tranchera.
                    return "DETECT_QUEST"
                end

                if quest.Remaining <= 0 then return "TURN_IN" end

                if #ctx.targets > 0 then
                    return self:bringEnabled() and "BRING_TARGETS" or "ATTACK"
                end
                return "SCAN_TARGETS"
            end,
        },

        -----------------------------------------------------------------
        -- La plupart des quetes se valident seules au dernier kill. On
        -- attend cette validation ; si elle ne vient pas, on retourne voir
        -- le donneur, certaines quetes l'exigent.
        TURN_IN = {
            timeout = 20,
            onTimeout = function() return self:recover("quest_lost") end,
            enter = function()
                Log.Quest("Complete")
                perception:setCombat(false)
            end,
            update = function()
                local quest = perception:detectQuest(true)

                if not quest.Active then
                    Log.Quest("recompense validee")
                    self.plan = nil
                    return "DETECT_QUEST"
                end

                if self.machine:elapsed() > 4 and ctx.questGiver then
                    local status = QuestTravel.step(ctx, self.plan)
                    if status == "unreachable" then return "DETECT_QUEST" end
                end
                return nil
            end,
        },

        -----------------------------------------------------------------
        RECOVERY = {
            -- Pas de timeout : c'est le controleur qui decide de l'escalade,
            -- y compris du moment ou il renonce.
            enter = function()
                perception:setCombat(false)
                self.attack:clear("recuperation")
                self.bring:detach()
                ctx.bringActive = false
            end,
            update = function()
                return self.recovery:step()
            end,
        },

        -----------------------------------------------------------------
        SERVER_HOP = {
            timeout = 30,
            onTimeout = "IDLE",
            enter = function()
                Log.ServerHop("changement de serveur demande")
                -- Tout ce qui a ete appris ici sera faux la-bas.
                ctx.map:clear("changement de serveur")
                ctx.region = nil
                ctx.questGiver = nil
                self.plan = nil
                pcall(function() ctx.server.hop(true) end)
            end,
            update = function() return nil end,
        },

        -----------------------------------------------------------------
        -- Point d'accroche des objectifs speciaux (CDK, quetes d'evenement).
        -- Le core y bascule sur demande explicite ; QuestFarm ne s'y rend
        -- jamais de lui-meme.
        SPECIAL_OBJECTIVE = {
            timeout = 600,
            onTimeout = "DETECT_QUEST",
            update = function()
                local handler = ctx.specialObjective
                if not handler then return "DETECT_QUEST" end
                local status = handler:step()
                if status == "done" or status == "failed" then
                    ctx.specialObjective = nil
                    return "DETECT_QUEST"
                end
                return nil
            end,
        },
    })

    self.machine:goTo("IDLE", "demarrage")
end

---------------------------------------------------------------------------
-- Cycle
---------------------------------------------------------------------------

function QuestFarm:update()
    local ctx = self.ctx

    -- Arret par l'UI : on rend la main proprement, sans laisser d'ancre ni
    -- de pilote de bring derriere nous.
    if not ctx.flags.farming() then
        if not self.machine:is("IDLE") then
            self.machine:goTo("IDLE", "farm arrete")
        end
        return
    end

    -- Causes implicites, detectees avant la machine : le joueur mort ou la
    -- carte non chargee court-circuitent l'etat courant.
    local implicit = self.recovery:detectImplicit(ctx)
    if implicit and not self.machine:is("RECOVERY") and not self.machine:is("SERVER_HOP") then
        self.recovery:begin(implicit)
        self.machine:goTo("RECOVERY", implicit)
        return
    end

    self.perception:update(false)
    self.machine:update()
end

function QuestFarm:stop()
    self.bring:detach()
    self.attack:clear("arret")
    TravelController.stop(self.ctx)
    self.machine:goTo("IDLE", "arret")
end

function QuestFarm:describe()
    return string.format("[%s] %s | %s",
        tostring(self.machine.current),
        self.perception:describe(),
        self.bring:describe())
end

return QuestFarm
