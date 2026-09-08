--=============================================================================
-- BRING CONTROLLER — amener les cibles, sans decider lesquelles
--=============================================================================
--  Ce module ne choisit RIEN. Il recoit une liste deja filtree et se contente
--  de la placer. Le flux impose est :
--
--      QuestDetector -> TargetSelector -> TargetValidator -> BringController
--
--  Deux differences de fond avec l'ancien Move.bringMobs :
--
--  1. EMPLACEMENTS DISTINCTS. L'ancien code ecrivait le meme CFrame pour tous
--     les mobs : ils se chevauchaient, se repoussaient, et le serveur les
--     renvoyait au loin. Ici chaque cible recoit son emplacement autour de
--     l'ancre, et l'emplacement d'un mob mort est rendu au suivant.
--
--  2. PULL LIMIT. Un mob tres eloigne n'est pas teleporte a travers la carte
--     (le serveur rejette le saut, et l'anti-triche le remarque). On demande
--     au TravelController de rapprocher le JOUEUR, puis on rescanne.
--=============================================================================

local Log = require("AutomationCore.Log")
local SafeCombatAnchor = require("AutomationCore.Movement.SafeCombatAnchor")
local TargetValidator = require("AutomationCore.Combat.TargetValidator")

local BringController = {}
BringController.__index = BringController

function BringController.new(ctx)
    return setmetatable({
        ctx = ctx,
        slots = {},        -- index -> { model = ..., since = ... }
        assigned = {},     -- model -> index
        lastRun = 0,
        lastAnchor = nil,
        moved = 0,
        tooFar = 0,
    }, BringController)
end

---------------------------------------------------------------------------
-- Emplacements
---------------------------------------------------------------------------

-- Repartition reguliere sur un cercle sous l'ancre. Avec MaxTargets = 6 cela
-- donne exactement avant / arriere / gauche / droite plus deux intermediaires,
-- mais la formule reste valable pour n'importe quel nombre d'emplacements.
function BringController:slotOffset(index)
    local cfg = self.ctx.cfg.Bring
    local count = math.max(1, cfg.MaxTargets)
    local angle = (index - 1) * (2 * math.pi / count)
    return Vector3.new(
        math.cos(angle) * cfg.SlotSpacing,
        -cfg.Height,
        math.sin(angle) * cfg.SlotSpacing)
end

function BringController:slotPosition(anchor, index)
    return anchor.Position + self:slotOffset(index)
end

-- Libere les emplacements dont l'occupant est mort, a disparu, ou n'est plus
-- une cible valide. C'est ce qui permet la reattribution demandee.
function BringController:reclaim(quest)
    local ctx = self.ctx
    for index, slot in pairs(self.slots) do
        local model = slot.model
        local drop = false

        if not model or not model.Parent then
            drop = true
        else
            local entry = slot.entry
            if not entry or not TargetValidator.stillValid(ctx, entry, quest) then
                drop = true
            end
        end

        if drop then
            if model then self.assigned[model] = nil end
            self.slots[index] = nil
        end
    end
end

function BringController:freeSlot()
    local count = math.max(1, self.ctx.cfg.Bring.MaxTargets)
    for index = 1, count do
        if not self.slots[index] then return index end
    end
    return nil
end

---------------------------------------------------------------------------
-- Cycle
---------------------------------------------------------------------------

-- targets : liste DEJA validee. quest : QuestState, uniquement pour
-- revalider les occupants d'un tour a l'autre.
-- Renvoie un compte-rendu : { moved, tooFar, placed, anchor, status }.
function BringController:update(targets, quest)
    local ctx = self.ctx
    local cfg = ctx.cfg.Bring
    local report = { moved = 0, tooFar = 0, placed = 0, status = "idle" }

    local now = os.clock()
    if now - self.lastRun < cfg.Interval then
        report.status = "throttled"
        return report
    end
    self.lastRun = now

    if not targets or #targets == 0 then
        self:reclaim(quest)
        report.status = "no_targets"
        return report
    end

    -- L'ancre est recalculee ici, pas conservee : c'est elle qui garantit que
    -- les emplacements restent au-dessus du sol quand le paquet se deplace.
    local anchor = SafeCombatAnchor.compute(ctx)
    if not anchor then
        report.status = "no_anchor"
        return report
    end
    report.anchor = anchor

    -- Un deplacement franc de l'ancre rend les affectations caduques : les
    -- emplacements ne sont plus au meme endroit.
    if self.lastAnchor and (anchor.Position - self.lastAnchor.Position).Magnitude > cfg.SlotSpacing * 2 then
        table.clear(self.slots)
        table.clear(self.assigned)
    end
    self.lastAnchor = anchor

    self:reclaim(quest)

    local origin = anchor.Position
    local reachable = 0

    for _, entry in ipairs(targets) do
        local model = entry.model
        local root = entry.root
        if model and model.Parent and root and root.Parent then
            local distance = (root.Position - origin).Magnitude

            if distance > cfg.PullLimit then
                -- Trop loin : on ne le tire pas. Le joueur ira a lui.
                report.tooFar = report.tooFar + 1
            elseif distance > cfg.Radius then
                -- Hors rayon de collecte, mais pas assez loin pour declencher
                -- un voyage : on l'ignore simplement ce tour-ci.
                reachable = reachable + 1
            else
                reachable = reachable + 1

                local index = self.assigned[model]
                if not index then
                    index = self:freeSlot()
                    if index then
                        self.assigned[model] = index
                        self.slots[index] = { model = model, entry = entry, since = now }
                    end
                end

                if index then
                    report.placed = report.placed + 1
                    local goal = self:slotPosition(anchor, index)

                    -- Deja en place : reecrire sa position a 10 Hz revient a
                    -- lutter contre le serveur pour rien.
                    if (root.Position - goal).Magnitude > cfg.DeadZone then
                        local ok = SafeCombatAnchor.validatePosition(ctx, goal)
                        if ok then
                            root.CanCollide = false
                            root.CFrame = CFrame.new(goal)
                            root.AssemblyLinearVelocity = Vector3.zero
                            report.moved = report.moved + 1
                        else
                            -- Emplacement devenu mauvais : on force le
                            -- recalcul de l'ancre au tour suivant.
                            SafeCombatAnchor.invalidate(ctx, "emplacement invalide")
                        end
                    end
                end
            end
        end
    end

    self.moved = report.moved
    self.tooFar = report.tooFar

    -- Aucune cible atteignable alors qu'il en existe : c'est le signal du
    -- PullLimit. QuestFarm doit rapprocher le joueur et recalculer le paquet.
    if reachable == 0 and report.tooFar > 0 then
        report.status = "too_far"
        Log.Bring(report.tooFar, "cible(s) hors de portee -- rapprochement du joueur")
    elseif report.placed > 0 then
        report.status = "bringing"
    else
        report.status = "no_targets"
    end

    return report
end

-- Le joueur est maintenu sur l'ancre par le runtime (60 Hz). On lui donne
-- l'ancre et le pilote de bring, on ne duplique pas sa boucle.
function BringController:attach()
    local ctx = self.ctx
    local state = ctx.legacy.State
    state.bringDriver = function()
        local quest = ctx.quest
        self:update(ctx.targets, quest)
    end
end

function BringController:detach()
    local ctx = self.ctx
    ctx.legacy.State.bringDriver = nil
    ctx.legacy.State.bringAnchor = nil
    table.clear(self.slots)
    table.clear(self.assigned)
end

-- Position de vol du joueur, lue par le runtime a chaque frame.
function BringController:publishAnchor(anchor)
    self.ctx.legacy.State.bringAnchor = anchor
end

function BringController:describe()
    local count = 0
    for _ in pairs(self.slots) do count = count + 1 end
    return string.format("%d emplacement(s) occupe(s), %d deplace(s), %d hors portee",
        count, self.moved, self.tooFar)
end

return BringController
